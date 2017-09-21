import Foundation
import Deferred
import Shared
import Storage

struct BraveShieldTableRow {
    var normalizedDomain = ""
    var shieldState = ""
}

class BraveShieldTable: GenericTable<BraveShieldTableRow> {
    static let tableName = "brave_shield_per_domain"
    static let colDomain = "domain"
    static let colState = "state_json"

    var db: BrowserDB!
    static func initialize(db: BrowserDB) -> BraveShieldTable {
        let table = BraveShieldTable()
        table.db = db
        switch db.createOrUpdate(BraveShieldTable()) {
        case .Failure:
            print("Failed to create/update DB schema for BraveShieldTable!")
            fatalError()
        case .Closed:
            print("BraveShieldTable not created as the SQLiteConnection is closed.")
        case .Success:
            print("BraveShieldTable succesfully created/updated")
        }

        return table
    }

    override var version: Int { return 1 }
    override var name: String { return BraveShieldTable.tableName }
    override var rows: String { return "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
        " \(BraveShieldTable.colDomain) TEXT NOT NULL UNIQUE, " +
        " \(BraveShieldTable.colState) TEXT " }

    override func updateTable(db: SQLiteDBConnection, from: Int) -> Bool {
        let to = self.version
        print("Update table \(self.name) from \(from) to \(to)")
        if from == 0 && to >= 1 {
            // changed name/type of state to state_json
            drop(db)
            create(db)
        }
        return false
    }

    func getRows() -> Deferred<Maybe<[BraveShieldTableRow]>> {
        var err: NSError?

        let cursor = db.withReadableConnection(&err) { connection, _ -> Cursor<BraveShieldTableRow> in
            return self.query(connection, options: nil)
        }

        if let err = err {
            cursor.close()
            return deferMaybe(DatabaseError(err: err))
        }

        let items = cursor.asArray()
        cursor.close()
        return deferMaybe(items)
    }

    func makeArgs(item: BraveShieldTableRow) -> [AnyObject?] {
        var args = [AnyObject?]()
        args.append(item.shieldState)
        args.append(item.normalizedDomain)
        return args
    }

    override func getInsertAndArgs( inout item: BraveShieldTableRow) -> (String, [AnyObject?])? {
        return ("INSERT INTO \(BraveShieldTable.tableName) (\(BraveShieldTable.colState), \(BraveShieldTable.colDomain)) VALUES (?,?)", makeArgs(item))
    }

    override func getUpdateAndArgs(inout item: BraveShieldTableRow) -> (String, [AnyObject?])? {
        return ("UPDATE \(BraveShieldTable.tableName) SET \(BraveShieldTable.colState) = ? WHERE \(BraveShieldTable.colDomain) = ?", makeArgs(item))
    }

    override func getDeleteAndArgs(inout item: BraveShieldTableRow?) -> (String, [AnyObject?])? {
        var args = [AnyObject?]()
        if let item = item {
            args.append(item.normalizedDomain)
            return ("DELETE FROM \(BraveShieldTable.tableName) WHERE \(BraveShieldTable.colDomain) = ?", args)
        }
        return ("DELETE FROM \(BraveShieldTable.tableName)", [])
    }

    override var factory: ((row: SDRow) -> BraveShieldTableRow)? {
        return { row -> BraveShieldTableRow in
            var item = BraveShieldTableRow()
            if let domain = row[BraveShieldTable.colDomain] as? String, state = row[BraveShieldTable.colState] as? String {
                item.normalizedDomain = domain
                item.shieldState = state
            }
            return item
        }
    }

    override func getQueryAndArgs(options: QueryOptions?) -> (String, [AnyObject?])? {
        var args = [AnyObject?]()
        if let filter: AnyObject = options?.filter {
            args.append("%\(filter)%")
            return ("SELECT \(BraveShieldTable.colState), \(BraveShieldTable.colDomain) FROM \(BraveShieldTable.tableName) WHERE \(BraveShieldTable.colDomain) LIKE ?", args)
        }
        return ("SELECT \(BraveShieldTable.colState), \(BraveShieldTable.colDomain) FROM \(BraveShieldTable.tableName)", args)
    }
}


var braveShieldForDomainTable:BraveShieldTable? = nil

extension BrowserProfile {
    public func clearBraveShieldHistory() ->  Success {
        let deferred = Success()

        if braveShieldForDomainTable == nil {
            deferred.fill(Maybe(success: ()))
            return deferred
        }

        var err: NSError? = nil
        db.transaction(&err) { (conn, err) -> Bool in
            err = conn.executeChange("DROP TABLE IF EXISTS \(BraveShieldTable.tableName)", withArgs: nil)
            if let err = err {
                print("SQL operation failed: \(err.localizedDescription)")
            }

            err = conn.executeChange("DELETE FROM \(kSchemaTableName) WHERE name = '\(BraveShieldTable.tableName)'", withArgs: nil)
            if let err = err {
                print("SQL operation failed: \(err.localizedDescription)")
            }
            braveShieldForDomainTable = nil
            BraveShieldState.perNormalizedDomain.removeAll()
            deferred.fill(Maybe(success: ()))
            return err == nil
        }

        return deferred
    }

    public func loadBraveShieldsPerBaseDomain() -> Deferred<Void> {
        let deferred = Deferred<Void>()
        succeed().upon() { _ in // move off main thread
            BraveShieldState.perNormalizedDomain.removeAll()
            braveShieldForDomainTable = BraveShieldTable.initialize(self.db)

            if braveShieldForDomainTable == nil {
                print("🌩 Failed to init BraveShieldTable")
                deferred.fill()
                return
            }

            braveShieldForDomainTable?.getRows().upon {
                result in
                if let rows = result.successValue {
                    for item in rows {
                        let jsonString = item.shieldState
                        let json = JSON(string: jsonString)
                        for (k, v) in json.asDictionary ?? [:] {
                            if let on = v.asBool {
                                BraveShieldState.forDomain(item.normalizedDomain, setState: (k, on))
                            }
                        }
                    }
                }
                deferred.fill(())
            }
        }
        return deferred
    }

    public func setBraveShieldForNormalizedDomain(domain: String, state: (String, Bool?)) {
        BraveShieldState.forDomain(domain, setState: state)

        if PrivateBrowsing.singleton.isOn {
            return
        }

        let persistentState = BraveShieldState.getStateForDomain(domain)

        succeed().upon() { _ in
            if braveShieldForDomainTable == nil {
                braveShieldForDomainTable = BraveShieldTable.initialize(self.db)
            }

            var t = BraveShieldTableRow()
            t.normalizedDomain = domain
            if let state = persistentState, jsonString = state.toJsonString() {
                t.shieldState = jsonString
            }
            var err: NSError?
            self.db.transaction(synchronous: true, err: &err) { (connection, inout err:NSError?) -> Bool in
                if persistentState == nil {
                    braveShieldForDomainTable?.delete(connection, item: t, err: &err)
                    return true
                }

                let id = braveShieldForDomainTable?.insert(connection, item: t, err: &err)
                if id < 0 {
                    braveShieldForDomainTable?.update(connection, item: t, err: &err)
                }
                return true
            }
        }
    }
}

// These override the setting in the prefs
public struct BraveShieldState {

    enum Shield : String {
        case AllOff = "all_off"
        case AdblockAndTp = "adblock_and_tp"
        case HTTPSE = "httpse"
        case SafeBrowsing = "safebrowsing"
        case FpProtection = "fp_protection"
        case NoScript = "noscript"
    }

    private var state = [Shield:Bool]()

    typealias DomainKey = String
    static var perNormalizedDomain = [DomainKey: BraveShieldState]()

    static func forDomain(domain: String, setState state:(String, Bool?)) {
        var shields = perNormalizedDomain[domain]
        if shields == nil {
            if state.1 == nil {
                return
            }
            shields = BraveShieldState()
        }

        if let key = Shield(rawValue: state.0) {
            shields!.setState(key, on: state.1)
            perNormalizedDomain[domain] = shields!
        } else {
            assert(false, "db has bad brave shield state")
        }
    }

    static func getStateForDomain(domain: String) -> BraveShieldState? {
        return perNormalizedDomain[domain]
    }

    public init(jsonStateFromDbRow: String) {
        let js = JSON(string: jsonStateFromDbRow)
        for (k,v) in (js.asDictionary ?? [:]) {
            if let key = Shield(rawValue: k) {
                setState(key, on: v.asBool)
            } else {
                assert(false, "db has bad brave shield state")
            }
        }
    }

    public init() {
    }

    public init(orig: BraveShieldState) {
        self.state = orig.state // Dict value type is copied
    }

    func toJsonString() -> String? {
        var _state = [String: Bool]()
        for (k, v) in state {
            _state[k.rawValue] = v
        }
        return JSON(_state).toString()
    }

    mutating func setState(key: Shield, on: Bool?) {
        if let on = on {
            state[key] = on
        } else {
            state.removeValueForKey(key)
        }
    }

    func isAllOff() -> Bool {
        return state[.AllOff] ?? false
    }

    func isNotSet() -> Bool {
        return state.count < 1
    }

    func isOnAdBlockAndTp() -> Bool? {
        return state[.AdblockAndTp] ?? nil
    }

    func isOnHTTPSE() -> Bool? {
        return state[.HTTPSE] ?? nil
    }

    func isOnSafeBrowsing() -> Bool? {
        return state[.SafeBrowsing] ?? nil
    }

    func isOnScriptBlocking() -> Bool? {
        return state[.NoScript] ?? nil
    }

    func isOnFingerprintProtection() -> Bool? {
        return state[.FpProtection] ?? nil
    }

    mutating func setStateFromPerPageShield(pageState: BraveShieldState?) {
        setState(.NoScript, on: pageState?.isOnScriptBlocking() ?? (BraveApp.getPrefs()?.boolForKey(kPrefKeyNoScriptOn) ?? false))
        setState(.AdblockAndTp, on: pageState?.isOnAdBlockAndTp() ?? AdBlocker.singleton.isNSPrefEnabled)
        setState(.SafeBrowsing, on: pageState?.isOnSafeBrowsing() ?? SafeBrowsing.singleton.isNSPrefEnabled)
        setState(.HTTPSE, on: pageState?.isOnHTTPSE() ?? HttpsEverywhere.singleton.isNSPrefEnabled)
        setState(.FpProtection, on: pageState?.isOnFingerprintProtection() ?? (BraveApp.getPrefs()?.boolForKey(kPrefKeyFingerprintProtection) ?? false))
    }
}

public class BraveGlobalShieldStats {
    static let singleton = BraveGlobalShieldStats()
    static let DidUpdateNotification = "BraveGlobalShieldStatsDidUpdate"
    
    private let prefs = NSUserDefaults.standardUserDefaults()
    
    var adblock: Int = 0 {
        didSet {
            NSNotificationCenter.defaultCenter().postNotificationName(BraveGlobalShieldStats.DidUpdateNotification, object: nil)
        }
    }

    var trackingProtection: Int = 0 {
        didSet {
            NSNotificationCenter.defaultCenter().postNotificationName(BraveGlobalShieldStats.DidUpdateNotification, object: nil)
        }
    }

    var httpse: Int = 0 {
        didSet {
            NSNotificationCenter.defaultCenter().postNotificationName(BraveGlobalShieldStats.DidUpdateNotification, object: nil)
        }
    }
    
    var safeBrowsing: Int = 0 {
        didSet {
            NSNotificationCenter.defaultCenter().postNotificationName(BraveGlobalShieldStats.DidUpdateNotification, object: nil)
        }
    }
    
    var fpProtection: Int = 0 {
        didSet {
            NSNotificationCenter.defaultCenter().postNotificationName(BraveGlobalShieldStats.DidUpdateNotification, object: nil)
        }
    }
    

    enum Shield: String {
        case Adblock = "adblock"
        case TrackingProtection = "tracking_protection"
        case HTTPSE = "httpse"
        case SafeBrowsing = "safebrowsing"
        case FpProtection = "fp_protection"
    }
    
    private init() {
        adblock += prefs.integerForKey(Shield.Adblock.rawValue)
        trackingProtection += prefs.integerForKey(Shield.TrackingProtection.rawValue)
        httpse += prefs.integerForKey(Shield.HTTPSE.rawValue)
        safeBrowsing += prefs.integerForKey(Shield.SafeBrowsing.rawValue)
        fpProtection += prefs.integerForKey(Shield.FpProtection.rawValue)
    }

    var bgSaveTask: UIBackgroundTaskIdentifier?

    public func save() {
        if let t = bgSaveTask where t != UIBackgroundTaskInvalid {
            return
        }
        
        bgSaveTask = UIApplication.sharedApplication().beginBackgroundTaskWithName("brave-global-stats-save", expirationHandler: {
            if let task = self.bgSaveTask {
                UIApplication.sharedApplication().endBackgroundTask(task)
            }
            self.bgSaveTask = UIBackgroundTaskInvalid
        })
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) { () -> Void in
            self.prefs.setInteger(self.adblock, forKey: Shield.Adblock.rawValue)
            self.prefs.setInteger(self.trackingProtection, forKey: Shield.TrackingProtection.rawValue)
            self.prefs.setInteger(self.httpse, forKey: Shield.HTTPSE.rawValue)
            self.prefs.setInteger(self.safeBrowsing, forKey: Shield.SafeBrowsing.rawValue)
            self.prefs.setInteger(self.fpProtection, forKey: Shield.FpProtection.rawValue)
            self.prefs.synchronize()

            if let task = self.bgSaveTask {
                UIApplication.sharedApplication().endBackgroundTask(task)
            }
            self.bgSaveTask = UIBackgroundTaskInvalid
        }
    }
}
