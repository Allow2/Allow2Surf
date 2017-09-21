/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Shared
import JavaScriptCore

let kNotificationPageUnload = "kNotificationPageUnload"
let kNotificationAllWebViewsDeallocated = "kNotificationAllWebViewsDeallocated"

func convertNavActionToWKType(type:UIWebViewNavigationType) -> WKNavigationType {
    return WKNavigationType(rawValue: type.rawValue)!
}

class ContainerWebView : WKWebView {
    weak var legacyWebView: BraveWebView?
}

var globalContainerWebView = ContainerWebView()

protocol WebPageStateDelegate : class {
    func webView(webView: UIWebView, progressChanged: Float)
    func webView(webView: UIWebView, isLoading: Bool)
    func webView(webView: UIWebView, urlChanged: String)
    func webView(webView: UIWebView, canGoBack: Bool)
    func webView(webView: UIWebView, canGoForward: Bool)
}


@objc class HandleJsWindowOpen : NSObject {
    static func open(url: String) {
        postAsyncToMain(0) { // we now know JS callbacks can be off main
            guard let wv = BraveApp.getCurrentWebView() else { return }
            let current = wv.URL
            print("window.open")
            if BraveApp.getPrefs()?.boolForKey("blockPopups") ?? true {
                guard let lastTappedTime = wv.lastTappedTime else { return }
                if fabs(lastTappedTime.timeIntervalSinceNow) > 0.75 { // outside of the 3/4 sec time window and we ignore it
                    print(lastTappedTime.timeIntervalSinceNow)
                    return
                }
            }
            wv.lastTappedTime = nil
            if let _url = NSURL(string: url, relativeToURL: current) {
                getApp().browserViewController.openURLInNewTab(_url)
            }
        }
    }
}

class BrowserTabToUAMapper {
    static private let idToBrowserTab = NSMapTable(keyOptions: .StrongMemory, valueOptions: .WeakMemory)

    static func setId(uniqueId: Int, tab: Browser) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        idToBrowserTab.setObject(tab, forKey: uniqueId)
    }

    static func userAgentToBrowserTab(ua: String?) -> Browser? {
        // synchronize code from this point on.
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        guard let ua = ua else { return nil }
        guard let loc = ua.rangeOfString("_id/") else {
            // the first created webview doesn't have this id set (see webviewBuiltinUserAgent to explain)
            return idToBrowserTab.objectForKey(1) as? Browser
        }
        let keyString = ua.substringWithRange(loc.endIndex..<loc.endIndex.advancedBy(6))
        guard let key = Int(keyString) else { return nil }
        return idToBrowserTab.objectForKey(key) as? Browser
    }
}

struct BraveWebViewConstants {
    static let kNotificationWebViewLoadCompleteOrFailed = "kNotificationWebViewLoadCompleteOrFailed"
    static let kNotificationPageInteractive = "kNotificationPageInteractive"
    static let kContextMenuBlockNavigation = 8675309
}

class BraveWebView: UIWebView {
    class Weak_WebPageStateDelegate {     // We can't use a WeakList here because this is a protocol.
        weak var value : WebPageStateDelegate?
        init (value: WebPageStateDelegate) { self.value = value }
    }
    var delegatesForPageState = [Weak_WebPageStateDelegate]()

    let usingDesktopUserAgent: Bool
    let specialStopLoadUrl = "http://localhost.stop.load"
    weak var navigationDelegate: WKCompatNavigationDelegate?

    lazy var configuration: BraveWebViewConfiguration = { return BraveWebViewConfiguration(webView: self) }()
    lazy var backForwardList: WebViewBackForwardList = { return WebViewBackForwardList(webView: self) } ()
    var progress: WebViewProgress?
    var certificateInvalidConnection:NSURLConnection?

    var uniqueId = -1
    var knownFrameContexts = Set<NSObject>()
    private static var containerWebViewForCallbacks = { return ContainerWebView() }()
    // From http://stackoverflow.com/questions/14268230/has-anybody-found-a-way-to-load-https-pages-with-an-invalid-server-certificate-u
    var loadingUnvalidatedHTTPSPage: Bool = false



    var blankTargetLinkDetectionOn = true
    var lastTappedTime: NSDate?
    var removeBvcObserversOnDeinit: ((UIWebView) -> Void)?
    var removeProgressObserversOnDeinit: ((UIWebView) -> Void)?

    var safeBrowsingBlockTriggered:Bool = false
    
    var estimatedProgress: Double = 0
    var title: String = "" {
        didSet {
            if let item = backForwardList.currentItem {
                item.title = title
            }
        }
    }

    private var _url: (url: NSURL?, prevUrl: NSURL?) = (nil, nil)

    private var lastBroadcastedKvoUrl: String = ""
    // return true if set, false if unchanged
    func setUrl( newUrl: NSURL?) -> Bool {
        guard var newUrl = newUrl, let urlString = newUrl.absoluteString where !urlString.isEmpty else { return false }

        if urlString.endsWith("?") {
            if let noEndingQ = URL?.absoluteString?.componentsSeparatedByString("?")[0] {
                newUrl = NSURL(string: noEndingQ) ?? newUrl
            }
        }

        if urlString == _url.url?.absoluteString {
            return false
        }

        _url.prevUrl = _url.url
        _url.url = newUrl

        if urlString != lastBroadcastedKvoUrl {
            delegatesForPageState.forEach { $0.value?.webView(self, urlChanged: urlString) }
            lastBroadcastedKvoUrl = urlString
        }

        return true
    }

    var previousUrl: NSURL? { get { return _url.prevUrl } }

    var URL: NSURL? {
        get {
            return _url.url
        }
    }

    func updateLocationFromHtml() -> Bool {
        guard let js = stringByEvaluatingJavaScriptFromString("document.location.href"), let location = NSURL(string: js) else { return false }
        if AboutUtils.isAboutHomeURL(location) {
            return false
        }
        return setUrl(location)
    }

    private static var webviewBuiltinUserAgent = UserAgent.defaultUserAgent()

    // Needed to identify webview in url protocol
    func generateUniqueUserAgent() {
        struct StaticCounter {
            static var counter = 0
        }

        StaticCounter.counter += 1
        let userAgentBase = usingDesktopUserAgent ? kDesktopUserAgent : BraveWebView.webviewBuiltinUserAgent
        let userAgent = userAgentBase + String(format:" _id/%06d", StaticCounter.counter)
        let defaults = NSUserDefaults(suiteName: AppInfo.sharedContainerIdentifier())!
        defaults.registerDefaults(["UserAgent": userAgent ])
        self.uniqueId = StaticCounter.counter
    }

    private var braveShieldState = BraveShieldState()
    private func internalSetBraveShieldStateForDomain(domain: String) {
        braveShieldState = BraveShieldState.perNormalizedDomain[domain] ?? BraveShieldState()

        // we need to propagate this change to the thread-safe wrapper
        let stateCopy = braveShieldState
        let browserTab = getApp().tabManager.tabForWebView(self)
        postAsyncToMain() {
            browserTab?.braveShieldStateSafeAsync.set(stateCopy)
        }
    }

    func setShieldStateSafely(state: BraveShieldState) {
        assert(NSThread.isMainThread())
        if (!NSThread.isMainThread()) { return }
        braveShieldState = state
    }

    var triggeredLocationCheckTimer = NSTimer()
    // On page load, the contentSize of the webview is updated (**). If the webview has not been notified of a page change (i.e. shouldStartLoadWithRequest was never called) then 'loading' will be false, and we should check the page location using JS.
    // (** Not always updated, particularly on back/forward. For instance load duckduckgo.com, then google.com, and go back. No content size change detected.)
    func contentSizeChangeDetected() {
        if triggeredLocationCheckTimer.valid {
            return
        }

        // Add a time delay so that multiple calls are aggregated
        triggeredLocationCheckTimer = NSTimer.scheduledTimerWithTimeInterval(0.15, target: self, selector: #selector(timeoutCheckLocation), userInfo: nil, repeats: false)
    }

    // Pushstate navigation may require this case (see brianbondy.com), as well as sites for which simple pushstate detection doesn't work:
    // youtube and yahoo news are examples of this (http://stackoverflow.com/questions/24297929/javascript-to-listen-for-url-changes-in-youtube-html5-player)
    @objc func timeoutCheckLocation() {
        assert(NSThread.isMainThread())

        if URL?.isSpecialInternalUrl() ?? true {
            return
        }

        if !updateLocationFromHtml() {
            return
        }

        print("Page change detected by content size change triggered timer: \(URL?.absoluteString ?? "")")

        NSNotificationCenter.defaultCenter().postNotificationName(kNotificationPageUnload, object: self)
        shieldStatUpdate(.reset)
        progress?.reset()

        if (!loading ||
            stringByEvaluatingJavaScriptFromString("document.readyState.toLowerCase()") == "complete")
        {
            progress?.completeProgress()
        } else {
            progress?.setProgress(0.3)
            delegatesForPageState.forEach { $0.value?.webView(self, progressChanged: 0.3) }
        }
    }

    func updateTitleFromHtml() {
        if URL?.isSpecialInternalUrl() ?? false {
            title = ""
            return
        }
        if let t = stringByEvaluatingJavaScriptFromString("document.title") where !t.isEmpty {
            title = t
        } else {
            title = URL?.baseDomain() ?? ""
        }
    }

    required init(frame: CGRect, useDesktopUserAgent: Bool) {
        self.usingDesktopUserAgent = useDesktopUserAgent
        super.init(frame: frame)
        commonInit()
    }

    static var allocCounter = 0

    private func commonInit() {
        BraveWebView.allocCounter += 1
        print("webview init  \(BraveWebView.allocCounter)")
        generateUniqueUserAgent()

        progress = WebViewProgress(parent: self)

        mediaPlaybackRequiresUserAction = true
        delegate = self
        scalesPageToFit = true
        scrollView.showsHorizontalScrollIndicator = false
        allowsInlineMediaPlayback = true
        opaque = false
        backgroundColor = UIColor.whiteColor()

        let rate = UIScrollViewDecelerationRateFast + (UIScrollViewDecelerationRateNormal - UIScrollViewDecelerationRateFast) * 0.5;
            scrollView.setValue(NSValue(CGSize: CGSizeMake(rate, rate)), forKey: "_decelerationFactor")

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(firstLayoutPerformed), name: swizzledFirstLayoutNotification, object: nil)
    }

    func firstLayoutPerformed() {
        updateLocationFromHtml()
    }

    var jsBlockedStatLastUrl: String? = nil
    func checkScriptBlockedAndBroadcastStats() {
        let state = braveShieldState
        if state.isOnScriptBlocking() ?? BraveApp.getPrefs()?.boolForKey(kPrefKeyNoScriptOn) ?? false {
            let jsBlocked = Int(stringByEvaluatingJavaScriptFromString("document.getElementsByTagName('script').length") ?? "0") ?? 0

            if request?.URL?.absoluteString == jsBlockedStatLastUrl && jsBlocked == 0 {
                return
            }
            jsBlockedStatLastUrl = request?.URL?.absoluteString

            shieldStatUpdate(.jsSetValue, increment: jsBlocked)
        } else {
            shieldStatUpdate(.broadcastOnly)
        }
    }

    func internalProgressNotification(notification: NSNotification) {
        if let prog = notification.userInfo?["WebProgressEstimatedProgressKey"] as? Double {
            progress?.setProgress(prog)
            if prog > 0.99 {
                loadingCompleted()
            }
        }
    }

    override var loading: Bool {
        get {
            return estimatedProgress > 0 && estimatedProgress < 0.99
        }
    }

    required init?(coder aDecoder: NSCoder) {
        self.usingDesktopUserAgent = false
        super.init(coder: aDecoder)
        commonInit()
    }

    deinit {
        BraveWebView.allocCounter -= 1
        if (BraveWebView.allocCounter == 0) {
            NSNotificationCenter.defaultCenter().postNotificationName(kNotificationAllWebViewsDeallocated, object: nil)
            print("NO LIVE WEB VIEWS")
        }

        NSNotificationCenter.defaultCenter().removeObserver(self)

        _ = Try(withTry: {
            self.removeBvcObserversOnDeinit?(self)
        }) { (exception) -> Void in
            print("Failed remove: \(exception)")
        }

        _ = Try(withTry: {
            self.removeProgressObserversOnDeinit?(self)
        }) { (exception) -> Void in
            print("Failed remove: \(exception)")
        }

        print("webview deinit \(title) ")
    }

    var blankTargetUrl: String?

    func urlBlankTargetTapped(url: String) {
        blankTargetUrl = url
    }

    let internalProgressStartedNotification = "WebProgressStartedNotification"
    let internalProgressChangedNotification = "WebProgressEstimateChangedNotification"
    let internalProgressFinishedNotification = "WebProgressFinishedNotification" // Not usable

    let swizzledFirstLayoutNotification = "WebViewFirstLayout" // not broadcast on history push nav

    override func loadRequest(request: NSURLRequest) {
        clearLoadCompletedHtmlProperty()

        guard let internalWebView = valueForKeyPath("documentView.webView") else { return }
        NSNotificationCenter.defaultCenter().removeObserver(self, name: internalProgressChangedNotification, object: internalWebView)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(BraveWebView.internalProgressNotification(_:)), name: internalProgressChangedNotification, object: internalWebView)

        if let url = request.URL, domain = url.normalizedHost() {
            internalSetBraveShieldStateForDomain(domain)
        }
        super.loadRequest(request)
    }

    enum LoadCompleteHtmlPropertyOption {
        case setCompleted, checkIsCompleted, clear, debug
    }

    // Not pretty, but we set some items on the page to know when the load completion arrived
    // You would think the DOM gets refreshed on page change, but not with modern js lib navigation
    // Domain changes will reset the DOM, which is easily to detect, but path changes require a few properties to reliably detect
    func loadCompleteHtmlProperty(option option: LoadCompleteHtmlPropertyOption) -> Bool {
        let sentinels = ["_brave_cached_title": "document.title", "_brave_cached_location" : "location.href"]

        if option == .debug {
            let js = sentinels.values.joinWithSeparator(",")
            print(stringByEvaluatingJavaScriptFromString("JSON.stringify({ \(js) })"))
            return false
        }

        let oper = (option != .checkIsCompleted) ? " = " : " === "
        let joiner = (option != .checkIsCompleted) ? "; " : " && "

        var js = sentinels.map{ $0 + oper + (option == .clear ? "''" :$1) }.joinWithSeparator(joiner)
        if option == .checkIsCompleted {
            js = "('_brave_cached_title' in window) && \(js) "
        }
        return stringByEvaluatingJavaScriptFromString(js) == "true"
    }

    private func isLoadCompletedHtmlPropertySet() -> Bool {
        return loadCompleteHtmlProperty(option: .checkIsCompleted)
    }

    private func setLoadCompletedHtmlProperty() {
        loadCompleteHtmlProperty(option: .setCompleted)
    }

    private func clearLoadCompletedHtmlProperty() {
        loadCompleteHtmlProperty(option: .clear)
    }

    func loadingCompleted() {
        if isLoadCompletedHtmlPropertySet() {
            return
        }
        setLoadCompletedHtmlProperty()

        print("loadingCompleted() ••••")
        progress?.setProgress(1.0)
        broadcastToPageStateDelegates()

        navigationDelegate?.webViewDidFinishNavigation(self, url: URL)

        if safeBrowsingBlockTriggered {
            return
        }

        // Wait a tiny bit in hopes the page contents are updated. Load completed doesn't mean the UIWebView has done any rendering (or even has the JS engine for the page ready, see the delay() below)
        postAsyncToMain(0.1) {
            [weak self] in
            guard let me = self, tab = getApp().tabManager.tabForWebView(me) else {
                    return
            }

            me.updateLocationFromHtml()
            me.updateTitleFromHtml()
            tab.lastExecutedTime = NSDate.now()
            getApp().browserViewController.updateProfileForLocationChange(tab)

            me.configuration.userContentController.injectJsIntoPage()
            NSNotificationCenter.defaultCenter().postNotificationName(BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed, object: me)
            LegacyUserContentController.injectJsIntoAllFrames(me, script: "document.body.style.webkitTouchCallout='none'")

            me.stringByEvaluatingJavaScriptFromString("console.log('get favicons'); __firefox__.favicons.getFavicons()")

            postAsyncToMain(0.3) { // the longer we wait, the more reliable the result (even though this script does polling for a result)
                [weak self] in
                let readerjs = ReaderModeNamespace + ".checkReadability()"
                self?.stringByEvaluatingJavaScriptFromString(readerjs)
            }

            me.checkScriptBlockedAndBroadcastStats()

            getApp().tabManager.expireSnackbars()
            getApp().browserViewController.screenshotHelper.takeDelayedScreenshot(tab)
            getApp().browserViewController.addOpenInViewIfNeccessary(tab.url)
        }
    }

    // URL changes are NOT broadcast here. Have to be selective with those until the receiver code is improved to be more careful about updating
    func broadcastToPageStateDelegates() {
        delegatesForPageState.forEach {
            $0.value?.webView(self, isLoading: loading)
            $0.value?.webView(self, canGoBack: canGoBack)
            $0.value?.webView(self, canGoForward: canGoForward)
            $0.value?.webView(self, progressChanged: loading ? Float(estimatedProgress) : 1.0)
        }
    }

    func canNavigateBackward() -> Bool {
        return self.canGoBack
    }

    func canNavigateForward() -> Bool {
        return self.canGoForward
    }

    func reloadFromOrigin() {
        self.reload()
    }

    override func reload() {
        clearLoadCompletedHtmlProperty()
        shieldStatUpdate(.reset)
        progress?.setProgress(0.3)
        NSURLCache.sharedURLCache().removeAllCachedResponses()
        NSURLCache.sharedURLCache().diskCapacity = 0
        NSURLCache.sharedURLCache().memoryCapacity = 0

        if let url = URL, domain = url.normalizedHost() {
            internalSetBraveShieldStateForDomain(domain)
            (getApp().browserViewController as! BraveBrowserViewController).updateBraveShieldButtonState(animated: false)
        }
        super.reload()
        
        BraveApp.setupCacheDefaults()
    }

    override func stopLoading() {
        super.stopLoading()
        self.progress?.reset()
    }

    private func convertStringToDictionary(text: String?) -> [String:AnyObject]? {
        if let data = text?.dataUsingEncoding(NSUTF8StringEncoding) where text?.characters.count > 0 {
            do {
                let json = try NSJSONSerialization.JSONObjectWithData(data, options: .MutableContainers) as? [String:AnyObject]
                return json
            } catch {
                print("Something went wrong")
            }
        }
        return nil
    }

    func evaluateJavaScript(javaScriptString: String, completionHandler: ((AnyObject?, NSError?) -> Void)?) {
        postAsyncToMain(0) { // evaluateJavaScript is for compat with WKWebView/Firefox, I didn't vet all the uses, guard by posting to main
            let wrapped = "var result = \(javaScriptString); JSON.stringify(result)"
            let string = self.stringByEvaluatingJavaScriptFromString(wrapped)
            let dict = self.convertStringToDictionary(string)
            completionHandler?(dict, NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotOpenFile, userInfo: nil))
        }
    }

    func goToBackForwardListItem(item: LegacyBackForwardListItem) {
        if let index = backForwardList.backList.indexOf(item) {
            let backCount = backForwardList.backList.count - index
            for _ in 0..<backCount {
                goBack()
            }
        } else if let index = backForwardList.forwardList.indexOf(item) {
            for _ in 0..<(index + 1) {
                goForward()
            }
        }
    }

    override func goBack() {
        clearLoadCompletedHtmlProperty()

        // stop scrolling so the web view will respond faster
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        NSNotificationCenter.defaultCenter().postNotificationName(kNotificationPageUnload, object: self)
        super.goBack()
    }

    override func goForward() {
        clearLoadCompletedHtmlProperty()

        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        NSNotificationCenter.defaultCenter().postNotificationName(kNotificationPageUnload, object: self)
        super.goForward()
    }

    class func isTopFrameRequest(request:NSURLRequest) -> Bool {
        guard let url = request.URL, mainDoc = request.mainDocumentURL else { return false }
        return url.host == mainDoc.host && url.path == mainDoc.path
    }

    // Long press context menu text selection overriding
    override func canPerformAction(action: Selector, withSender sender: AnyObject?) -> Bool {
        return super.canPerformAction(action, withSender: sender)
    }

    func injectCSS(css: String) {
        var js = "var script = document.createElement('style');"
        js += "script.type = 'text/css';"
        js += "script.innerHTML = '\(css)';"
        js += "document.head.appendChild(script);"
        LegacyUserContentController.injectJsIntoAllFrames(self, script: js)
    }

    enum ShieldStatUpdate {
        case reset
        case broadcastOnly
        case httpseIncrement
        case abIncrement
        case tpIncrement
        case jsSetValue
        case fpIncrement
    }

    var shieldStats = ShieldBlockedStats()

    // Some sites will re-try loads (us.yahoo.com). Trivially block this case by keeping small list of recently blocked
    struct RecentlyBlocked {
        var urls = [String](count: 5, repeatedValue: "")
        var insertAtIndex = 0
    }
    var recentlyBlocked = RecentlyBlocked()

    func shieldStatUpdate(stat: ShieldStatUpdate, increment: Int = 1, affectedUrl: String = "") {
        if !affectedUrl.isEmpty {
            if recentlyBlocked.urls.contains(affectedUrl) {
                return
            }
            recentlyBlocked.urls[recentlyBlocked.insertAtIndex] = affectedUrl
            recentlyBlocked.insertAtIndex = (recentlyBlocked.insertAtIndex + 1) % recentlyBlocked.urls.count
        }

        switch stat {
        case .broadcastOnly:
            break
        case .reset:
            shieldStats = ShieldBlockedStats()
            recentlyBlocked = RecentlyBlocked()
        case .httpseIncrement:
            shieldStats.httpse += increment
            BraveGlobalShieldStats.singleton.httpse += increment
        case .abIncrement:
            shieldStats.abAndTp += increment
            BraveGlobalShieldStats.singleton.adblock += increment
        case .tpIncrement:
            shieldStats.abAndTp += increment
            BraveGlobalShieldStats.singleton.trackingProtection += increment
        case .jsSetValue:
            shieldStats.js = increment
        case .fpIncrement:
            shieldStats.fp += increment
            BraveGlobalShieldStats.singleton.fpProtection += increment
        }

        postAsyncToMain(0.2) { [weak self] in
            if let me = self where BraveApp.getCurrentWebView() === me {
                getApp().braveTopViewController.rightSidePanel.setShieldBlockedStats(me.shieldStats)
            }
        }
    }
}

extension BraveWebView: UIWebViewDelegate {

    class LegacyNavigationAction : WKNavigationAction {
        var writableRequest: NSURLRequest
        var writableType: WKNavigationType

        init(type: WKNavigationType, request: NSURLRequest) {
            writableType = type
            writableRequest = request
            super.init()
        }

        override var request: NSURLRequest { get { return writableRequest} }
        override var navigationType: WKNavigationType { get { return writableType } }
        override var sourceFrame: WKFrameInfo {
            get { return WKFrameInfo() }
        }
    }

    func webView(webView: UIWebView,shouldStartLoadWithRequest request: NSURLRequest, navigationType: UIWebViewNavigationType ) -> Bool {
        guard let url = request.URL else { return false }

        webView.backgroundColor = UIColor.whiteColor()

        if let contextMenu = window?.rootViewController?.presentedViewController
            where contextMenu.view.tag == BraveWebViewConstants.kContextMenuBlockNavigation {
            // When showing a context menu, the webview will often still navigate (ex. news.google.com)
            // We need to block navigation using this tag.
            return false
        }

        if let tab = getApp().tabManager.tabForWebView(self) {
            let state = braveShieldState
            var fpShieldOn = !state.isAllOff() && (state.isOnFingerprintProtection() ?? BraveApp.getPrefs()?.boolForKey(kPrefKeyFingerprintProtection) ?? false)

            // Override for automated testing
            if URLProtocol.testShieldState?.isOnFingerprintProtection() ?? false {
                fpShieldOn = true
            }

            if fpShieldOn {
                if tab.getHelper(FingerprintingProtection.self) == nil {
                    let fp = FingerprintingProtection(browser: tab)
                    tab.addHelper(fp)
                }
            } else {
                tab.removeHelper(FingerprintingProtection.self)
            }
        }

        if url.absoluteString == blankTargetUrl {
            blankTargetUrl = nil
            print(url)
            getApp().browserViewController.openURLInNewTab(url)
            return false
        }
        blankTargetUrl = nil

        if url.scheme == "mailto" {
            UIApplication.sharedApplication().openURL(url)
            return false
        }

        if AboutUtils.isAboutHomeURL(url) {
            setUrl(url)
            progress?.setProgress(1.0)
            return true
        }

        if url.absoluteString?.contains(specialStopLoadUrl) ?? false {
            progress?.completeProgress()
            return false
        }

        if loadingUnvalidatedHTTPSPage {
            certificateInvalidConnection = NSURLConnection(request: request, delegate: self)
            certificateInvalidConnection?.start()
            return false
        }

        if let progressCheck = progress?.shouldStartLoadWithRequest(request, navigationType: navigationType) where !progressCheck {
            return false
        }

        if let nd = navigationDelegate {
            var shouldLoad = true
            nd.webViewDecidePolicyForNavigationAction(self, url: url, shouldLoad: &shouldLoad)
            if !shouldLoad {
                return false
            }
        }

        if url.scheme?.startsWith("itms") ?? false || url.host == "itunes.apple.com" {
            progress?.completeProgress()
            return false
        }

        let locationChanged = BraveWebView.isTopFrameRequest(request) && url.absoluteString != URL?.absoluteString
        if locationChanged {
            blankTargetLinkDetectionOn = true
            // TODO Maybe separate page unload from link clicked.
            NSNotificationCenter.defaultCenter().postNotificationName(kNotificationPageUnload, object: self)
            setUrl(url)
            #if DEBUG
                print("Page changed by shouldStartLoad: \(URL?.absoluteString ?? "")")
            #endif

            if let url = request.URL, domain = url.normalizedHost() {
                internalSetBraveShieldStateForDomain(domain)
            }

            shieldStatUpdate(.reset)
        }

        broadcastToPageStateDelegates()

        return true
    }


    func webViewDidStartLoad(webView: UIWebView) {
        backForwardList.update()
        
        if let nd = navigationDelegate {
            // this triggers the network activity spinner
            globalContainerWebView.legacyWebView = self
            nd.webViewDidStartProvisionalNavigation(self, url: URL)
        }
        progress?.webViewDidStartLoad()

        delegatesForPageState.forEach { $0.value?.webView(self, isLoading: true) }

        #if !TEST
            HideEmptyImages.runJsInWebView(self)
        #endif

        configuration.userContentController.injectFingerprintProtection()
    }

    func webViewDidFinishLoad(webView: UIWebView) {
        assert(NSThread.isMainThread())
#if DEBUGJS
        let context = valueForKeyPath("documentView.webView.mainFrame.javaScriptContext") as! JSContext
        let logFunction : @convention(block) (String) -> Void = { (msg: String) in
            NSLog("Console: %@", msg)
        }
        context.objectForKeyedSubscript("console").setObject(unsafeBitCast(logFunction, AnyObject.self), forKeyedSubscript: "log")
#endif
        // browserleaks canvas requires injection at this point
        configuration.userContentController.injectFingerprintProtection()

        let readyState = stringByEvaluatingJavaScriptFromString("document.readyState.toLowerCase()")
        updateTitleFromHtml()

        if let isSafeBrowsingBlock = stringByEvaluatingJavaScriptFromString("document['BraveSafeBrowsingPageResult']") {
            safeBrowsingBlockTriggered = (isSafeBrowsingBlock as NSString).boolValue
        }

        progress?.webViewDidFinishLoad(documentReadyState: readyState)

        backForwardList.update()
        broadcastToPageStateDelegates()
    }

    func webView(webView: UIWebView, didFailLoadWithError error: NSError) {
        print("didFailLoadWithError: \(error)")
        guard let errorUrl = error.userInfo[NSURLErrorFailingURLErrorKey] as? NSURL else { return }
        if errorUrl.isSpecialInternalUrl() {
            return
        }

        if (error.domain == NSURLErrorDomain) &&
               (error.code == NSURLErrorServerCertificateHasBadDate      ||
                error.code == NSURLErrorServerCertificateUntrusted         ||
                error.code == NSURLErrorServerCertificateHasUnknownRoot    ||
                error.code == NSURLErrorServerCertificateNotYetValid)
        {
            if errorUrl.absoluteString?.regexReplacePattern("^.+://", with: "") != URL?.absoluteString?.regexReplacePattern("^.+://", with: "") {
                print("only show cert error for top-level page")
                return
            }

            let alertUrl = errorUrl.absoluteString ?? "this site"
            let alert = UIAlertController(title: "Certificate Error", message: "The identity of \(alertUrl) can't be verified", preferredStyle: UIAlertControllerStyle.Alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.Default) {
                handler in
                self.stopLoading()
                webView.loadRequest(NSURLRequest(URL: NSURL(string: self.specialStopLoadUrl)!))

                // The current displayed url is wrong, so easiest hack is:
                if (self.canGoBack) { // I don't think the !canGoBack case needs handling
                    self.goBack()
                    self.goForward()
                }
                })
            alert.addAction(UIAlertAction(title: "Continue", style: UIAlertActionStyle.Default) {
                handler in
                self.loadingUnvalidatedHTTPSPage = true;
                self.loadRequest(NSURLRequest(URL: errorUrl))
                })

            window?.rootViewController?.presentViewController(alert, animated: true, completion: nil)
            return
        }

        NSNotificationCenter.defaultCenter()
            .postNotificationName(BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed, object: self)

        // The error may not be the main document that failed to load. Check if the failing URL matches the URL being loaded

        if let errorUrl = error.userInfo[NSURLErrorFailingURLErrorKey] as? NSURL {
            var handled = false
            if error.code == -1009 /*kCFURLErrorNotConnectedToInternet*/ {
                let cache = NSURLCache.sharedURLCache().cachedResponseForRequest(NSURLRequest(URL: errorUrl))
                if let html = cache?.data.utf8EncodedString where html.characters.count > 100 {
                    loadHTMLString(html, baseURL: errorUrl)
                    handled = true
                }
            }

            let kPluginIsHandlingLoad = 204 // mp3 for instance, returns an error to webview that a plugin is taking over, which is correct
            if !handled && URL?.absoluteString == errorUrl.absoluteString && error.code != kPluginIsHandlingLoad {
                if let nd = navigationDelegate {
                    globalContainerWebView.legacyWebView = self
                    nd.webViewDidFailNavigation(self, withError: error ?? NSError.init(domain: "", code: 0, userInfo: nil))
                }
            }
        }

        (webView as! BraveWebView).updateLocationFromHtml()
        postAsyncToMain(1) {
            // There is no order of event guarantee, so in case some other event sets self.URL AFTER page error, do added check
            [weak webView] in
            (webView as? BraveWebView)?.updateLocationFromHtml()
        }

        progress?.didFailLoadWithError()
        broadcastToPageStateDelegates()
    }
}

extension BraveWebView : NSURLConnectionDelegate, NSURLConnectionDataDelegate {
    func connection(connection: NSURLConnection, willSendRequestForAuthenticationChallenge challenge: NSURLAuthenticationChallenge) {
        guard let trust = challenge.protectionSpace.serverTrust else { return }
        let cred = NSURLCredential(forTrust: trust)
        challenge.sender?.useCredential(cred, forAuthenticationChallenge: challenge)
        challenge.sender?.continueWithoutCredentialForAuthenticationChallenge(challenge)
        loadingUnvalidatedHTTPSPage = false
    }

    func connection(connection: NSURLConnection, didReceiveResponse response: NSURLResponse) {
        guard let url = URL else { return }
        loadingUnvalidatedHTTPSPage = false
        loadRequest(NSURLRequest(URL: url))
        certificateInvalidConnection?.cancel()
    }    
}
