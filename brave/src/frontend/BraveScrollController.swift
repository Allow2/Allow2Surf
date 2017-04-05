/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import SnapKit

private let ToolbarBaseAnimationDuration: CGFloat = 0.2

class BraveScrollController: NSObject {
    enum ScrollDirection {
        case Up
        case Down
        case None  // Brave added
    }

    weak var browser: Browser? {
        willSet {
            self.scrollView?.delegate = nil
            self.scrollView?.removeGestureRecognizer(panGesture)
            BraveApp.getCurrentWebView()?.removeGestureRecognizer(tapShowBottomBar)
        }

        didSet {
            BraveApp.getCurrentWebView()?.addGestureRecognizer(tapShowBottomBar)
            self.scrollView?.addGestureRecognizer(panGesture)
            scrollView?.delegate = self
        }
    }

    lazy var tapShowBottomBar: UITapGestureRecognizer = {
        let t = UITapGestureRecognizer(target: self, action: #selector(onTapShowBottomBar))
        t.delegate = self
        return t
    }()

    weak var header: UIView?
    weak var footer: UIView?
    weak var urlBar: URLBarView?
    weak var snackBars: UIView?

    var keyboardIsShowing = false
    var verticalTranslation = CGFloat(0)

    var footerBottomConstraint: Constraint?
    var headerTopConstraint: Constraint?
    var toolbarsShowing: Bool { return headerTopOffset == 0 }

    var edgeSwipingActive = false

    private var headerTopOffset: CGFloat = 0 {
        didSet {
            headerTopConstraint?.updateOffset(headerTopOffset)
            header?.superview?.setNeedsLayout()
        }
    }

    private var footerBottomOffset: CGFloat = 0 {
        didSet {
            footerBottomConstraint?.updateOffset(footerBottomOffset)
            footer?.superview?.setNeedsLayout()
        }
    }

    lazy var panGesture: UIPanGestureRecognizer = {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(BraveScrollController.handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        panGesture.delegate = self
        return panGesture
    }()

    private var scrollView: UIScrollView? { return browser?.webView?.scrollView }
    private var contentOffset: CGPoint { return scrollView?.contentOffset ?? CGPointZero }
    private var contentSize: CGSize { return scrollView?.contentSize ?? CGSizeZero }
    private var scrollViewHeight: CGFloat { return scrollView?.frame.height ?? 0 }
    private var headerFrame: CGRect { return header?.frame ?? CGRectZero }
    private var footerFrame: CGRect { return footer?.frame ?? CGRectZero }
    private var snackBarsFrame: CGRect { return snackBars?.frame ?? CGRectZero }

    private var lastContentOffset: CGFloat = 0
    private var scrollDirection: ScrollDirection = .Down

    // Brave added
    // What I am seeing on older devices is when scroll direction is changed quickly, and the toolbar show/hides,
    // the first or second pan gesture after that will report the wrong direction (the gesture handling seems bugging during janky scrolling)
    // This added check is a secondary validator of the scroll direction
    private var scrollViewWillBeginDragPoint: CGFloat = 0

    func setBottomInset(bottom: CGFloat) {
        scrollView?.contentInset = UIEdgeInsetsMake(0, 0, bottom, 0)
        scrollView?.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, bottom, 0)
    }

    override init() {
        super.init()

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(BraveScrollController.pageUnload), name: kNotificationPageUnload, object: nil)

        NSNotificationCenter.defaultCenter().addObserver(self, selector:#selector(BraveScrollController.keyboardWillAppear(_:)), name: UIKeyboardWillShowNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector:#selector(BraveScrollController.keyboardDidAppear(_:)), name: UIKeyboardDidShowNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector:#selector(BraveScrollController.keyboardWillDisappear(_:)), name: UIKeyboardWillHideNotification, object: nil)
    }

    func keyboardWillAppear(notification: NSNotification){
        keyboardIsShowing = true
    }
    
    func keyboardDidAppear(notification: NSNotification){
        checkHeightOfPageAndAdjustWebViewInsets()
    }

    func keyboardWillDisappear(notification: NSNotification){
        keyboardIsShowing = false

        postAsyncToMain(0.2) {
            // Hiding/showing toolbars during kb show affects layout updating, reset the toolbar state
            self.verticalTranslation = 0
            self.header?.layer.transform = CATransform3DIdentity
            self.footer?.layer.transform = CATransform3DIdentity
            if self.headerTopOffset < 0 {
                self.headerTopOffset = -BraveURLBarView.CurrentHeight
                self.footerBottomOffset = UIConstants.ToolbarHeight
            } else {
                self.headerTopOffset = 0
                self.footerBottomOffset = 0
                self.urlBar?.updateAlphaForSubviews(1.0)
            }
        }
    }

    func pageUnload() {
        postAsyncToMain(0.1) {
            self.showToolbars(animated: true)
        }
    }

    // Struct used to prevent inset adjustment based on runtime scenarios
    struct RuntimeInsetChecks {
        // If inset adjustment code is already being executed
        static var isRunningCheck = false
        
        // Whether webview is currently being zoomed
        // Should not update on zooming (e.g. issue #717)
        static var isZoomingCheck = false
    }
    
    // This causes issue #216 if contentInset changed during a load
    func checkHeightOfPageAndAdjustWebViewInsets() {

        if RuntimeInsetChecks.isZoomingCheck {
            return
        }

        if self.browser?.webView?.loading ?? false {
            if RuntimeInsetChecks.isRunningCheck {
                return
            }
            RuntimeInsetChecks.isRunningCheck = true
            postAsyncToMain(0.2) {
                RuntimeInsetChecks.isRunningCheck = false
                self.checkHeightOfPageAndAdjustWebViewInsets()
            }
        } else {
            RuntimeInsetChecks.isRunningCheck = false

            if !isScrollHeightIsLargeEnoughForScrolling() && !keyboardIsShowing {
                let h = BraveApp.isIPhonePortrait() ? UIConstants.ToolbarHeight + BraveURLBarView.CurrentHeight : BraveURLBarView.CurrentHeight
                setBottomInset(h)
            }
            else {
                // Use offset of header and footer bar positions to determine contentInset and scrollIndicatorInsets
                let top = max((CGRectGetMaxY(header?.frame ?? CGRectZero) - CGRectGetMaxY(UIApplication.sharedApplication().statusBarFrame)), 0)
                let bottom = BraveApp.isIPhonePortrait() ? min((CGRectGetMaxY(UIApplication.sharedApplication().keyWindow?.frame ?? CGRectZero) - CGRectGetMinY(footer?.frame ?? CGRectZero)), 0) : 0
                let oh = BraveApp.isIPhonePortrait() ? (header?.frame.height ?? 0) + (footer?.frame.height ?? 0) : (footer?.frame.height ?? 0)
                let h = keyboardIsShowing ? oh : (top + bottom)
                setBottomInset(h)
            }
        }
    }

    func showToolbars(animated animated: Bool, isShowingDueToBottomTap: Bool = false, completion: ((finished: Bool) -> Void)? = nil) {
        checkHeightOfPageAndAdjustWebViewInsets()

        if verticalTranslation == 0 && headerTopOffset == 0 {
            completion?(finished: true)
            return
        }

        removeTranslationAndSetLayout()

        let durationRatio = abs(headerTopOffset / headerFrame.height)
        let actualDuration = NSTimeInterval(ToolbarBaseAnimationDuration * durationRatio)
        self.animateToolbarsWithOffsets(
            animated: animated,
            duration: actualDuration,
            headerOffset: 0,
            footerOffset: 0,
            alpha: 1,
            isShowingDueToBottomTap: isShowingDueToBottomTap,
            completion: completion)
    }

    var entrantGuard = false
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if entrantGuard {
            return
        }
        entrantGuard = true
        defer {
            entrantGuard = false
        }
        if (keyPath ?? "") == "contentSize" && browser?.webView?.scrollView === object {
            browser?.webView?.contentSizeChangeDetected()
            checkHeightOfPageAndAdjustWebViewInsets()
            if !isScrollHeightIsLargeEnoughForScrolling() && !toolbarsShowing {
                showToolbars(animated: true, completion: nil)
            }
        }
    }

    //// bottom tap //////
    func onTapShowBottomBar(gesture: UITapGestureRecognizer) {
        if toolbarsShowing || !BraveApp.isIPhonePortrait() {
            return
        }

        guard let height = gesture.view?.frame.height else { return }
        if gesture.locationInView(gesture.view).y > height - UIConstants.ToolbarHeight {
            showToolbars(animated: true, isShowingDueToBottomTap: true)
        }
    }
}

private extension BraveScrollController {
    func browserIsLoading() -> Bool {
        return browser?.loading ?? true
    }

    @objc func handlePan(gesture: UIPanGestureRecognizer) {
        if browserIsLoading() || edgeSwipingActive {
            return
        }

        guard let containerView = scrollView?.superview else { return }

        let translation = gesture.translationInView(containerView)
        let delta = lastContentOffset - translation.y

        if delta > 0 && contentOffset.y - scrollViewWillBeginDragPoint >= 1.0 {
            scrollDirection = .Down
        } else if delta < 0 && scrollViewWillBeginDragPoint - contentOffset.y >= 1.0 {
            scrollDirection = .Up
        }

        lastContentOffset = translation.y
        if isScrollHeightIsLargeEnoughForScrolling() {
            scrollToolbarsWithDelta(delta)
        }

        if gesture.state == .Ended || gesture.state == .Cancelled {
            lastContentOffset = 0
        }
        
        checkHeightOfPageAndAdjustWebViewInsets()
    }

    func scrollToolbarsWithDelta(delta: CGFloat) {
        if scrollViewHeight >= contentSize.height {
            return
        }

        if snackBars?.frame.size.height > 0 {
            return
        }

        if refreshControl?.hidden == false {
            return
        }

        let updatedOffset = toolbarsShowing ? clamp(verticalTranslation - delta, min: -BraveURLBarView.CurrentHeight, max: 0) :
            clamp(verticalTranslation - delta, min: 0, max: BraveURLBarView.CurrentHeight)

        verticalTranslation = updatedOffset

        if (fabs(updatedOffset) > 0 && fabs(updatedOffset) < BraveURLBarView.CurrentHeight) {
            // this stops parallax effect where the scrolling rate is doubled while hiding/showing toolbars
            scrollView?.contentOffset = CGPoint(x: contentOffset.x, y: contentOffset.y - delta)
        }

        header?.layer.transform = CATransform3DMakeAffineTransform(CGAffineTransformMakeTranslation(0, verticalTranslation))

        let footerTranslation = verticalTranslation > UIConstants.ToolbarHeight ? -UIConstants.ToolbarHeight : -verticalTranslation
        footer?.layer.transform = CATransform3DMakeAffineTransform(CGAffineTransformMakeTranslation(0, footerTranslation))

        let webViewVertTranslation = toolbarsShowing ? verticalTranslation : verticalTranslation - BraveURLBarView.CurrentHeight
        let webView = getApp().browserViewController.webViewContainer
        webView.layer.transform = CATransform3DMakeAffineTransform(CGAffineTransformMakeTranslation(0, webViewVertTranslation))

        var alpha = 1 - abs(verticalTranslation / UIConstants.ToolbarHeight)
        if (!toolbarsShowing) {
            alpha = 1 - alpha
        }
        urlBar?.updateAlphaForSubviews(alpha)
    }

    func clamp(y: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        if y >= max {
            return max
        } else if y <= min {
            return min
        }
        return y
    }

    // Currently only has handling for the show toolbars case.
    private func animateToolbarsWithOffsets(animated animated: Bool, duration: NSTimeInterval, headerOffset: CGFloat,
                                                     footerOffset: CGFloat, alpha: CGFloat, isShowingDueToBottomTap: Bool, completion: ((finished: Bool) -> Void)?) {

        let animation: () -> Void = {
            self.headerTopOffset = headerOffset
            self.footerBottomOffset = footerOffset
            self.urlBar?.updateAlphaForSubviews(alpha)
            self.header?.layoutIfNeeded()
            self.footer?.layoutIfNeeded()

            // TODO this code is only being used to show toolbars, so right now hard-code for that case, obviously if/when hide is added, update the code to support that
            let webView = getApp().browserViewController.webViewContainer
            webView.layer.transform = CATransform3DIdentity

            if isShowingDueToBottomTap { // scroll up to show page under the bottom toolbar
                self.scrollView?.contentOffset.y += 2 * BraveURLBarView.CurrentHeight
            } else if self.contentOffset.y > BraveURLBarView.CurrentHeight {
                // keep the web view in the same scroll position by scrolling up the toolbar height 
                self.scrollView?.contentOffset.y += BraveURLBarView.CurrentHeight
            }
        }

        // Reset the scroll direction now that it is handled
        scrollDirection = .None

        let completionWrapper: Bool -> Void = { finished in
            completion?(finished: finished)
        }

        if animated {
            UIView.animateWithDuration(0.350, delay:0.0, options: .AllowUserInteraction, animations: animation, completion: completionWrapper)
        } else {
            animation()
            completion?(finished: true)
        }
    }

    func isScrollHeightIsLargeEnoughForScrolling() -> Bool {
        return (UIScreen.mainScreen().bounds.size.height + 2 * UIConstants.ToolbarHeight) < scrollView?.contentSize.height
    }
}

extension BraveScrollController: UIGestureRecognizerDelegate {
    func gestureRecognizer(gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWithGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

func blockOtherGestures(isBlocked: Bool, views: [UIView]) {
    for view in views {
        if let gestures = view.gestureRecognizers as [UIGestureRecognizer]! {
            for gesture in gestures {
                gesture.enabled = !isBlocked
            }
        }
    }
}

var refreshControl:ODRefreshControl?
// stop refresh interaction while animating
var isInRefreshQuietPeriod:Bool = false
// only allow refresh when scrolling with finger down, not from a momentum scrll
var isRefreshBlockedDueToMomentumScroll = false

extension BraveScrollController: UIScrollViewDelegate {
    func scrollViewDidScroll(scrollView: UIScrollView) {
        guard let webView = browser?.webView else { return }
        if (webViewIsZoomed(webView)) {
            return;
        }

        let position = -webView.convertPoint(webView.frame.origin, fromView: nil).y
        if contentOffset.y < 0 && !isInRefreshQuietPeriod && !isRefreshBlockedDueToMomentumScroll && verticalTranslation == 0 && toolbarsShowing {
            if refreshControl == nil {
                refreshControl = ODRefreshControl(inScrollView: getApp().rootViewController.view)
            }
            refreshControl?.backgroundColor = UIColor.clearColor()
            refreshControl?.tintColor = BraveUX.BraveOrange
            refreshControl?.hidden = false
            refreshControl?.frame = CGRectMake(0, position, refreshControl?.frame.size.width ?? 0, -contentOffset.y)

            var pullToReloadDistance = CGFloat(-BraveUX.PullToReloadDistance)
            if BraveApp.isIPhoneLandscape() {
                // The "spring" is tighter in this case, make the distance shorter
                pullToReloadDistance *= CGFloat(0.80)
            }

            if contentOffset.y < pullToReloadDistance && !keyboardIsShowing {
                isInRefreshQuietPeriod = true

                let currentOffset =  scrollView.contentOffset.y
                blockOtherGestures(true, views: scrollView.subviews)
                blockOtherGestures(true, views: [scrollView])
                scrollView.contentOffset.y = currentOffset
                refreshControl?.beginRefreshing()
                browser?.webView?.reloadFromOrigin()
                UIView.animateWithDuration(0.5, animations: { refreshControl?.backgroundColor = UIColor.clearColor() })
                UIView.animateWithDuration(0.5, delay: 0.2, options: .AllowAnimatedContent, animations: {
                    scrollView.contentOffset.y = 0
                    refreshControl?.frame = CGRectMake(0, position, refreshControl?.frame.size.width ?? 0, 0)
                    }, completion: {
                        finished in
                        blockOtherGestures(false, views: scrollView.subviews)
                        blockOtherGestures(false, views: [scrollView])
                        isInRefreshQuietPeriod = false
                        refreshControl?.endRefreshing()
                        refreshControl?.hidden = true
                        refreshControl?.backgroundColor = UIColor.blackColor()
                })
            }
        } else if refreshControl?.hidden == false {
            refreshControl?.frame = CGRectMake(0, position, refreshControl?.frame.size.width ?? 0, -contentOffset.y)
        }

        if contentOffset.y >= 0 && refreshControl?.hidden == false && !isInRefreshQuietPeriod {
            refreshControl?.hidden = true
        }
    }

    func scrollViewDidEndDragging(scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if browserIsLoading() {
            return
        }

        if (!decelerate) {
            removeTranslationAndSetLayout()
        } else {
            isRefreshBlockedDueToMomentumScroll = true
        }
    }

    func removeTranslationAndSetLayout() {
        if verticalTranslation == 0 {
            return
        }

        if verticalTranslation < 0 && headerTopOffset == 0 {
            headerTopOffset = -BraveURLBarView.CurrentHeight
            footerBottomOffset = UIConstants.ToolbarHeight
            urlBar?.updateAlphaForSubviews(0)
        } else if verticalTranslation > UIConstants.ToolbarHeight / 2.0 && headerTopOffset != 0 {
            headerTopOffset = 0
            footerBottomOffset = 0
            urlBar?.updateAlphaForSubviews(1.0)
        }

        verticalTranslation = 0
        header?.layer.transform = CATransform3DIdentity
        footer?.layer.transform = CATransform3DIdentity
    }

    func scrollViewWillBeginZooming(scrollView: UIScrollView, withView view: UIView?) {
        // freeze
        RuntimeInsetChecks.isZoomingCheck = true
    }
    
    func scrollViewDidEndZooming(scrollView: UIScrollView, withView view: UIView?, atScale scale: CGFloat) {
        // unfreeze
        RuntimeInsetChecks.isZoomingCheck = false
    }
    
    func scrollViewWillBeginDragging(scrollView: UIScrollView) {
        self.scrollViewWillBeginDragPoint = scrollView.contentOffset.y
    }
    
    func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
        self.removeTranslationAndSetLayout()
        isRefreshBlockedDueToMomentumScroll = false
    }
    
    func scrollViewShouldScrollToTop(scrollView: UIScrollView) -> Bool {
        showToolbars(animated: true)
        return true
    }
}
