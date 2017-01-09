/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import Deferred
#if !NO_FABRIC
    import Fabric
    import Crashlytics
    import Mixpanel
#endif
import Allow2

#if !DEBUG
    func print(items: Any..., separator: String = " ", terminator: String = "\n") {}
#endif

private let _singleton = BraveApp()

let kAppBootingIncompleteFlag = "kAppBootingIncompleteFlag"
let kDesktopUserAgent = "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_11_6) AppleWebKit/537.36 (KHTML, like Gecko) Version/5.0 Safari/537.36"

#if !TEST
    func getApp() -> AppDelegate {
        return UIApplication.sharedApplication().delegate as! AppDelegate
    }
#endif

extension NSURL {
    // The url is a local webserver url or an about url, a.k.a something we don't display to users
    public func isSpecialInternalUrl() -> Bool {
        assert(WebServer.sharedInstance.base.startsWith("http"))
        return (absoluteString ?? "").startsWith(WebServer.sharedInstance.base) || AboutUtils.isAboutURL(self)
    }
}

// Any app-level hooks we need from Firefox, just add a call to here
class BraveApp {
    static var isSafeToRestoreTabs = true
    // If app runs for this long, clear the saved pref that indicates it is safe to restore tabs
    static let kDelayBeforeDecidingAppHasBootedOk = (Int64(NSEC_PER_SEC) * 10) // 10 sec

    var allow2Timer : NSTimer?
    let allow2Activities = [ Allow2.Allow2Activity(activity: Allow2.Activity.Internet, log: true) ]    // just log internet usage = browser use
    
    class var singleton: BraveApp {
        return _singleton
    }

    #if !TEST
    class func getCurrentWebView() -> BraveWebView? {
        return getApp().browserViewController.tabManager.selectedTab?.webView
    }
    #endif

    private init() {
    }

    class func isIPhoneLandscape() -> Bool {
        return UIDevice.currentDevice().userInterfaceIdiom == .Phone &&
            UIInterfaceOrientationIsLandscape(UIApplication.sharedApplication().statusBarOrientation)
    }

    class func isIPhonePortrait() -> Bool {
        return UIDevice.currentDevice().userInterfaceIdiom == .Phone &&
            UIInterfaceOrientationIsPortrait(UIApplication.sharedApplication().statusBarOrientation)
    }

    class func setupCacheDefaults() {
        NSURLCache.sharedURLCache().memoryCapacity = 6 * 1024 * 1024; // 6 MB
        NSURLCache.sharedURLCache().diskCapacity = 40 * 1024 * 1024;
    }

    class func didFinishLaunching() {
        #if !NO_FABRIC
            let telemetryOn = getApp().profile!.prefs.intForKey(BraveUX.PrefKeyUserAllowsTelemetry) ?? 1 == 1
            if telemetryOn {
                Fabric.with([Crashlytics.self])

                if let dict = NSBundle.mainBundle().infoDictionary, let token = dict["MIXPANEL_TOKEN"] as? String {
                    // note: setting this in willFinishLaunching is causing a crash, keep it in didFinish
                    mixpanelInstance = Mixpanel.initialize(token: token)
                    mixpanelInstance?.serverURL = "https://metric-proxy.brave.com"
                }
            }
       #endif

        postAsyncToMain(10) {
            updateDauStat()
        }
    }

    // Be aware: the Prefs object has not been created yet
    class func willFinishLaunching_begin() {
        BraveApp.setupCacheDefaults()
        NSURLProtocol.registerClass(URLProtocol);

        NSNotificationCenter.defaultCenter().addObserver(BraveApp.singleton,
             selector: #selector(BraveApp.didEnterBackground(_:)), name: UIApplicationDidEnterBackgroundNotification, object: nil)

        NSNotificationCenter.defaultCenter().addObserver(BraveApp.singleton,
             selector: #selector(BraveApp.willEnterForeground(_:)), name: UIApplicationWillEnterForegroundNotification, object: nil)

        NSNotificationCenter.defaultCenter().addObserver(BraveApp.singleton,
             selector: #selector(BraveApp.memoryWarning(_:)), name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)

        #if !TEST
            //  these quiet the logging from the core of fx ios
            // GCDWebServer.setLogLevel(5)
            Logger.syncLogger.setup(.None)
            Logger.browserLogger.setup(.None)
        #endif

        #if DEBUG
            // desktop UA for testing
            //      let defaults = NSUserDefaults(suiteName: AppInfo.sharedContainerIdentifier())!
            //      defaults.registerDefaults(["UserAgent": kDesktopUserAgent])

        #endif
    }

    // Prefs are created at this point
    class func willFinishLaunching_end() {
        BraveApp.isSafeToRestoreTabs = BraveApp.getPrefs()?.stringForKey(kAppBootingIncompleteFlag) == nil
        BraveApp.getPrefs()?.setString("remove me when booted", forKey: kAppBootingIncompleteFlag)

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, BraveApp.kDelayBeforeDecidingAppHasBootedOk),
                       dispatch_get_main_queue(), {
                        BraveApp.getPrefs()?.removeObjectForKey(kAppBootingIncompleteFlag)
        })


        let args = NSProcessInfo.processInfo().arguments
        if args.contains("BRAVE-TEST-CLEAR-PREFS") {
            BraveApp.getPrefs()!.clearAll()
        }
        if args.contains("BRAVE-TEST-NO-SHOW-INTRO") {
            BraveApp.getPrefs()!.setInt(1, forKey: IntroViewControllerSeenProfileKey)
        }
        if args.contains("BRAVE-TEST-SHOW-OPT-IN") {
            BraveApp.getPrefs()!.removeObjectForKey(BraveUX.PrefKeyOptInDialogWasSeen)
        }
        if args.contains("BRAVE-DELETE-BOOKMARKS") {
            succeed().upon { _ in
                getApp().profile!.bookmarks.modelFactory >>== {
                    $0.clearBookmarks().uponQueue(dispatch_get_main_queue()) { res in
                        // test case should just sleep or wait for bm count to be zero
                    }
                }
            }
        }
        if args.contains("BRAVE-UI-TEST") || AppConstants.IsRunningTestNonUI {
            // Maybe we will need a specific flag to keep tabs for restoration testing
            BraveApp.isSafeToRestoreTabs = false

            if args.filter({ $0.startsWith("BRAVE") }).count == 1 || AppConstants.IsRunningTestNonUI { // only contains 1 arg
                BraveApp.getPrefs()!.setInt(1, forKey: IntroViewControllerSeenProfileKey)
                BraveApp.getPrefs()!.setInt(1, forKey: BraveUX.PrefKeyOptInDialogWasSeen)
            }
        }

        AdBlocker.singleton.networkFileLoader.loadData()
        SafeBrowsing.singleton.networkFileLoader.loadData()
        TrackingProtection.singleton.networkFileLoader.loadData()
        HttpsEverywhere.singleton.networkFileLoader.loadData()

        #if !TEST
            PrivateBrowsing.singleton.startupCheckIfKilledWhileInPBMode()
            CookieSetting.setupOnAppStart()
            PasswordManagerButtonSetting.setupOnAppStart()
            //BlankTargetLinkHandler.updatedEnabledState()
        #endif

        getApp().profile?.loadBraveShieldsPerBaseDomain().upon() {
            postAsyncToMain(0) { // back to main thread
                guard let shieldState = getApp().tabManager.selectedTab?.braveShieldStateSafeAsync.get() else { return }
                if let wv = getCurrentWebView(), url = wv.URL, base = url.normalizedHost(), dbState = BraveShieldState.perNormalizedDomain[base] where shieldState.isNotSet() {
                    // on init, the webview's shield state doesn't match the db
                    getApp().tabManager.selectedTab?.braveShieldStateSafeAsync.set(dbState)
                    wv.reloadFromOrigin()
                }
            }
        }
        
        // check usage while in the foreground
        BraveApp.singleton.startAllow2Timer()
    }

    // This can only be checked ONCE, the flag is cleared after this.
    // This is because BrowserViewController asks this question after the startup phase,
    // when tabs are being created by user actions. So without more refactoring of the
    // Firefox logic, this is the simplest solution.
    class func shouldRestoreTabs() -> Bool {
        let ok = BraveApp.isSafeToRestoreTabs
        BraveApp.isSafeToRestoreTabs = true
        return ok
    }

    @objc func memoryWarning(_: NSNotification) {
        NSURLCache.sharedURLCache().memoryCapacity = 0
        BraveApp.setupCacheDefaults()
        getApp().tabManager.memoryWarning()
    }

    @objc func didEnterBackground(_: NSNotification) {
        allow2Timer?.invalidate()
        allow2Timer = nil
    }

    @objc func willEnterForeground(_ : NSNotification) {
        // check usage while in the foreground
        startAllow2Timer()
    }
    
    @objc func startAllow2Timer() {
        if (allow2Timer == nil) {
            allow2Timer = NSTimer.scheduledTimerWithTimeInterval(10.0, target: self, selector: #selector(BraveApp.checkAllow2), userInfo: nil, repeats: true)
            Allow2.sharedInstance.check(allow2Activities)
        }
    }
    
    @objc func checkAllow2() {
        Allow2.sharedInstance.check(allow2Activities)
    }

    class func shouldHandleOpenURL(components: NSURLComponents) -> Bool {
        // TODO look at what x-callback is for
        let handled = components.scheme == "brave" || components.scheme == "brave-x-callback"
        if (handled) {
            telemetry(action: "Open in brave", props: nil)
        }
        return handled
    }

    class func getPrefs() -> Prefs? {
        return getApp().profile?.prefs
    }

    static func showErrorAlert(title title: String,  error: String) {
        postAsyncToMain(0) { // this utility function can be called from anywhere
            UIAlertView(title: title, message: error, delegate: nil, cancelButtonTitle: "Close").show()
        }
    }

    static func statusBarHeight() -> CGFloat {
        if UIScreen.mainScreen().traitCollection.verticalSizeClass == .Compact {
            return 0
        }
        return 20
    }

    static var isPasswordManagerInstalled: Bool?

    static func is3rdPartyPasswordManagerInstalled(refreshLookup refreshLookup: Bool) -> Deferred<Bool> {
        let deferred = Deferred<Bool>()
        if refreshLookup || isPasswordManagerInstalled == nil {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) {
                isPasswordManagerInstalled = OnePasswordExtension.sharedExtension().isAppExtensionAvailable()
                deferred.fill(isPasswordManagerInstalled!)
            }
        } else {
            deferred.fill(isPasswordManagerInstalled!)
        }
        return deferred
    }
}

extension BraveApp {

    static func updateDauStat() {

        guard let prefs = getApp().profile?.prefs else { return }
        let prefName = "dau_stat"
        let dauStat = prefs.arrayForKey(prefName)

        let appVersion = NSBundle.mainBundle().objectForInfoDictionaryKey("CFBundleShortVersionString") as! String
        var statsQuery = "https://laptop-updates.brave.com/1/usage/ios?platform=ios" + "&channel=\(BraveUX.IsRelease ? "stable" : "beta")"
            + "&version=\(appVersion)"
            + "&first=\(dauStat != nil)"

        let today = NSDate()
        let components = NSCalendar.currentCalendar().components([.Month , .Year], fromDate: today)
        let year =  components.year
        let month = components.month

        if let stat = dauStat as? [Int] where stat.count == 3 {
            let dSecs = Int(today.timeIntervalSince1970) - stat[0]
            let _month = stat[1]
            let _year = stat[2]
            let SECONDS_IN_A_DAY = 86400
            let SECONDS_IN_A_WEEK = 7 * 86400
            let daily = dSecs >= SECONDS_IN_A_DAY
            let weekly = dSecs >= SECONDS_IN_A_WEEK
            let monthly = month != _month || year != _year
            if (!daily && !weekly && !monthly) {
               return
            }
            statsQuery += "&daily=\(daily)&weekly=\(weekly)&monthly=\(monthly)"
        }

        let secsMonthYear = [Int(today.timeIntervalSince1970), month, year]
        prefs.setObject(secsMonthYear, forKey: prefName)

        guard let url = NSURL(string: statsQuery) else {
            if !BraveUX.IsRelease {
                BraveApp.showErrorAlert(title: "Debug", error: "failed stats update")
            }
            return
        }
        let task = NSURLSession.sharedSession().dataTaskWithURL(url) {
            (_, _, error) in
            if let e = error { NSLog("status update error: \(e)") }
        }
        task.resume()
    }
}


