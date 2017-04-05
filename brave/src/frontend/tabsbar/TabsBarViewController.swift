/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */
import UIKit
import SnapKit

enum TabsBarShowPolicy : Int {
    case Never
    case Always
    case LandscapeOnly
}

let kPrefKeyTabsBarShowPolicy = "kPrefKeyTabsBarShowPolicy"
let kPrefKeyTabsBarOnDefaultValue = UIDevice.currentDevice().userInterfaceIdiom == .Pad ? TabsBarShowPolicy.Always : TabsBarShowPolicy.LandscapeOnly

let minTabWidth =  UIDevice.currentDevice().userInterfaceIdiom == .Pad ? CGFloat(180) : CGFloat(160)
let tabHeight = TabsBarHeight - 1

class TabsBarViewController: UIViewController {
    var scrollView: UIScrollView!

    var tabs = [TabWidget]()
    var spacerLeftmost = UIView() // Hiddens space on the left used during drag-and-drop
    var plusButton = UIButton()

    var leftOverflowIndicator : CAGradientLayer = CAGradientLayer()
    var rightOverflowIndicator : CAGradientLayer = CAGradientLayer()

    var isVisible:Bool {
        return self.view.alpha > 0
    }

    private var isAddTabAnimationRunning = false
    
    init() {
        super.init(nibName: nil, bundle: nil)

        self.view = UIView(frame: CGRectZero)
        scrollView = UIScrollView(frame: CGRectZero)
        scrollView.bounces = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
        view.addSubview(scrollView)

        scrollView.snp_makeConstraints { (make) in
            make.bottom.top.left.equalTo(view)
            make.right.equalTo(view).inset(BraveUX.TabsBarPlusButtonWidth)
        }

        if UIDevice.currentDevice().userInterfaceIdiom == .Pad {
            plusButton.setImage(UIImage(named: "add")!.imageWithRenderingMode(.AlwaysTemplate), forState: .Normal)
            plusButton.imageEdgeInsets = UIEdgeInsetsMake(6, 6, 6, 10)
            plusButton.tintColor = UIColor.blackColor()
            plusButton.contentMode = .ScaleAspectFit
            plusButton.addTarget(self, action: #selector(addTabPressed), forControlEvents: .TouchUpInside)
            view.addSubview(plusButton)

            plusButton.snp_makeConstraints { (make) in
                make.right.top.bottom.equalTo(view)
                make.width.equalTo(BraveUX.TabsBarPlusButtonWidth)
            }

            let vertLine = UIView()
            vertLine.backgroundColor = UIColor.blackColor()
            plusButton.addSubview(vertLine)
            vertLine.snp_makeConstraints { (make) in
                make.left.equalTo(plusButton)
                make.width.equalTo(1)
                make.height.equalTo(22)
                make.centerY.equalTo(plusButton.snp_centerY)
            }

        }

        getApp().tabManager.addDelegate(self)

        scrollView.addSubview(spacerLeftmost)
        spacerLeftmost.snp_makeConstraints { (make) in
            make.top.left.equalTo(scrollView)
            make.height.equalTo(tabHeight)
            make.width.equalTo(0)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLayoutSubviews() {
        postAsyncToMain(0.1) { // to ensure view.bounds is updated
            self.updateContentSize(self.tabs.count)
        }
    }

    func addTabPressed() {
        getApp().tabManager.addTabAndSelect()
    }

    func tabOverflowWidth(tabCount: Int) -> CGFloat {
        let overflow = CGFloat(tabCount) * minTabWidth - scrollView.frame.width
        return overflow > 0 ? overflow : 0
    }

    func updateTabWidthConstraint(width width: CGFloat) {
        tabs.forEach {
            $0.widthConstraint?.updateOffset(width)
        }

        self.tabs.forEach {
            if width > 0 {
                $0.reinstallConstraints()
            }
        }
    }

    func updateContentSize(tabCount: Int) {
        struct staticWidth { static var val = CGFloat(0) }
        if abs(staticWidth.val - scrollView.bounds.width) > 10 {
            let w = calcTabWidth(tabs.count)
            updateTabWidthConstraint(width: w)
            overflowIndicators()
        }
        staticWidth.val = scrollView.bounds.width
        scrollView.contentSize = CGSizeMake(scrollView.bounds.width + tabOverflowWidth(tabCount), scrollView.bounds.height)
    }

    func overflowIndicators() {
        if tabOverflowWidth(tabs.count) < 1 {
            leftOverflowIndicator.opacity = 0
            rightOverflowIndicator.opacity = 0
            return
        }

        let offset = Float(scrollView.contentOffset.x)
        let startFade = Float(30)
        if offset < startFade {
            leftOverflowIndicator.opacity = offset / startFade
        } else {
            leftOverflowIndicator.opacity = 1

        }

        // all the way scrolled right
        let offsetFromRight = scrollView.contentSize.width - CGFloat(offset) - scrollView.frame.width
        if offsetFromRight < CGFloat(startFade) {
            rightOverflowIndicator.opacity = Float(offsetFromRight) / startFade
        } else {
            rightOverflowIndicator.opacity = 1
        }
    }

    override func viewDidAppear(animated: Bool) {
        addLeftRightScrollHint(isRightSide: false, maskLayer: leftOverflowIndicator)
        addLeftRightScrollHint(isRightSide: true, maskLayer: rightOverflowIndicator)

        if tabs.count < 1 {
            return
        }

        recalculateTabView()
    }
    
    func calcTabWidth(tabCount: Int) -> CGFloat {
        func calc() -> CGFloat {
            if tabCount < 2 {
                return scrollView.frame.width
            }
            var w = scrollView.frame.width / (CGFloat(tabCount))
            if w < minTabWidth {
                w = minTabWidth
            }
            return w
        }
        let c = calc()
        return c > 0 ? c : UIScreen.mainScreen().bounds.width
    }
    
    func recalculateTabView() {
        let w = calcTabWidth(tabs.count)
        updateTabWidthConstraint(width: w)

        updateContentSize(tabs.count)
        overflowIndicators()
        
        scrollView.layoutIfNeeded()
    }


    func addTab(browser browser: Browser) -> TabWidget {
    
        let t = TabWidget(browser: browser, parentScrollView: scrollView)
        t.delegate = self
        
        if self.isVisible {
            isAddTabAnimationRunning = true
            t.alpha = 0
            t.widthConstraint?.updateOffset(0)
        }
        
        scrollView.addSubview(t)
        
        let w = calcTabWidth(tabs.count)
        
        t.remakeLayout(prev: tabs.last?.spacerRight != nil ? tabs.last!.spacerRight : self.spacerLeftmost, width: w, scrollView: scrollView)
        
        tabs.append(t)

        if self.isVisible {
            UIView.animateWithDuration(0.2, animations: {
                self.recalculateTabView()
                let w = self.calcTabWidth(self.tabs.count)
                let overflow =  w * CGFloat(self.tabs.count) - self.scrollView.frame.size.width
                if overflow > 0 {
                    self.scrollView.contentOffset = CGPoint(x: overflow, y: 0)
                }
            }) { _ in
                UIView.animateWithDuration(0.1) {
                    t.alpha = 1
                    self.isAddTabAnimationRunning = false
                }
            }
        } else {
            recalculateTabView()
        }

        return t
    }

    func neighborSpacer(i: Int) -> UIView? {
        if i < 0 {
            return self.spacerLeftmost
        }
        return 0 ..< self.tabs.count ~= i ? self.tabs[i].spacerRight : nil
    }

    func neighborTab(i: Int) -> TabWidget? {
        return 0 ..< self.tabs.count ~= i ? self.tabs[i] : nil
    }

    func removeTab(tab: TabWidget) {
        
        guard let index = tabs.indexOf(tab) else {
            print("ERROR tab \(tab) not matched in tab list \(self.tabs)")
            return
        }
        
        func _removeTab(tab: TabWidget, atIndex index: Int) {

            let prev = self.neighborSpacer(index - 1)
            let next = self.neighborTab(index + 1)
            
            tab.spacerRight.removeFromSuperview()
            tab.removeFromSuperview()
            next?.snp_makeConstraints(closure: { (make) in
                if let prev = prev {
                    make.left.equalTo(prev.snp_right)
                }
            })
            self.tabs.removeAtIndex(index)
            self.recalculateTabView()
        }
        
        assert(index < self.tabs.count)
        
        if !self.isVisible {
            _removeTab(tab, atIndex: index)
        }
        else {
            UIView.animateWithDuration(0.2, animations: {
                _removeTab(tab, atIndex: index)
            })
        }
    }

    func addLeftRightScrollHint(isRightSide isRightSide: Bool, maskLayer: CAGradientLayer) {
        maskLayer.removeFromSuperlayer()
        let colors = [UIColor(white: 80/255, alpha: 0).CGColor, UIColor(white:66/255, alpha: 1.0).CGColor]
        let locations = [0.9, 1.0]
        maskLayer.startPoint = CGPoint(x: isRightSide ? 0 : 1.0, y: 0.5)
        maskLayer.endPoint = CGPoint(x: isRightSide ? 1.0 : 0, y: 0.5)
        maskLayer.opacity = 0
        maskLayer.colors = colors;
        maskLayer.locations = locations;
        maskLayer.bounds = CGRectMake(0, 0, scrollView.frame.width, tabHeight)
        maskLayer.anchorPoint = CGPointZero;
        // you must add the mask to the root view, not the scrollView, otherwise the masks will move as the user scrolls!
        view.layer.addSublayer(maskLayer)
    }

    func updateSeparatorLineBetweenTabs() {
        for (index, tab) in tabs.enumerate() {
            if index == 0 || tab.isSelectedStyle() {
                tab.separatorLine.hidden = true
            } else if index - 1 > -1 && tabs[index - 1].isSelectedStyle() {
                tab.separatorLine.hidden = true
            } else {
                tab.separatorLine.hidden = false
            }
        }
    }
}

extension TabsBarViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(scrollView: UIScrollView) {
        overflowIndicators()
    }
}

extension TabsBarViewController: TabWidgetDelegate {
    func tabWidgetClose(tab: TabWidget) {
        if let b = tab.browser {
            getApp().tabManager.removeTab(b, createTabIfNoneLeft: true)
        }
    }

    func tabWidgetSelected(tab: TabWidget) {
        tabs.forEach {
            $0.deselect()
        }
        tab.setStyleToSelected()

        if getApp().tabManager.selectedTab !== tab.browser {
            getApp().tabManager.selectTab(tab.browser)
        }

        if !isAddTabAnimationRunning {
            postAsyncToMain(0.1) { // allow time for any layout code to complete
                let left = CGRectMake(tab.frame.minX, 1, 1, 1)
                let right = CGRectMake(tab.frame.maxX - 1, 1, 1, 1)
                self.scrollView.scrollRectToVisible(left, animated: true)
                self.scrollView.scrollRectToVisible(right, animated: true)
            }
        }
    }
}

extension TabsBarViewController: TabManagerDelegate {
    func tabManagerDidEnterPrivateBrowsingMode(tabManager: TabManager) {
        assert(NSThread.currentThread().isMainThread)
        tabs.forEach{ $0.removeFromSuperview() }
        tabs.removeAll()
    }

    func tabManagerDidExitPrivateBrowsingMode(tabManager: TabManager) {
        assert(NSThread.currentThread().isMainThread)
        tabs.forEach{ $0.removeFromSuperview() }
        tabs.removeAll()

        tabManager.tabs.internalTabList.forEach {
            let t = addTab(browser: $0)
            t.setTitle($0.lastTitle)
            if tabManager.selectedTab === $0 {
                tabWidgetSelected(t)
            }
        }
    }

    func tabManager(tabManager: TabManager, didSelectedTabChange selected: Browser?) {
        assert(NSThread.currentThread().isMainThread)
        tabs.forEach { tabWidget in
            if tabWidget.browser === selected {
                tabWidgetSelected(tabWidget)
            }
        }

        updateSeparatorLineBetweenTabs()
    }

    func tabManager(tabManager: TabManager, didCreateWebView tab: Browser, url: NSURL?) {
        if let t = tabs.find({ $0.browser === tab }) {
            if let wv = t.browser?.webView {
                wv.delegatesForPageState.append(BraveWebView.Weak_WebPageStateDelegate(value: t))
            }
            return
        }

        let t = addTab(browser: tab)
        if let url = url {
            let title = url.baseDomain()
            t.setTitle(title)
        }

        getApp().browserViewController.urlBar.updateTabsBarShowing()
    }

    func tabManager(tabManager: TabManager, didAddTab tab: Browser) {}

    func tabManager(tabManager: TabManager, didRemoveTab tab: Browser) {
        assert(NSThread.currentThread().isMainThread)
        tabs.forEach { tabWidget in
            if tabWidget.browser === tab {
                removeTab(tabWidget)
            }
        }

        updateSeparatorLineBetweenTabs()

        getApp().browserViewController.urlBar.updateTabsBarShowing()
    }

    func tabManagerDidRestoreTabs(tabManager: TabManager) {
        postAsyncToMain(0.5) { [weak self] in
            self?.tabs.forEach {
                $0.updateTitle_throttled()
            }
            getApp().browserViewController.urlBar.updateTabsBarShowing()
        }
    }

    func tabManagerDidAddTabs(tabManager: TabManager) {}
}
// MARK: Drag and drop support

var tabXPositions: [CGFloat]?
var lastHitSpacerDuringDrag: UIView? // the spacer the tab is dragged over

extension TabsBarViewController {
    func moveTab(tab: TabWidget, index: Int) {
        guard let oldIndex = tabs.indexOf(tab) else { return }

        tabs.removeAtIndex(oldIndex)
        tabs.insert(tab, atIndex: index)

        let w = calcTabWidth(tabs.count)

        var prev = spacerLeftmost
        for t in tabs {
            t.alpha = 1
            if let dragClone = t.dragClone {
                dragClone.alpha = 0
                dragClone.removeFromSuperview()
                t.dragClone = nil
            }
            t.remakeLayout(prev: prev, width: w, scrollView: scrollView)
            prev = t.spacerRight
        }
    }


    func modifyWidth(view: UIView?, width: CGFloat) {
        if let tab = view as? TabWidget {
            if width < 1 {
                tab.breakConstraintsForShrinking()
            }
        }
        UIView.animateWithDuration(0.5, animations: {
            view?.snp_updateConstraints{ (make) in
                make.width.equalTo(width)
            }
            self.view.layoutIfNeeded()
        }, completion : { _ in
            if let tab = view as? TabWidget {
                if width > 0 {
                    tab.reinstallConstraints()
                }
            }})

    }

    func newIndexOfMovedTab(indexOfMovedTab indexOfMovedTab: Int, dragDistance: CGFloat) -> Int {
        var newIndex = -1
        guard let tabXPositions = tabXPositions else { assert(false); return 0 }
        assert(0 ..< tabXPositions.count ~= indexOfMovedTab)
        let moveTabPos = tabXPositions[indexOfMovedTab]
        let tabWidth = calcTabWidth(tabs.count)
        for (i, x) in tabXPositions.enumerate() {
            if i == indexOfMovedTab {
                continue
            }
            let newX = moveTabPos + dragDistance
            if dragDistance > 0 && x > moveTabPos {
                if newX > x - tabWidth * 0.5 + 10 {
                    newIndex = i
                }
            } else if dragDistance < 0 && x < moveTabPos {
                if newX < x + tabWidth * 0.5 - 10 {
                    newIndex = i
                    break
                }
            }
        }
        return newIndex
    }

    func handleDraggingEnded(tab: TabWidget, dragDistance: CGFloat) {
        if tabXPositions == nil {
            tab.alpha = 1.0
            return
        }

        guard let movedIndex = tabs.indexOf(tab) else { print("ERROR"); return }
        let newIndex = newIndexOfMovedTab(indexOfMovedTab: movedIndex, dragDistance: dragDistance)

        let moveCloneTo = newIndex < 0 ? tab.dragClone?.lastLocation : CGPoint(x: tabXPositions![newIndex], y: tab.center.y)

        if let clone = tab.dragClone where clone.lastLocation != nil {
            UIView.animateWithDuration(0.2, animations: {
                tab.dragClone?.alpha = 1.0
                if let p = moveCloneTo {
                    tab.dragClone?.center = p
                }
                }, completion: {_ in
                    if newIndex > -1 {
                        self.spacerLeftmost.snp_updateConstraints { (make) in
                            make.width.equalTo(0)
                        }
                        self.moveTab(tab, index: newIndex)
                    }
                    tab.alpha = 1.0
                    postAsyncToMain(0.5) {
                        tab.dragClone?.removeFromSuperview()
                        tab.dragClone = nil
                    }
            })
        }

        lastHitSpacerDuringDrag = nil
        scrollView.scrollEnabled = true
        tabXPositions = nil

        // Returning to original spot, set widths back (animated)
        if newIndex < 0 {
            modifyWidth(tab, width:self.calcTabWidth(self.tabs.count))
            modifyWidth(spacerLeftmost, width: 0)
            for t in tabs {
                modifyWidth(t.spacerRight, width: 0)
            }
        }

        postAsyncToMain(0.3) {
            tab.reinstallConstraints()
            self.updateSeparatorLineBetweenTabs()
        }
        // Ensure tab is re-shown
        postAsyncToMain(0.5) {
            tab.alpha = 1
            tab.superview!.bringSubviewToFront(tab)
        }
    }

    func tabWidgetDragStarted(tab: TabWidget) {
        scrollView.scrollEnabled = false
    }

    func tabWidgetDragMoved(tab: TabWidget, distance: CGFloat, isEnding: Bool) {
        let tabWidth = calcTabWidth(tabs.count)

        guard let movedIndex = tabs.indexOf(tab) else { print("ERROR"); return }

        if isEnding {
            handleDraggingEnded(tab, dragDistance: distance)
            return
        }

        if tabXPositions == nil {
            tabXPositions = tabs.map { $0.center.x }
            lastHitSpacerDuringDrag = tab.spacerRight
        }

        if abs(distance) < 1 {
            return
        }
        //let newPoint = CGPointMake(, tab.center.y)

        var hitSpacer: UIView? = tab.spacerRight
        let newIndex = newIndexOfMovedTab(indexOfMovedTab: movedIndex, dragDistance: distance)

        if newIndex < 0 {
            hitSpacer = tab.spacerRight
        } else {
            if distance > 0 {
                hitSpacer = neighborSpacer(newIndex)
            } else {
                if newIndex > 0 {
                    hitSpacer = neighborSpacer(newIndex - 1)
                } else {
                    hitSpacer = spacerLeftmost
                }
            }
        }

        let isChanged = lastHitSpacerDuringDrag !== hitSpacer
        lastHitSpacerDuringDrag = hitSpacer
        if !isChanged {
            return
        }

        for t in tabs {
            if t.spacerRight !== hitSpacer {
                modifyWidth(t.spacerRight, width: 0)
            }
        }

        if hitSpacer != spacerLeftmost {
            modifyWidth(spacerLeftmost, width: 0)
        }
        
        modifyWidth(tab.spacerRight, width: hitSpacer !== tab.spacerRight ? 0 : tabWidth)
        modifyWidth(tab, width: 0)
        modifyWidth(hitSpacer, width: tabWidth)
    }

    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)

        leftOverflowIndicator.opacity = 0
        rightOverflowIndicator.opacity = 0
        postAsyncToMain(0.1) {
            self.addLeftRightScrollHint(isRightSide: false, maskLayer: self.leftOverflowIndicator)
            self.addLeftRightScrollHint(isRightSide: true, maskLayer: self.rightOverflowIndicator)
            self.overflowIndicators()
        }
    }


}



