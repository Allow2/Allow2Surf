/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
import SnapKit
import SafariServices

class BraveBrowserViewController : BrowserViewController {
    var historySwiper = HistorySwiper()

    override func applyTheme(themeName: String) {
        super.applyTheme(themeName)

        toolbar?.accessibilityLabel = "bottomToolbar"
        webViewContainerBackdrop.accessibilityLabel = "webViewContainerBackdrop"
        webViewContainer.accessibilityLabel = "webViewContainer"
        statusBarOverlay.accessibilityLabel = "statusBarOverlay"
        urlBar.accessibilityLabel = "BraveUrlBar"

        toolbar?.applyTheme(themeName)
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)

        struct RunOnceAtStartup { static var ran = false }
        if !RunOnceAtStartup.ran && profile.prefs.boolForKey(kPrefKeyPrivateBrowsingAlwaysOn) ?? false {
            getApp().browserViewController.switchToPrivacyMode()
            getApp().tabManager.addTabAndSelect(isPrivate: true)
        }

        RunOnceAtStartup.ran = true
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        let showingIntroScreen = profile.prefs.intForKey(IntroViewControllerSeenProfileKey) == nil
        if !showingIntroScreen && profile.prefs.intForKey(BraveUX.PrefKeyOptInDialogWasSeen) == nil {
            presentOptInDialog()
        }

        self.updateToolbarStateForTraitCollection(self.traitCollection)
        
        // TODO: Should never call setupConstraints multiple times, this can cause huge headaches. Constraints should mostly be static with adjustments made to those constraints.
        setupConstraints()
        if BraveApp.shouldRestoreTabs() {
            tabManager.restoreTabs()
        } else {
            tabManager.addTabAndSelect()
        }

        updateTabCountUsingTabManager(tabManager, animated: false)

        footer.accessibilityLabel = "footer"
        footerBackdrop.accessibilityLabel = "footerBackdrop"
    }

    func updateBraveShieldButtonState(animated animated: Bool) {
        guard let s = tabManager.selectedTab?.braveShieldStateSafeAsync.get() else { return }
        let up = s.isNotSet() || !s.isAllOff()
        (urlBar as! BraveURLBarView).setBraveButtonState(shieldsUp: up, animated: animated)
    }

    override func selectedTabChanged(selected: Browser) {
        historySwiper.setup(topLevelView: self.view, webViewContainer: self.webViewContainer)
        for swipe in [historySwiper.goBackSwipe, historySwiper.goForwardSwipe] {
            selected.webView?.scrollView.panGestureRecognizer.requireGestureRecognizerToFail(swipe)
            scrollController.panGesture.requireGestureRecognizerToFail(swipe)
        }

        if let webView = selected.webView {
            webViewContainer.insertSubview(webView, atIndex: 0)
            webView.snp_makeConstraints { make in
                make.top.equalTo(webViewContainerToolbar.snp_bottom)
                make.left.right.bottom.equalTo(self.webViewContainer)
            }

            urlBar.updateProgressBar(Float(webView.estimatedProgress), dueToTabChange: true)
            urlBar.updateReloadStatus(webView.loading)
            updateBraveShieldButtonState(animated: false)

            let bravePanel = getApp().braveTopViewController.rightSidePanel
            bravePanel.setShieldBlockedStats(webView.shieldStats)
            bravePanel.updateSitenameAndTogglesState()
        }
        postAsyncToMain(0.1) {
            self.becomeFirstResponder()
        }
    }

    override func SELtappedTopArea() {
     //   scrollController.showToolbars(animated: true)
    }

    var heightConstraint: Constraint?
    override func setupConstraints() {
        super.setupConstraints()

        // TODO: Should be moved to parent class, but requires property moving too
        webViewContainer.snp_remakeConstraints { make in
            make.left.right.equalTo(self.view)
            heightConstraint = make.height.equalTo(self.view.snp_height).constraint
            webViewContainerTopOffset = make.top.equalTo(self.statusBarOverlay.snp_bottom).offset(BraveURLBarView.CurrentHeight).constraint
        }

    }

    override func updateViewConstraints() {
        super.updateViewConstraints()

        // Setup the bottom toolbar
        toolbar?.snp_remakeConstraints { make in
            make.edges.equalTo(self.footerBackground!)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        webViewContainerTopOffset?.updateOffset(BraveURLBarView.CurrentHeight)
        heightConstraint?.updateOffset(-BraveApp.statusBarHeight())
    }
    
    override func updateToolbarStateForTraitCollection(newCollection: UITraitCollection) {
        super.updateToolbarStateForTraitCollection(newCollection)

        heightConstraint?.updateOffset(-BraveApp.statusBarHeight())

        postAsyncToMain(0) {
            self.urlBar.updateTabsBarShowing()
        }
    }

    override func showHomePanelController(inline inline:Bool) {
        super.showHomePanelController(inline: inline)
        postAsyncToMain(0.1) {
            if UIResponder.currentFirstResponder() == nil {
                self.becomeFirstResponder()
            }
        }
    }

    override func hideHomePanelController() {
        super.hideHomePanelController()

        // For bizzaro reasons, this can take a few delayed attempts. The first responder is getting set to nil -I *did* search the codebase for any resigns that could cause this.
        func setSelfAsFirstResponder(attempt: Int) {
            if UIResponder.currentFirstResponder() === self {
                return
            }
            if attempt > 5 {
                print("Failed to set BVC as first responder ;(")
                return
            }
            postAsyncToMain(0.1) {
                self.becomeFirstResponder()
                setSelfAsFirstResponder(attempt + 1)
            }
        }

        postAsyncToMain(0.1) {
           setSelfAsFirstResponder(0)
        }
    }

    func newTabForDesktopSite(url url: NSURL) {
        let tab = tabManager.addTabForDesktopSite()
        tab.loadRequest(NSURLRequest(URL: url))
    }

    @objc func learnMoreTapped() {
        UIApplication.sharedApplication().openURL(BraveUX.BravePrivacyURL)
    }

    func presentOptInDialog() {
        // Off until TOS is properly set
//        let view = BraveTermsViewController()
//        view.delegate = self
//        presentViewController(view, animated: false) {}
    }
}

extension BraveBrowserViewController: BraveTermsViewControllerDelegate {
    func braveTermsAcceptedTermsAndOptIn() {
        profile.prefs.setInt(1, forKey: BraveUX.PrefKeyUserAllowsTelemetry)
        profile.prefs.setInt(1, forKey: BraveUX.PrefKeyOptInDialogWasSeen)
    }
    
    func braveTermsAcceptedTermsAndOptOut() {
        profile.prefs.setInt(0, forKey: BraveUX.PrefKeyUserAllowsTelemetry)
        profile.prefs.setInt(1, forKey: BraveUX.PrefKeyOptInDialogWasSeen)
    }

    func dismissed() {
        let optedIn = self.profile.prefs.intForKey(BraveUX.PrefKeyUserAllowsTelemetry) ?? 1
        if optedIn != 1 {
            return
        }

        func showHiddenSafariViewController(controller:SFSafariViewController) {
            controller.view.userInteractionEnabled = false
            controller.view.alpha = 0.0
            controller.view.frame = CGRectZero
            self.addChildViewController(controller)
            self.view.addSubview(controller.view)
            controller.didMoveToParentViewController(self)
        }

        func removeHiddenSafariViewController(controller:SFSafariViewController) {
            controller.willMoveToParentViewController(nil)
            controller.view.removeFromSuperview()
            controller.removeFromParentViewController()
        }

        let mixpanelToken = NSBundle.mainBundle().infoDictionary?["MIXPANEL_TOKEN"] ?? "no-token"
        let callbackData = "{'event':'install','properties':{'product':'brave-ios','token':'\(mixpanelToken)','version':'/\(getApp().appVersion)'}}".stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLQueryAllowedCharacterSet()) ?? "no-data"
        let base64Encoded = callbackData.dataUsingEncoding(NSUTF8StringEncoding)?.base64EncodedStringWithOptions(NSDataBase64EncodingOptions(rawValue: 0)) ?? "no-base64"
        let callbackUrl = "https://metric-proxy.brave.com/track?data=" + base64Encoded

        let sf = SFSafariViewController(URL: NSURL(string: callbackUrl)!)
        showHiddenSafariViewController(sf)

        postAsyncToMain(15) {
            removeHiddenSafariViewController(sf)
        }
    }
}

weak var _firstResponder:UIResponder?
extension UIResponder {
    func findFirstResponder() {
        _firstResponder = self
    }

    static func currentFirstResponder() -> UIResponder? {
        if (UIApplication.sharedApplication().sendAction(#selector(findFirstResponder), to: nil, from: nil, forEvent: nil)) {
            return _firstResponder
        } else {
            return nil
        }
    }
}
