/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Storage
import Shared

private let log = Logger.browserLogger

protocol TabManagerDelegate: class {
    func tabManager(tabManager: TabManager, didSelectedTabChange selected: Browser?)
    func tabManager(tabManager: TabManager, didCreateWebView tab: Browser, url: NSURL?)
    func tabManager(tabManager: TabManager, didAddTab tab: Browser)
    func tabManager(tabManager: TabManager, didRemoveTab tab: Browser)
    func tabManagerDidRestoreTabs(tabManager: TabManager)
    func tabManagerDidAddTabs(tabManager: TabManager)
    func tabManagerDidEnterPrivateBrowsingMode(tabManager: TabManager) // has default impl
    func tabManagerDidExitPrivateBrowsingMode(tabManager: TabManager) // has default impl
}

extension TabManagerDelegate { // add default implementation for 'optional' funcs
    func tabManagerDidEnterPrivateBrowsingMode(tabManager: TabManager) {}
    func tabManagerDidExitPrivateBrowsingMode(tabManager: TabManager) {}
}

protocol TabManagerStateDelegate: class {
    func tabManagerWillStoreTabs(tabs: [Browser])
}

// We can't use a WeakList here because this is a protocol.
class WeakTabManagerDelegate {
    weak var value : TabManagerDelegate?

    init (value: TabManagerDelegate) {
        self.value = value
    }
}

// TabManager must extend NSObjectProtocol in order to implement WKNavigationDelegate
class TabManager : NSObject {
    private var delegates = [WeakTabManagerDelegate]()
    weak var stateDelegate: TabManagerStateDelegate?

    func addDelegate(delegate: TabManagerDelegate) {
        debugNoteIfNotMainThread()
        delegates.append(WeakTabManagerDelegate(value: delegate))
    }

    func removeDelegate(delegate: TabManagerDelegate) {
        debugNoteIfNotMainThread()
        for i in 0 ..< delegates.count {
            let del = delegates[i]
            if delegate === del.value {
                delegates.removeAtIndex(i)
                return
            }
        }
    }

    class TabsList {
        private(set) var tabs = [Browser]()
        func append(tab: Browser) { tabs.append(tab) }
        var internalTabList : [Browser] { return tabs }

        var nonprivateTabs: [Browser] {
            objc_sync_enter(self); defer { objc_sync_exit(self) }
            debugNoteIfNotMainThread()
            return tabs.filter { !$0.isPrivate }
        }

        var privateTabs: [Browser] {
            objc_sync_enter(self); defer { objc_sync_exit(self) }
            debugNoteIfNotMainThread()
            return tabs.filter { $0.isPrivate }
        }

        // What the users sees displayed based on current private browsing mode
        var displayedTabsForCurrentPrivateMode: [Browser] {
            return PrivateBrowsing.singleton.isOn ? privateTabs : nonprivateTabs
        }

        func removeTab(tab: Browser) {
            if let i = internalTabList.indexOf(tab) {
                tabs.removeAtIndex(i)
            }
        }
    }

    private(set) var tabs = TabsList()

    private let defaultNewTabRequest: NSURLRequest
    private let navDelegate: TabManagerNavDelegate
    private(set) var isRestoring = false

    // A WKWebViewConfiguration used for normal tabs
    lazy private var configuration: WKWebViewConfiguration = {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = WKProcessPool()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = !(self.prefs.boolForKey("blockPopups") ?? true)
        return configuration
    }()

    private let imageStore: DiskImageStore?

    private let prefs: Prefs

    init(defaultNewTabRequest: NSURLRequest, prefs: Prefs, imageStore: DiskImageStore?) {
        debugNoteIfNotMainThread()

        self.prefs = prefs
        self.defaultNewTabRequest = defaultNewTabRequest
        self.navDelegate = TabManagerNavDelegate()
        self.imageStore = imageStore
        super.init()

        addNavigationDelegate(self)

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(TabManager.prefsDidChange), name: NSUserDefaultsDidChangeNotification, object: nil)
    }

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }

    func addNavigationDelegate(delegate: WKCompatNavigationDelegate) {
        debugNoteIfNotMainThread()

        self.navDelegate.insert(delegate)
    }

    var tabCount: Int {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        return tabs.internalTabList.count
    }

    private weak var _selectedTab: Browser?
    var selectedTab: Browser? {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        return _selectedTab
    }

    func tabForWebView(webView: UIWebView) -> Browser? {
        objc_sync_enter(self); defer { objc_sync_exit(self) }

        for tab in tabs.internalTabList {
            if tab.webView === webView {
                return tab
            }
        }

        return nil
    }

    func getTabFor(url: NSURL) -> Browser? {
        objc_sync_enter(self); defer { objc_sync_exit(self) }

        for tab in tabs.internalTabList {
            if (tab.webView?.URL == url) {
                return tab
            }
        }
        return nil
    }

    func selectTab(tab: Browser?) {
        debugNoteIfNotMainThread()
        if (!NSThread.isMainThread()) { // No logical reason this should be off-main, don't select.
            return
        }
        objc_sync_enter(self); defer { objc_sync_exit(self) }

        if let tab = tab  where selectedTab === tab && tab.webView != nil {
            return
        }

        _selectedTab = tab
        preserveTabs()

        if let t = self.selectedTab where t.webView == nil {
            t.createWebview()
            for delegate in delegates where t.webView != nil {
                delegate.value?.tabManager(self, didCreateWebView: t, url: nil)
            }
        }

        for delegate in delegates where tab != nil {
            delegate.value?.tabManager(self, didSelectedTabChange: tab)
        }

        limitInMemoryTabs()

//        if let s = selectedTab {
//            print("idx: \(tabs.indexOf(s)), tab: \(s.url?.absoluteDisplayString())")
//        }
    }

    func expireSnackbars() {
        debugNoteIfNotMainThread()

        for tab in tabs.internalTabList {
            tab.expireSnackbars()
        }
    }

    func addTabForDesktopSite() -> Browser {
        let tab = Browser(configuration: self.configuration, isPrivate: PrivateBrowsing.singleton.isOn)
        configureTab(tab, request: nil, flushToDisk: false, zombie: false, useDesktopUserAgent: true)
        selectTab(tab)
        return tab
    }

    func addTab(request: NSURLRequest! = nil, configuration: WKWebViewConfiguration! = nil, isPrivate: Bool) -> Browser? {
        return self.addTab(request, configuration: configuration, flushToDisk: true, zombie: false, isPrivate: isPrivate)
    }

    func addTabAndSelect(request: NSURLRequest! = nil, configuration: WKWebViewConfiguration! = nil, isPrivate: Bool) -> Browser? {
        guard let tab = addTab(request, configuration: configuration, isPrivate: isPrivate) else { return nil }
        selectTab(tab)
        return tab
    }

    func addTabAndSelect(request: NSURLRequest! = nil, configuration: WKWebViewConfiguration! = nil) -> Browser? {
        guard let tab = addTab(request, configuration: configuration) else { return nil }
        selectTab(tab)
        return tab
    }

    // This method is duplicated to hide the flushToDisk option from consumers.
    func addTab(request: NSURLRequest! = nil, configuration: WKWebViewConfiguration! = nil) -> Browser? {
        return self.addTab(request, configuration: configuration, flushToDisk: true, zombie: false)
    }

    func addTabsForURLs(urls: [NSURL], zombie: Bool) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        debugNoteIfNotMainThread()

        if urls.isEmpty {
            return
        }

        var tab: Browser!
        for url in urls {
            tab = self.addTab(NSURLRequest(URL: url), flushToDisk: false, zombie: zombie)
        }

        // Flush.
        storeChanges()

        // Select the most recent.
        self.selectTab(tab)

        // Notify that we bulk-loaded so we can adjust counts.
        for delegate in delegates {
            delegate.value?.tabManagerDidAddTabs(self)
        }
    }

    private func limitInMemoryTabs() {
        let maxInMemTabs = BraveUX.MaxTabsInMemory
        if tabs.internalTabList.count < maxInMemTabs {
            return
        }

        var webviews = 0
        for browser in tabs.internalTabList {
            if browser.webView != nil {
                webviews += 1
            }
        }
        if webviews < maxInMemTabs {
            return
        }

        print("webviews \(webviews)")

        var oldestTime: Timestamp = NSDate.now()
        var oldestBrowser: Browser? = nil
        for browser in tabs.internalTabList {
            if browser.webView == nil {
                continue
            }
            if let t = browser.lastExecutedTime where t < oldestTime {
                oldestTime = t
                oldestBrowser = browser
            }
        }
        if let browser = oldestBrowser {
            if selectedTab != browser {
                browser.deleteWebView(isTabDeleted: false)
            } else {
                print("limitInMemoryTabs: tab to delete is selected!")
            }
        }
    }

    private func addTab(request: NSURLRequest? = nil, configuration: WKWebViewConfiguration? = nil, flushToDisk: Bool, zombie: Bool, isPrivate: Bool) -> Browser? {
        debugNoteIfNotMainThread()
        if (!NSThread.isMainThread()) { // No logical reason this should be off-main, don't add a tab.
            return nil
        }
        objc_sync_enter(self); defer { objc_sync_exit(self) }

        let tab = Browser(configuration: self.configuration, isPrivate: isPrivate)
        configureTab(tab, request: request, flushToDisk: flushToDisk, zombie: zombie)
        return tab
    }

    private func addTab(request: NSURLRequest? = nil, configuration: WKWebViewConfiguration? = nil, flushToDisk: Bool, zombie: Bool) -> Browser? {
        debugNoteIfNotMainThread()
        if (!NSThread.isMainThread()) { // No logical reason this should be off-main, don't add a tab.
            return nil
        }
        objc_sync_enter(self); defer { objc_sync_exit(self) }

        let tab = Browser(configuration: configuration ?? self.configuration, isPrivate: PrivateBrowsing.singleton.isOn)
        configureTab(tab, request: request, flushToDisk: flushToDisk, zombie: zombie)
        return tab
    }

    func configureTab(tab: Browser, request: NSURLRequest?, flushToDisk: Bool, zombie: Bool, useDesktopUserAgent: Bool = false) {
        debugNoteIfNotMainThread()
        if (!NSThread.isMainThread()) { // No logical reason this should be off-main, don't add a tab.
            return
        }
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        
        limitInMemoryTabs()

        tabs.append(tab)

        for delegate in delegates {
            delegate.value?.tabManager(self, didAddTab: tab)
        }

        tab.createWebview(useDesktopUserAgent: useDesktopUserAgent)

        for delegate in delegates {
            delegate.value?.tabManager(self, didCreateWebView: tab, url: request?.URL)
        }

        tab.navigationDelegate = navDelegate
        tab.loadRequest(request ?? defaultNewTabRequest)

        if flushToDisk {
            storeChanges()
        }
    }

    // This method is duplicated to hide the flushToDisk option from consumers.
    func removeTab(tab: Browser, createTabIfNoneLeft: Bool) {
        self.removeTab(tab, flushToDisk: true, notify: true, createTabIfNoneLeft: createTabIfNoneLeft)
        hideNetworkActivitySpinner()
    }

    /// - Parameter notify: if set to true, will call the delegate after the tab
    ///   is removed.
    private func removeTab(tab: Browser, flushToDisk: Bool, notify: Bool, createTabIfNoneLeft: Bool) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        debugNoteIfNotMainThread()
        if !NSThread.isMainThread() {
            return
        }

        if let selected = selectedTab where selectedTab === tab {
            if let idx = tabs.displayedTabsForCurrentPrivateMode.indexOf(selected) {
                if idx - 1 >= 0 {
                    selectTab(tabs.displayedTabsForCurrentPrivateMode[idx - 1])
                } else if tabs.displayedTabsForCurrentPrivateMode.last !== tab {
                    selectTab(tabs.displayedTabsForCurrentPrivateMode.last)
                }
            }
        }
        tabs.removeTab(tab)


        // There's still some time between this and the webView being destroyed.
        // We don't want to pick up any stray events.
        tab.webView?.navigationDelegate = nil
        if notify {
            for delegate in delegates {
                delegate.value?.tabManager(self, didRemoveTab: tab)
            }
        }

        // Make sure we never reach 0 normal tabs
        if tabs.displayedTabsForCurrentPrivateMode.count == 0 && createTabIfNoneLeft {
            let tab = addTab(isPrivate: PrivateBrowsing.singleton.isOn)
            selectTab(tab)
        }
        
        if createTabIfNoneLeft && selectedTab == nil {
            selectTab(tabs.displayedTabsForCurrentPrivateMode.first)
        }

        if flushToDisk {
        	storeChanges()
        }
    }

    /// Removes all private tabs from the manager.
    /// - Parameter notify: if set to true, the delegate is called when a tab is
    ///   removed.
    func removeAllPrivateTabsAndNotify(notify: Bool) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        for tab in tabs.internalTabList {
            tab.deleteWebView(isTabDeleted: false)
        }
        _selectedTab = nil
        tabs.privateTabs.forEach{
            removeTab($0, flushToDisk: true, notify: notify, createTabIfNoneLeft: false)
        }
    }

    func removeAll() {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        let tabs = self.tabs

        for tab in tabs.internalTabList {
            self.removeTab(tab, flushToDisk: false, notify: true, createTabIfNoneLeft: false)
        }
        storeChanges()
    }

    func getTabForURL(url: NSURL) -> Browser? {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        debugNoteIfNotMainThread()

        return tabs.internalTabList.filter { $0.webView?.URL == url } .first
    }

    func storeChanges() {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        stateDelegate?.tabManagerWillStoreTabs(tabs.nonprivateTabs)

        // Also save (full) tab state to disk.
        preserveTabs()
    }

    func prefsDidChange() {
#if !BRAVE
        dispatch_async(dispatch_get_main_queue()) {
            let allowPopups = !(self.prefs.boolForKey("blockPopups") ?? true)
            // Each tab may have its own configuration, so we should tell each of them in turn.
            for tab in self.tabs {
                tab.webView?.configuration.preferences.javaScriptCanOpenWindowsAutomatically = allowPopups
            }
            // The default tab configurations also need to change.
            self.configuration.preferences.javaScriptCanOpenWindowsAutomatically = allowPopups
            self.privateConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = allowPopups
        }
#endif
    }

    func resetProcessPool() {
        debugNoteIfNotMainThread()

        configuration.processPool = WKProcessPool()
    }
}

extension TabManager {

    class SavedTab: NSObject, NSCoding {
        let isSelected: Bool
        let title: String?
        let isPrivate: Bool
        var sessionData: SessionData?
        var screenshotUUID: NSUUID?

        var jsonDictionary: [String: AnyObject] {
            let title: String = self.title ?? "null"
            let uuid: String = String(self.screenshotUUID ?? "null")

            var json: [String: AnyObject] = [
                "title": title,
                "isPrivate": String(self.isPrivate),
                "isSelected": String(self.isSelected),
                "screenshotUUID": uuid
            ]

            if let sessionDataInfo = self.sessionData?.jsonDictionary {
                json["sessionData"] = sessionDataInfo
            }

            return json
        }

        init?(browser: Browser, isSelected: Bool) {
            debugNoteIfNotMainThread()

            self.screenshotUUID = browser.screenshotUUID
            self.isSelected = isSelected
            self.title = browser.displayTitle
            self.isPrivate = browser.isPrivate
            super.init()

            if browser.sessionData == nil {
                let currentItem: LegacyBackForwardListItem! = browser.webView?.backForwardList.currentItem

                // Freshly created web views won't have any history entries at all.
                // If we have no history, abort.
                if currentItem == nil {
                    return nil
                }

                let backList = browser.webView?.backForwardList.backList ?? []
                let forwardList = browser.webView?.backForwardList.forwardList ?? []
                let urls = (backList + [currentItem] + forwardList).map { $0.URL }
                let currentPage = -forwardList.count
                self.sessionData = SessionData(currentPage: currentPage, currentTitle: browser.title, currentFavicon: browser.displayFavicon, urls: urls, lastUsedTime: browser.lastExecutedTime ?? NSDate.now())
            } else {
                self.sessionData = browser.sessionData
            }
        }

        required init?(coder: NSCoder) {
            self.sessionData = coder.decodeObjectForKey("sessionData") as? SessionData
            self.screenshotUUID = coder.decodeObjectForKey("screenshotUUID") as? NSUUID
            self.isSelected = coder.decodeBoolForKey("isSelected")
            self.title = coder.decodeObjectForKey("title") as? String
            self.isPrivate = coder.decodeBoolForKey("isPrivate")
        }

        func encodeWithCoder(coder: NSCoder) {
#if BRAVE
            if (isPrivate) { // seems more private to not write private tab info to disk
                return
            }
#endif
            coder.encodeObject(sessionData, forKey: "sessionData")
            coder.encodeObject(screenshotUUID, forKey: "screenshotUUID")
            coder.encodeBool(isSelected, forKey: "isSelected")
            coder.encodeObject(title, forKey: "title")
#if !BRAVE
            coder.encodeBool(isPrivate, forKey: "isPrivate")
#endif
        }
    }

    static private func tabsStateArchivePath() -> String {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0]
        return NSURL(fileURLWithPath: documentsPath).URLByAppendingPathComponent("tabsState.archive")!.path!
    }

    static func tabArchiveData() -> NSData? {
        let tabStateArchivePath = tabsStateArchivePath()
        if NSFileManager.defaultManager().fileExistsAtPath(tabStateArchivePath) {
            return NSData(contentsOfFile: tabStateArchivePath)
        } else {
            return nil
        }
    }

    static func tabsToRestore() -> [SavedTab]? {
        if let tabData = tabArchiveData() {
            let unarchiver = NSKeyedUnarchiver(forReadingWithData: tabData)
            return unarchiver.decodeObjectForKey("tabs") as? [SavedTab]
        } else {
            return nil
        }
    }

    private func preserveTabsInternal() {
        debugNoteIfNotMainThread()

        guard !isRestoring else { return }

        let path = TabManager.tabsStateArchivePath()
        var savedTabs = [SavedTab]()
        var savedUUIDs = Set<String>()
        for tab in tabs.internalTabList {
            if tab.isPrivate {
                continue
            }
            if let savedTab = SavedTab(browser: tab, isSelected: tab === selectedTab) {
                savedTabs.append(savedTab)

                if let screenshot = tab.screenshot.image,
                   let screenshotUUID = tab.screenshotUUID
                {
                    savedUUIDs.insert(screenshotUUID.UUIDString)
                    imageStore?.put(screenshotUUID.UUIDString, image: screenshot)
                }
            }
        }

        // Clean up any screenshots that are no longer associated with a tab.
        imageStore?.clearExcluding(savedUUIDs)

        let tabStateData = NSMutableData()
        let archiver = NSKeyedArchiver(forWritingWithMutableData: tabStateData)
        archiver.encodeObject(savedTabs, forKey: "tabs")
        archiver.finishEncoding()
        tabStateData.writeToFile(path, atomically: true)
    }

    func preserveTabs() {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        // This is wrapped in an Objective-C @try/@catch handler because NSKeyedArchiver may throw exceptions which Swift cannot handle
        _ = Try(withTry: { () -> Void in
            self.preserveTabsInternal()
            }) { (exception) -> Void in
            print("Failed to preserve tabs: \(exception)")
        }
    }

    private func restoreTabsInternal() {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        log.debug("Restoring tabs.")
        guard let savedTabs = TabManager.tabsToRestore() else {
            log.debug("Nothing to restore.")
            return
        }

        var tabToSelect: Browser?
        for (_, savedTab) in savedTabs.enumerate() {
            if savedTab.isPrivate {
                continue
            }

            guard let tab = self.addTab(flushToDisk: false, zombie: true) else { return }
            tab.lastExecutedTime = savedTab.sessionData?.lastUsedTime

            // Set the UUID for the tab, asynchronously fetch the UIImage, then store
            // the screenshot in the tab as long as long as a newer one hasn't been taken.
            if let screenshotUUID = savedTab.screenshotUUID,
               let imageStore = self.imageStore {
                tab.screenshotUUID = screenshotUUID
                imageStore.get(screenshotUUID.UUIDString) >>== { screenshot in
                    if tab.screenshotUUID == screenshotUUID {
                        tab.setScreenshot(screenshot, revUUID: false)
                    }
                }
            }

            if savedTab.isSelected {
                tabToSelect = tab
            }

            tab.sessionData = savedTab.sessionData
            tab.lastTitle = savedTab.title

            if let w = tab.webView {
                tab.restore(w)
            }
        }

        if tabToSelect == nil {
            tabToSelect = tabs.displayedTabsForCurrentPrivateMode.first
        }

        log.debug("Done adding tabs.")

        // Only tell our delegates that we restored tabs if we actually restored a tab(s)
        if savedTabs.count > 0 {
            log.debug("Notifying delegates.")
            for delegate in delegates {
                delegate.value?.tabManagerDidRestoreTabs(self)
            }
        }

        if let tab = tabToSelect {
            log.debug("Selecting a tab.")
            selectTab(tab)
        }

        log.debug("Done.")
    }

    func restoreTabs() {
        isRestoring = true

        if tabCount == 0 && !DebugSettingsBundleOptions.skipSessionRestore {
            // This is wrapped in an Objective-C @try/@catch handler because NSKeyedUnarchiver may throw exceptions which Swift cannot handle
            let _ = Try(
                withTry: { () -> Void in
                    self.restoreTabsInternal()
                },
                catch: { exception in
                    print("Failed to restore tabs: \(exception)")
                }
            )
        }

        if tabCount == 0 {
            let tab = addTab()
            selectTab(tab)
        }

        isRestoring = false
    }

    // Only call from PB class
    func enterPrivateBrowsingMode(_: PrivateBrowsing) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        tabs.internalTabList.forEach{ $0.deleteWebView(isTabDeleted: false) }
        delegates.forEach {
            $0.value?.tabManagerDidEnterPrivateBrowsingMode(self)
        }
    }

    func exitPrivateBrowsingMode(_: PrivateBrowsing) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        delegates.forEach {
            $0.value?.tabManagerDidExitPrivateBrowsingMode(self)
        }

        if getApp().tabManager.tabs.internalTabList.count < 1 {
            getApp().tabManager.addTab()
        }
        getApp().tabManager.selectTab(getApp().tabManager.tabs.displayedTabsForCurrentPrivateMode.first)
    }
}

extension TabManager : WKCompatNavigationDelegate {

    func webViewDecidePolicyForNavigationAction(webView: UIWebView, url: NSURL?, inout shouldLoad: Bool) {}

    func webViewDidStartProvisionalNavigation(_: UIWebView, url: NSURL?) {
        UIApplication.sharedApplication().networkActivityIndicatorVisible = true

#if BRAVE
        var hider: (Void -> Void)!
        hider = {
            postAsyncToMain(1) {
                self.hideNetworkActivitySpinner()
                if UIApplication.sharedApplication().networkActivityIndicatorVisible {
                    hider()
                }
            }
        }
        hider()
#endif
    }

    func webViewDidFinishNavigation(webView: UIWebView, url: NSURL?) {
        hideNetworkActivitySpinner()

        // only store changes if this is not an error page
        // as we current handle tab restore as error page redirects then this ensures that we don't
        // call storeChanges unnecessarily on startup
        if let url = tabForWebView(webView)?.url {
            if !ErrorPageHelper.isErrorPageURL(url) {
                storeChanges()
            }
        }
    }

    func webViewDidFailNavigation(_: UIWebView, withError _: NSError) {
        hideNetworkActivitySpinner()
    }

    func hideNetworkActivitySpinner() {
        for tab in tabs.internalTabList {
            if let tabWebView = tab.webView {
                // If we find one tab loading, we don't hide the spinner
                if tabWebView.loading {
                    return
                }
            }
        }
        UIApplication.sharedApplication().networkActivityIndicatorVisible = false
    }

    /// Called when the WKWebView's content process has gone away. If this happens for the currently selected tab
    /// then we immediately reload it.

//    func webViewWebContentProcessDidTerminate(webView: WKWebView) {
//        if let browser = selectedTab where browser.webView == webView {
//            webView.reload()
//        }
//    }
}

extension TabManager {
    class func tabRestorationDebugInfo() -> String {
        debugNoteIfNotMainThread()

        let tabs = TabManager.tabsToRestore()?.map { $0.jsonDictionary } ?? []
        do {
            let jsonData = try NSJSONSerialization.dataWithJSONObject(tabs, options: [.PrettyPrinted])
            return String(data: jsonData, encoding: NSUTF8StringEncoding) ?? ""
        } catch _ {
            return ""
        }
    }
}


protocol WKCompatNavigationDelegate : class {
    func webViewDidFailNavigation(webView: UIWebView, withError error: NSError)
    func webViewDidFinishNavigation(webView: UIWebView, url: NSURL?)
    func webViewDidStartProvisionalNavigation(webView: UIWebView, url: NSURL?)
    func webViewDecidePolicyForNavigationAction(webView: UIWebView, url: NSURL?, inout shouldLoad: Bool)
}

// WKNavigationDelegates must implement NSObjectProtocol
class TabManagerNavDelegate : WKCompatNavigationDelegate {
    class Weak_WKCompatNavigationDelegate {     // We can't use a WeakList here because this is a protocol.
        weak var value : WKCompatNavigationDelegate?
        init (value: WKCompatNavigationDelegate) { self.value = value }
    }
    private var navDelegates = [Weak_WKCompatNavigationDelegate]()

    func insert(delegate: WKCompatNavigationDelegate) {
        navDelegates.append(Weak_WKCompatNavigationDelegate(value: delegate))
    }

//    func webView(webView: WKWebView, didCommitNavigation navigation: WKNavigation!) {
//        for delegate in delegates {
//            delegate.webView?(webView, didCommitNavigation: navigation)
//        }
//    }

    func webViewDidFailNavigation(webView: UIWebView, withError error: NSError) {
        for delegate in navDelegates {
            delegate.value?.webViewDidFailNavigation(webView, withError: error)
        }
    }

//    func webView(webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
//        withError error: NSError) {
//            for delegate in delegates {
//                delegate.webView?(webView, didFailProvisionalNavigation: navigation, withError: error)
//            }
//    }

    func webViewDidFinishNavigation(webView: UIWebView, url: NSURL?) {
        for delegate in navDelegates {
            delegate.value?.webViewDidFinishNavigation(webView, url: url)
        }
    }

//    func webView(webView: WKWebView, didReceiveAuthenticationChallenge challenge: NSURLAuthenticationChallenge,
//        completionHandler: (NSURLSessionAuthChallengeDisposition,
//        NSURLCredential?) -> Void) {
//            let authenticatingDelegates = delegates.filter {
//                $0.respondsToSelector(#selector(WKNavigationDelegate.webView(_:didReceiveAuthenticationChallenge:completionHandler:)))
//            }
//
//            guard let firstAuthenticatingDelegate = authenticatingDelegates.first else {
//                return completionHandler(NSURLSessionAuthChallengeDisposition.PerformDefaultHandling, nil)
//            }
//
//            firstAuthenticatingDelegate.webView?(webView, didReceiveAuthenticationChallenge: challenge) { (disposition, credential) in
//                completionHandler(disposition, credential)
//            }
//    }

//    func webView(webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
//        for delegate in delegates {
//            delegate.webView?(webView, didReceiveServerRedirectForProvisionalNavigation: navigation)
//        }
//    }

    func webViewDidStartProvisionalNavigation(webView: UIWebView, url: NSURL?) {
        for delegate in navDelegates {
            delegate.value?.webViewDidStartProvisionalNavigation(webView, url: url)
        }
    }

    func webViewDecidePolicyForNavigationAction(webView: UIWebView, url: NSURL?, inout shouldLoad: Bool) {
        for delegate in navDelegates {
            delegate.value?.webViewDecidePolicyForNavigationAction(webView, url: url, shouldLoad: &shouldLoad)
        }

    }

//    func webView(webView: WKWebView, decidePolicyForNavigationResponse navigationResponse: WKNavigationResponse,
//        decisionHandler: (WKNavigationResponsePolicy) -> Void) {
//            var res = WKNavigationResponsePolicy.Allow
//            for delegate in delegates {
//                delegate.webView?(webView, decidePolicyForNavigationResponse: navigationResponse, decisionHandler: { policy in
//                    if policy == .Cancel {
//                        res = policy
//                    }
//                })
//            }
//
//            decisionHandler(res)
//    }
}
