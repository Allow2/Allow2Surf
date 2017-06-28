/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */


import UIKit
import CoreData
import Foundation
import Shared

class Bookmark: NSManagedObject, WebsitePresentable {
    
    @NSManaged var isFolder: Bool
    @NSManaged var title: String?
    @NSManaged var customTitle: String?
    @NSManaged var url: String?
    @NSManaged var visits: Int32
    @NSManaged var lastVisited: Date?
    @NSManaged var created: Date?
    @NSManaged var order: Int16
    @NSManaged var tags: [String]?
    
    /// Should not be set directly, due to specific formatting required, use `syncUUID` instead
    /// CD does not allow (easily) searching on transformable properties, could use binary, but would still require tranformtion
    //  syncUUID should never change
    @NSManaged var syncDisplayUUID: String?
    @NSManaged var syncParentDisplayUUID: String?
    @NSManaged var parentFolder: Bookmark?
    @NSManaged var children: Set<Bookmark>?
    
    @NSManaged var domain: Domain?

    // To trigger fetchedResultsController to update, change this value.
    // For instance, when a favicon is set on a domain, to notify any bookmarks or history items that
    // are displayed in a table and waiting for a favicon, you can change markDirty, and the favicon will update
    @NSManaged var markDirty: Int16

    // Is conveted to better store in CD
    var syncUUID: [Int]? {
        get { return syncUUID(fromString: syncDisplayUUID) }
        set(value) { syncDisplayUUID = Bookmark.syncDisplay(fromUUID: value) }
    }
    
    var syncParentUUID: [Int]? {
        get { return syncUUID(fromString: syncParentDisplayUUID) }
        set(value) {
            // Save actual instance variable
            syncParentDisplayUUID = Bookmark.syncDisplay(fromUUID: value)

            // Attach parent, only works if parent exists.
            let parent = Bookmark.get(parentSyncUUID: value)
            parentFolder = parent
        }
    }
    
    var displayTitle: String? {
        if let custom = customTitle, !custom.isEmpty {
            return customTitle
        }
        
        if let t = title, !t.isEmpty {
            return title
        }
        
        // Want to return nil so less checking on frontend
        return nil
    }
    
    override func awakeFromInsert() {
        super.awakeFromInsert()
        created = Date()
        lastVisited = created
    }
    
    func asDictionary(deviceId: [Int]?, action: Int?) -> [String: AnyObject] {
        return SyncRoot(bookmark: self, deviceId: deviceId, action: action).dictionaryRepresentation()
    }

    static func entity(context:NSManagedObjectContext) -> NSEntityDescription {
        return NSEntityDescription.entity(forEntityName: "Bookmark", in: context)!
    }

    class func frc(parentFolder: Bookmark?) -> NSFetchedResultsController<NSFetchRequestResult> {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>()
        fetchRequest.entity = Bookmark.entity(context: DataController.moc)
        fetchRequest.fetchBatchSize = 20
        fetchRequest.fetchLimit = 200
        fetchRequest.sortDescriptors = [NSSortDescriptor(key:"order", ascending: true), NSSortDescriptor(key:"created", ascending: false)]
        if let parentFolder = parentFolder {
            fetchRequest.predicate = NSPredicate(format: "parentFolder == %@", parentFolder)
        } else {
            fetchRequest.predicate = NSPredicate(format: "parentFolder == nil")
        }

        return NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext:DataController.moc, sectionNameKeyPath: nil, cacheName: nil)
    }
    
    func update(rootObject root: SyncRoot, save: Bool = false) {
        guard let bm = root.bookmark, let site = bm.site else { return }
        title = site.title
        customTitle = site.customTitle
        url = site.location
        lastVisited = Date(timeIntervalSince1970:(Double(site.lastAccessedTime ?? 0) / 1000.0))
        syncParentUUID = bm.parentFolderObjectId
        
        if save {
            DataController.saveContext()
        }
    }
    
    func update(customTitle: String?, url: String?, save: Bool = false) {
        
        // See if there has been any change
        if self.customTitle == customTitle && self.url == url {
            return
        }
        
        if let ct = customTitle, !ct.isEmpty {
            self.customTitle = customTitle
        }
        
        if let u = url, !u.isEmpty {
            self.url = url
        }
        
        if save {
            DataController.saveContext()
        }
        
        Sync.shared.sendSyncRecords(.bookmark, action: .update, bookmarks: [self])
    }

    // Should not be used for updating, modify to increase protection
    class func add(rootObject root: SyncRoot, save: Bool = false, sendToSync: Bool = false, parentFolder: Bookmark? = nil) -> Bookmark? {
        let bookmark = root.bookmark
        let site = bookmark?.site
     
        var bk: Bookmark!
        if let id = root.objectId, let foundBK = Bookmark.get(syncUUIDs: [id])?.first {
            // Found a pre-existing bookmark, cannot add duplicate
            // Turn into 'update' record instead
            bk = foundBK
        } else {
            bk = Bookmark(entity: Bookmark.entity(context: DataController.moc), insertInto: DataController.moc)
        }
        
        // Should probably have visual indication before reaching this point
        if site?.location?.startsWith(WebServer.sharedInstance.base) ?? false {
            return nil
        }
        
        // Use new values, fallback to previous values
        bk.url = site?.location ?? bk.url
        bk.title = site?.title ?? bk.title
        bk.customTitle = site?.customTitle ?? bk.customTitle // TODO: Check against empty titles
        bk.isFolder = bookmark?.isFolder ?? bk.isFolder ?? false
        bk.syncUUID = root.objectId ?? bk.syncUUID ?? (0..<16).map { _ in Int(arc4random_uniform(256)) }
        
        if let created = site?.creationTime {
            bk.created = Date(timeIntervalSince1970:(Double(created) / 1000.0))
        } else if bk.created == nil {
            bk.created = Date()
        }
        
        if let visited = site?.lastAccessedTime {
            bk.lastVisited = Date(timeIntervalSince1970:(Double(visited) / 1000.0))
        } else if bk.lastVisited == nil {
            bk.lastVisited = Date()
        }
        
        if let location = site?.location, let url = URL(string: location) {
            bk.domain = Domain.getOrCreateForUrl(url, context: DataController.moc)
        }
        
        // Must assign both, in cae parentFolder does not exist, need syncParentUUID to attach later
        bk.parentFolder = parentFolder
        bk.syncParentUUID = bookmark?.parentFolderObjectId ?? bk.syncParentUUID
        
        if save {
            // For folders that are saved _with_ a syncUUID, there may be child bookmarks
            //  (e.g. sync sent down bookmark before parent folder)
            if bk.isFolder {
                // Find all children and attach them
                if let children = Bookmark.getChildren(forFolderUUID: bk.syncUUID) {
                    
                    // TODO: Setup via bk.children property instead
                    children.forEach { $0.parentFolder = bk }
                }
            }
            
            // Submit to server
            if sendToSync {
                Sync.shared.sendSyncRecords(.bookmark, action: .update, bookmarks: [bk])
            }
            
            DataController.saveContext()
        }
        
        return bk
    }
    
    // TODO: DELETE
    class func add(url: URL?,
                       title: String?,
                       customTitle: String? = nil, // Folders only use customTitle
                       parentFolder:Bookmark? = nil,
                       isFolder:Bool = false) -> Bookmark? {
        
        let site = SyncSite()
        site.title = title
        site.customTitle = customTitle
        site.location = url?.absoluteString
        
        let bookmark = SyncBookmark()
        bookmark.isFolder = isFolder
        bookmark.parentFolderObjectId = parentFolder?.syncUUID
        bookmark.site = site
        
        let root = SyncRoot()
        root.bookmark = bookmark
        
        return self.add(rootObject: root, save: true, sendToSync: true, parentFolder: parentFolder)
    }
    
    // TODO: Migration syncUUIDS still needs to be solved
    // Should only ever be used for migration from old db
    class func addForMigration(url: String?, title: String, customTitle: String, parentFolder: Bookmark?, isFolder: Bool?) -> Bookmark? {
        // isFolder = true
        
        let site = SyncSite()
        site.title = title
        site.customTitle = customTitle
        site.location = url
        
        let bookmark = SyncBookmark()
        bookmark.isFolder = isFolder
//        bookmark.parentFolderObjectId = [parentFolder]
        bookmark.site = site
        
        let root = SyncRoot()
        root.bookmark = bookmark
        
        return self.add(rootObject: root, save: true)
    }

    class func contains(url: URL, completionOnMain completion: @escaping ((Bool)->Void)) {
        var found = false
        let context = DataController.shared.workerContext()
        context.perform {
            if let count = get(forUrl: url, countOnly: true, context: context) as? Int {
                found = count > 0
            }
            postAsyncToMain {
                completion(found)
            }
        }
    }

    class func frecencyQuery(context: NSManagedObjectContext, containing: String?) -> [Bookmark] {
        assert(!Thread.isMainThread)

        let fetchRequest = NSFetchRequest<NSFetchRequestResult>()
        fetchRequest.fetchLimit = 5
        fetchRequest.entity = Bookmark.entity(context: context)
        
        var predicate = NSPredicate(format: "lastVisited > %@", History.ThisWeek as CVarArg)
        if let query = containing {
            predicate = NSPredicate(format: predicate.predicateFormat + " AND url CONTAINS %@", query)
        }
        fetchRequest.predicate = predicate

        do {
            if let results = try context.fetch(fetchRequest) as? [Bookmark] {
                return results
            }
        } catch {
            let fetchError = error as NSError
            print(fetchError)
        }
        return [Bookmark]()
    }
    
    
    /// UUID -> DisplayUUID
    fileprivate static func syncDisplay(fromUUID uuid: [Int]?) -> String? {
        return uuid?.map{ $0.description }.joined(separator: ",")
    }
    
    /// DisplayUUID -> UUID
    fileprivate func syncUUID(fromString string: String?) -> [Int]? {
        return string?.components(separatedBy: ",").map { Int($0) }.flatMap { $0 }
    }
}

// TODO: Document well
// Getters
extension Bookmark {
    fileprivate static func get(forUrl url: URL, countOnly: Bool = false, context: NSManagedObjectContext) -> AnyObject? {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>()
        fetchRequest.entity = Bookmark.entity(context: context)
        fetchRequest.predicate = NSPredicate(format: "url == %@", url.absoluteString)
        do {
            if countOnly {
                let count = try context.count(for: fetchRequest)
                return count as AnyObject
            }
            let results = try context.fetch(fetchRequest) as? [Bookmark]
            return results?.first
        } catch {
            let fetchError = error as NSError
            print(fetchError)
        }
        return nil
    }
    
    fileprivate static func get(predicate: NSPredicate?) -> [Bookmark]? {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>()
        fetchRequest.entity = Bookmark.entity(context: DataController.moc)
        fetchRequest.predicate = predicate
        
        do {
            return try DataController.moc.fetch(fetchRequest) as? [Bookmark]
        } catch {
            let fetchError = error as NSError
            print(fetchError)
        }
        
        return nil
    }
    
    static func get(syncUUIDs: [[Int]]?) -> [Bookmark]? {
        
        guard let syncUUIDs = syncUUIDs else {
            return nil
        }
        
        // TODO: filter a unique set of syncUUIDs
        
        let searchableUUIDs = syncUUIDs.map { Bookmark.syncDisplay(fromUUID: $0) }.flatMap { $0 }
        return get(predicate: NSPredicate(format: "syncDisplayUUID IN %@", searchableUUIDs ))
    }
    
    static func getChildren(forFolderUUID syncUUID: [Int]?) -> [Bookmark]? {
        guard let searchableUUID = Bookmark.syncDisplay(fromUUID: syncUUID) else {
            return nil
        }
        
        return get(predicate: NSPredicate(format: "syncParentDisplayUUID == %@", searchableUUID))
    }
    
    static func get(parentSyncUUID parentUUID: [Int]?) -> Bookmark? {
        guard let searchableUUID = Bookmark.syncDisplay(fromUUID: parentUUID) else {
            return nil
        }
        
        return get(predicate: NSPredicate(format: "syncDisplayUUID == %@", searchableUUID))?.first
    }
    
    static func getFolders(_ bookmark: Bookmark?) -> [Bookmark] {
    
        var predicate: NSPredicate?
        if let parent = bookmark?.parentFolder {
            predicate = NSPredicate(format: "isFolder == true and parentFolder == %@", parent)
        } else {
            predicate = NSPredicate(format: "isFolder == true and parentFolder.@count = 0")
        }
        
        return get(predicate: predicate) ?? [Bookmark]()
    }
    
    static func getAllBookmarks() -> [Bookmark] {
        return get(predicate: nil) ?? [Bookmark]()
    }
}

// Removals
extension Bookmark {
    class func remove(forUrl url: URL, save: Bool = true) -> Bool {
        if let bm = get(forUrl: url, context: DataController.moc) as? Bookmark {
            self.remove(bookmark: bm, save: save)
            return true
        }
        return false
    }
    
    class func remove(bookmark: Bookmark, save: Bool = true) {
        // Must happen before, otherwise bookmark is gone
        Sync.shared.sendSyncRecords(.bookmark, action: .delete, bookmarks: [bookmark])

        DataController.moc.delete(bookmark)
        if save {
            DataController.saveContext()
        }
    }
}

