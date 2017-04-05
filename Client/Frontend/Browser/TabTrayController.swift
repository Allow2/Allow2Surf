/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import SnapKit
import Storage
import ReadingList
import Shared

struct TabTrayControllerUX {
    static let CornerRadius = BraveUX.TabTrayCellCornerRadius
    static let BackgroundColor = UIConstants.AppBackgroundColor
    static let CellBackgroundColor = UIColor(red:1.0, green:1.0, blue:1.0, alpha:1)
    static let TitleBoxHeight = CGFloat(32.0)
    static let Margin = CGFloat(15)
    static let ToolbarBarTintColor = UIConstants.AppBackgroundColor
    static let ToolbarButtonOffset = CGFloat(10.0)
    static let CloseButtonMargin = CGFloat(4.0)
    static let CloseButtonEdgeInset = CGFloat(6)

    static let NumberOfColumnsThin = 1
    static let NumberOfColumnsWide = 3
    static let CompactNumberOfColumnsThin = 2
}

struct LightTabCellUX {
    static let TabTitleTextColor = UIColor.blackColor()
}

struct DarkTabCellUX {
    static let TabTitleTextColor = UIColor.whiteColor()
}

protocol TabCellDelegate: class {
    func tabCellDidClose(cell: TabCell)
}

class TabCell: UICollectionViewCell {

    static let Identifier = "TabCellIdentifier"

    let shadowView = UIView()
    let backgroundHolder = UIView()
    let background = UIImageViewAligned()
    let titleLbl: UILabel
    let favicon: UIImageView = UIImageView()
    let titleWrapperBackground = UIView()
    let closeButton: UIButton

    var titleWrapper: UIView = UIView()
    var animator: SwipeAnimator!

    weak var delegate: TabCellDelegate?

    // Changes depending on whether we're full-screen or not.
    var margin = CGFloat(0)

    override init(frame: CGRect) {
        self.shadowView.layer.cornerRadius = TabTrayControllerUX.CornerRadius
        self.shadowView.layer.masksToBounds = false
        
        self.backgroundHolder.backgroundColor = TabTrayControllerUX.CellBackgroundColor
        self.backgroundHolder.layer.cornerRadius = TabTrayControllerUX.CornerRadius
        self.backgroundHolder.layer.borderColor = UIColor(white: 0.0, alpha: 0.15).CGColor
        self.backgroundHolder.layer.borderWidth = 0.5
        self.backgroundHolder.layer.masksToBounds = true

        self.background.contentMode = UIViewContentMode.ScaleAspectFill
        self.background.userInteractionEnabled = false
        self.background.layer.masksToBounds = true
        self.background.alignLeft = true
        self.background.alignTop = true

        self.favicon.layer.cornerRadius = 2.0
        self.favicon.layer.masksToBounds = true

        self.titleLbl = UILabel()
        self.titleLbl.backgroundColor = .clearColor()
        self.titleLbl.textAlignment = NSTextAlignment.Left
        self.titleLbl.userInteractionEnabled = false
        self.titleLbl.numberOfLines = 1
        self.titleLbl.font = DynamicFontHelper.defaultHelper.DefaultSmallFontBold

        self.closeButton = UIButton()
        self.closeButton.setImage(UIImage(named: "stop"), forState: UIControlState.Normal)
        self.closeButton.tintColor = .blackColor()
        
        self.titleWrapperBackground.backgroundColor = UIColor.whiteColor()

        self.titleWrapper.backgroundColor = .clearColor()
        
        self.titleWrapper.addSubview(self.titleWrapperBackground)
        self.titleWrapper.addSubview(self.closeButton)
        self.titleWrapper.addSubview(self.titleLbl)
        self.titleWrapper.addSubview(self.favicon)

        super.init(frame: frame)

        self.closeButton.addTarget(self, action: #selector(TabCell.SELclose), forControlEvents: UIControlEvents.TouchUpInside)
        self.contentView.clipsToBounds = false
        self.clipsToBounds = false
        
        self.animator = SwipeAnimator(animatingView: self.shadowView, container: self)

        shadowView.addSubview(backgroundHolder)
        backgroundHolder.addSubview(self.background)
        backgroundHolder.addSubview(self.titleWrapper)
        contentView.addSubview(shadowView)
        
        setupConstraints()

        self.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: Strings.Close, target: self.animator, selector: #selector(SELclose))
        ]
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupConstraints() {
        
        let generalOffset = 4
        
        shadowView.snp_remakeConstraints { make in
            make.edges.equalTo(shadowView.superview!)
        }
        
        backgroundHolder.snp_remakeConstraints { make in
            make.edges.equalTo(backgroundHolder.superview!)
        }

        background.snp_remakeConstraints { make in
            make.edges.equalTo(background.superview!)
        }

        favicon.snp_remakeConstraints { make in
            make.top.left.equalTo(favicon.superview!).offset(generalOffset)
            make.size.equalTo(titleWrapper.snp_height).offset(-generalOffset * 2)
        }

        titleWrapper.snp_remakeConstraints { make in
            make.left.top.equalTo(titleWrapper.superview!)
            make.width.equalTo(titleWrapper.superview!.snp_width)
            make.height.equalTo(TabTrayControllerUX.TitleBoxHeight)
        }
        
        titleWrapperBackground.snp_remakeConstraints { make in
            make.top.left.right.equalTo(titleWrapperBackground.superview!)
            make.height.equalTo(TabTrayControllerUX.TitleBoxHeight + 15)
        }

        titleLbl.snp_remakeConstraints { make in
            make.left.equalTo(favicon.snp_right).offset(generalOffset)
            make.right.equalTo(closeButton.snp_left).offset(generalOffset)
            make.top.bottom.equalTo(titleLbl.superview!)
        }

        closeButton.snp_remakeConstraints { make in
            make.size.equalTo(titleWrapper.snp_height)
            make.centerY.equalTo(titleWrapper)
            make.right.equalTo(closeButton.superview!)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Frames do not seem to update until next runloop cycle
        dispatch_async(dispatch_get_main_queue()) {
            let gradientLayer = CAGradientLayer()
            gradientLayer.frame = self.titleWrapperBackground.bounds
            gradientLayer.colors = [UIColor(white: 1.0, alpha: 0.98).CGColor, UIColor(white: 1.0, alpha: 0.9).CGColor, UIColor.clearColor().CGColor]
            self.titleWrapperBackground.layer.mask = gradientLayer
        }
    }
    
    override func prepareForReuse() {
        // TODO: Move more of this to cellForItem
        // Reset any close animations.
        backgroundHolder.layer.borderColor = UIColor(white: 0.0, alpha: 0.15).CGColor
        backgroundHolder.layer.borderWidth = 0.5
        shadowView.alpha = 1
        shadowView.transform = CGAffineTransformIdentity
        shadowView.layer.shadowOpacity = 0
        self.titleLbl.font = DynamicFontHelper.defaultHelper.DefaultSmallFontBold
    }

    override func accessibilityScroll(direction: UIAccessibilityScrollDirection) -> Bool {
        animator.close(right: direction == .Right)
        return true
    }

    @objc
    func SELclose() {
        self.animator.SELcloseWithoutGesture()
    }
}

struct PrivateModeStrings {
    static let toggleAccessibilityLabel = Strings.Private_Mode
    static let toggleAccessibilityHint = Strings.Turns_private_mode_on_or_off
    static let toggleAccessibilityValueOn = Strings.On
    static let toggleAccessibilityValueOff = Strings.Off
}

protocol TabTrayDelegate: class {
    func tabTrayDidDismiss(tabTray: TabTrayController)
    func tabTrayDidAddBookmark(tab: Browser)
    func tabTrayDidAddToReadingList(tab: Browser) -> ReadingListClientRecord?
    func tabTrayRequestsPresentationOf(viewController viewController: UIViewController)
}

class TabTrayController: UIViewController {
    let tabManager: TabManager
    let profile: Profile
    weak var delegate: TabTrayDelegate?

    var collectionView: UICollectionView!
    lazy var addTabButton: UIButton = {
        let addTabButton = UIButton()
        addTabButton.setImage(UIImage(named: "add")?.imageWithRenderingMode(.AlwaysTemplate), forState: .Normal)
        addTabButton.addTarget(self, action: #selector(TabTrayController.SELdidClickAddTab), forControlEvents: .TouchUpInside)
        addTabButton.accessibilityLabel = Strings.Add_Tab
        addTabButton.accessibilityIdentifier = "TabTrayController.addTabButton"
        return addTabButton
    }()
    
    var collectionViewTransitionSnapshot: UIView?
    
    /// Views to be animationed when preseting the Tab Tray.
    /// There is some bug related to the blurring background the tray controller attempts to handle.
    /// On animating self.view the blur effect will not animate (just pops in at the animation end),
    /// and must be animated manually. Instead of animating the larger view elements, smaller pieces
    /// must be animated in order to achieve a blur-incoming animation
    var viewsToAnimate: [UIView] = []

    private(set) internal var privateMode: Bool = false {
        didSet {
            if privateMode {
                togglePrivateMode.selected = true
                togglePrivateMode.accessibilityValue = PrivateModeStrings.toggleAccessibilityValueOn
                togglePrivateMode.backgroundColor = .whiteColor()
                
                addTabButton.tintColor = UIColor.whiteColor()
                
                blurBackdropView.effect = UIBlurEffect(style: .Dark)
            } else {
                togglePrivateMode.selected = false
                togglePrivateMode.accessibilityValue = PrivateModeStrings.toggleAccessibilityValueOff
                togglePrivateMode.backgroundColor = .clearColor()
                
                addTabButton.tintColor = UIColor.blackColor()
                
                blurBackdropView.effect = UIBlurEffect(style: .Light)
            }
            tabDataSource.updateData()
            collectionView?.reloadData()
        }
    }

    private var tabsToDisplay: [Browser] {
        return tabManager.tabs.displayedTabsForCurrentPrivateMode
    }

    lazy var togglePrivateMode: UIButton = {
        let button = UIButton()
        button.setTitle(Strings.Private, forState: .Normal)
        button.setTitleColor(UIColor.blackColor(), forState: .Normal)
        button.titleLabel!.font = UIFont.systemFontOfSize(button.titleLabel!.font.pointSize + 2)
        button.contentEdgeInsets = UIEdgeInsetsMake(0, 4 /* left */, 0, 4 /* right */)
        button.layer.cornerRadius = 4.0
        button.addTarget(self, action: #selector(TabTrayController.SELdidTogglePrivateMode), forControlEvents: .TouchUpInside)
        button.accessibilityLabel = PrivateModeStrings.toggleAccessibilityLabel
        button.accessibilityHint = PrivateModeStrings.toggleAccessibilityHint
        button.accessibilityIdentifier = "TabTrayController.togglePrivateMode"

        return button
    }()
    
    private var blurBackdropView = UIVisualEffectView()

    private lazy var emptyPrivateTabsView: UIView = {
        return self.newEmptyPrivateTabsView()
    }()
    
    private lazy var tabDataSource: TabManagerDataSource = {
        return TabManagerDataSource(cellDelegate: self)
    }()

    private lazy var tabLayoutDelegate: TabLayoutDelegate = {
        let delegate = TabLayoutDelegate(profile: self.profile, traitCollection: self.traitCollection)
        delegate.tabSelectionDelegate = self
        return delegate
    }()

    override func dismissViewControllerAnimated(flag: Bool, completion: (() -> Void)?) {

        super.dismissViewControllerAnimated(flag, completion:completion)

        UIView.animateWithDuration(0.2) {
             getApp().browserViewController.toolbar?.leavingTabTrayMode()
        }

        getApp().browserViewController.updateTabCountUsingTabManager(getApp().tabManager)
    }

    init(tabManager: TabManager, profile: Profile) {
        self.tabManager = tabManager
        self.profile = profile
        super.init(nibName: nil, bundle: nil)

        tabManager.addDelegate(self)
    }

    convenience init(tabManager: TabManager, profile: Profile, tabTrayDelegate: TabTrayDelegate) {
        self.init(tabManager: tabManager, profile: profile)
        self.delegate = tabTrayDelegate
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationWillResignActiveNotification, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationWillEnterForegroundNotification, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NotificationDynamicFontChanged, object: nil)
        self.tabManager.removeDelegate(self)
    }

    func SELDynamicFontChanged(notification: NSNotification) {
        guard notification.name == NotificationDynamicFontChanged else { return }

        self.collectionView.reloadData()
    }

    @objc func onTappedBackground(gesture: UITapGestureRecognizer) {
        dismissViewControllerAnimated(true, completion: nil)
    }

    override func viewDidAppear(animated: Bool) {
        // TODO: centralize timing
        UIView.animateWithDuration(0.2) {
            self.viewsToAnimate.forEach { $0.alpha = 1.0 }
        }
        
        let tabs = WeakList<Browser>()
        getApp().tabManager.tabs.displayedTabsForCurrentPrivateMode.forEach {
            tabs.insert($0)
        }
        
        guard let selectedTab = tabManager.selectedTab else { return }
        let selectedIndex = tabs.indexOf(selectedTab) ?? 0
        self.collectionView.scrollToItemAtIndexPath(NSIndexPath(forItem: selectedIndex, inSection: 0), atScrollPosition: UICollectionViewScrollPosition.CenteredVertically, animated: false)
    }
    
// MARK: View Controller Callbacks
    override func viewDidLoad() {
        super.viewDidLoad()

        view.accessibilityLabel = Strings.Tabs_Tray

        let flowLayout = TabTrayCollectionViewLayout()
        collectionView = UICollectionView(frame: view.frame, collectionViewLayout: flowLayout)

        collectionView.dataSource = tabDataSource
        collectionView.delegate = tabLayoutDelegate

        collectionView.registerClass(TabCell.self, forCellWithReuseIdentifier: TabCell.Identifier)
        collectionView.backgroundColor = UIColor.clearColor()
        
        // Background view created for tapping background closure
        collectionView.backgroundView = UIView()
        collectionView.backgroundView?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(TabTrayController.onTappedBackground(_:))))

        viewsToAnimate = [blurBackdropView, collectionView, addTabButton, togglePrivateMode]
        viewsToAnimate.forEach {
            $0.alpha = 0.0
            view.addSubview($0)
        }

        makeConstraints()
        
        if profile.prefs.boolForKey(kPrefKeyPrivateBrowsingAlwaysOn) ?? false {
            togglePrivateMode.hidden = true
        }

        view.insertSubview(emptyPrivateTabsView, aboveSubview: collectionView)
        emptyPrivateTabsView.alpha = privateTabsAreEmpty() ? 1 : 0
        emptyPrivateTabsView.snp_makeConstraints { make in
            make.edges.equalTo(self.view)
        }

        // Make sure buttons are all setup before this, to allow
        // privateMode setter to setup final visuals
        let selectedTabIsPrivate = tabManager.selectedTab?.isPrivate ?? false
        privateMode = PrivateBrowsing.singleton.isOn || selectedTabIsPrivate

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(TabTrayController.SELappWillResignActiveNotification), name: UIApplicationWillResignActiveNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(TabTrayController.SELappDidBecomeActiveNotification), name: UIApplicationDidBecomeActiveNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(TabTrayController.SELDynamicFontChanged(_:)), name: NotificationDynamicFontChanged, object: nil)
    }

    override func traitCollectionDidChange(previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        // Update the trait collection we reference in our layout delegate
        tabLayoutDelegate.traitCollection = traitCollection
    }

    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)
        
        // Used to update the glow effect on the selected tab
        //  and update screenshot framing/positioning
        // Must be scheduled on next runloop
        dispatch_async(dispatch_get_main_queue()) { 
            self.collectionView.reloadData()
        }
        
        coordinator.animateAlongsideTransition({ _ in
            self.collectionView.collectionViewLayout.invalidateLayout()
        }, completion: nil)
    }

    private func makeConstraints() {
        
        togglePrivateMode.snp_makeConstraints { make in
            make.right.equalTo(addTabButton.snp_left).offset(-10)
            make.centerY.equalTo(self.addTabButton.snp_centerY)
        }

        addTabButton.snp_makeConstraints { make in
            make.trailing.equalTo(self.view)
            make.top.equalTo(snp_topLayoutGuideBottom)
            make.size.equalTo(UIConstants.ToolbarHeight)
        }

        collectionView.snp_makeConstraints { make in
            make.top.equalTo(addTabButton.snp_bottom)
            make.left.right.bottom.equalTo(self.view)
        }
        
        blurBackdropView.snp_makeConstraints { (make) in
            make.edges.equalTo(view)
        }
    }
    
    // View we display when there are no private tabs created
    private func newEmptyPrivateTabsView() -> UIView {
        let titleLabel = UILabel()
        titleLabel.textColor = EmptyPrivateTabsViewUX.TitleColor
        titleLabel.font = EmptyPrivateTabsViewUX.TitleFont
        titleLabel.textAlignment = NSTextAlignment.Center
        
        let descriptionLabel = UILabel()
        descriptionLabel.textColor = EmptyPrivateTabsViewUX.DescriptionColor
        descriptionLabel.font = EmptyPrivateTabsViewUX.DescriptionFont
        descriptionLabel.textAlignment = NSTextAlignment.Center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.preferredMaxLayoutWidth = EmptyPrivateTabsViewUX.MaxDescriptionWidth
        
        let emptyView = UIView()
        emptyView.backgroundColor = UIColor.blackColor().colorWithAlphaComponent(0.6)
        
        titleLabel.text = Strings.Private_Browsing
        descriptionLabel.text = Strings.Brave_wont_remember_any_of_your_history
        
        emptyView.addSubview(titleLabel)
        emptyView.addSubview(descriptionLabel)
        
        titleLabel.snp_makeConstraints { make in
            make.center.equalTo(emptyView)
        }
        
        descriptionLabel.snp_makeConstraints { make in
            make.top.equalTo(titleLabel.snp_bottom).offset(EmptyPrivateTabsViewUX.TextMargin)
            make.centerX.equalTo(emptyView)
        }
        return emptyView
    }

// MARK: Selectors

    func SELdidClickAddTab() {
        openNewTab()
    }
    
    func SELdidTogglePrivateMode() {
        telemetry(action: "Private mode button tapped", props: nil)

        let fromView: UIView
        if privateTabsAreEmpty() {
            fromView = emptyPrivateTabsView
        } else {
            let snapshot = collectionView.snapshotViewAfterScreenUpdates(false)
            snapshot!.frame = collectionView.frame
            view.insertSubview(snapshot!, aboveSubview: collectionView)
            fromView = snapshot!
        }

        privateMode = !privateMode
        if privateMode {
            PrivateBrowsing.singleton.enter()
        } else {
            view.userInteractionEnabled = false
            let activityView = UIActivityIndicatorView(activityIndicatorStyle: .WhiteLarge)
            activityView.center = view.center
            activityView.startAnimating()
            self.view.addSubview(activityView)

            PrivateBrowsing.singleton.exit().uponQueue(dispatch_get_main_queue()) {
                self.view.userInteractionEnabled = true
                activityView.stopAnimating()
            }
        }
        tabDataSource.updateData()

        collectionView.layoutSubviews()

        let scaleDownTransform = CGAffineTransformMakeScale(0.9, 0.9)
        let toView = privateTabsAreEmpty() ? emptyPrivateTabsView : collectionView
        toView.transform = scaleDownTransform
        toView.alpha = 0

        UIView.animateWithDuration(0.4, delay: 0, options: [], animations: { () -> Void in
            fromView.alpha = 0
            toView.transform = CGAffineTransformIdentity
            toView.alpha = 1
        }) { finished in
            if fromView != self.emptyPrivateTabsView {
                fromView.removeFromSuperview()
            }
        }
    }

    private func privateTabsAreEmpty() -> Bool {
        return privateMode && tabManager.tabs.privateTabs.count == 0
    }
    
    func changePrivacyMode(isPrivate: Bool) {
        if isPrivate != privateMode {
            guard let _ = collectionView else {
                privateMode = isPrivate
                return
            }
            SELdidTogglePrivateMode()
        }
    }
    
    private func openNewTab(request: NSURLRequest? = nil) {
        if privateMode {
            emptyPrivateTabsView.hidden = true
        }
        
        // We're only doing one update here, but using a batch update lets us delay selecting the tab
        // until after its insert animation finishes.
        self.collectionView.performBatchUpdates({ _ in
            var tab: Browser?
            tab = self.tabManager.addTab(request, isPrivate: self.privateMode)

            if let tab = tab {
                self.tabManager.selectTab(tab)
            }
        }, completion: { finished in
            if finished {
                self.dismissViewControllerAnimated(true, completion: nil)
            }
        })
    }
}

// MARK: - App Notifications
extension TabTrayController {
    func SELappWillResignActiveNotification() {
        if privateMode {
            collectionView.alpha = 0
        }
    }

    func SELappDidBecomeActiveNotification() {
        // Re-show any components that might have been hidden because they were being displayed
        // as part of a private mode tab
        UIView.animateWithDuration(0.2, delay: 0, options: UIViewAnimationOptions.CurveEaseInOut, animations: {
            self.collectionView.alpha = 1
        },
        completion: nil)
    }
}

extension TabTrayController: TabSelectionDelegate {
    func didSelectTabAtIndex(index: Int) {
        let tab = tabsToDisplay[index]
        tabManager.selectTab(tab)
        self.dismissViewControllerAnimated(true, completion: nil)
    }
}

extension TabTrayController: PresentingModalViewControllerDelegate {
    func dismissPresentedModalViewController(modalViewController: UIViewController, animated: Bool) {
        dismissViewControllerAnimated(animated, completion: { self.collectionView.reloadData() })
    }
}

extension TabTrayController: TabManagerDelegate {
    func tabManager(tabManager: TabManager, didSelectedTabChange selected: Browser?) {
    }

    func tabManager(tabManager: TabManager, didCreateWebView tab: Browser, url: NSURL?) {
    }

    func tabManager(tabManager: TabManager, didAddTab tab: Browser) {
        // Get the index of the added tab from it's set (private or normal)
        guard let index = tabsToDisplay.indexOf(tab) else { return }

        tabDataSource.updateData()

        self.collectionView?.performBatchUpdates({ _ in
            self.collectionView.insertItemsAtIndexPaths([NSIndexPath(forItem: index, inSection: 0)])
        }, completion: { finished in
            if finished {
                tabManager.selectTab(tab)
                // don't pop the tab tray view controller if it is not in the foreground
                if self.presentedViewController == nil {
                    self.dismissViewControllerAnimated(true, completion: nil)
                }
            }
        })
    }

    func tabManager(tabManager: TabManager, didRemoveTab tab: Browser) {
        var removedIndex = -1
        for i in 0..<tabDataSource.tabList.count() {
            let tabRef = tabDataSource.tabList.at(i)
            if tabRef == nil || getApp().tabManager.tabs.displayedTabsForCurrentPrivateMode.indexOf(tabRef!) == nil {
                removedIndex = i
                break
            }
        }

        tabDataSource.updateData()
        if (removedIndex < 0) {
            return
        }

        self.collectionView.deleteItemsAtIndexPaths([NSIndexPath(forItem: removedIndex, inSection: 0)])
        
        if privateTabsAreEmpty() {
            emptyPrivateTabsView.alpha = 1
        }
    }

    func tabManagerDidAddTabs(tabManager: TabManager) {
    }

    func tabManagerDidRestoreTabs(tabManager: TabManager) {
    }
}

extension TabTrayController: UIScrollViewAccessibilityDelegate {
    func accessibilityScrollStatusForScrollView(scrollView: UIScrollView) -> String? {
        var visibleCells = collectionView.visibleCells() as! [TabCell]
        var bounds = collectionView.bounds
        bounds = CGRectOffset(bounds, collectionView.contentInset.left, collectionView.contentInset.top)
        bounds.size.width -= collectionView.contentInset.left + collectionView.contentInset.right
        bounds.size.height -= collectionView.contentInset.top + collectionView.contentInset.bottom
        // visible cells do sometimes return also not visible cells when attempting to go past the last cell with VoiceOver right-flick gesture; so make sure we have only visible cells (yeah...)
        visibleCells = visibleCells.filter { !CGRectIsEmpty(CGRectIntersection($0.frame, bounds)) }

        let cells = visibleCells.map { self.collectionView.indexPathForCell($0)! }
        let indexPaths = cells.sort { (a: NSIndexPath, b: NSIndexPath) -> Bool in
            return a.section < b.section || (a.section == b.section && a.row < b.row)
        }

        if indexPaths.count == 0 {
            return Strings.No_tabs
        }

        let firstTab = indexPaths.first!.row + 1
        let lastTab = indexPaths.last!.row + 1
        let tabCount = collectionView.numberOfItemsInSection(0)

        if (firstTab == lastTab) {
            let format = Strings.Tab_xofx_template
            return String(format: format, NSNumber(integer: firstTab), NSNumber(integer: tabCount))
        } else {
            let format = Strings.Tabs_xtoxofx_template
            return String(format: format, NSNumber(integer: firstTab), NSNumber(integer: lastTab), NSNumber(integer: tabCount))
        }
    }
}

private func removeTabUtil(tabManager: TabManager, tab: Browser) {
    let isAlwaysPrivate = getApp().profile?.prefs.boolForKey(kPrefKeyPrivateBrowsingAlwaysOn) ?? false
    let createIfNone =  isAlwaysPrivate ? true : !PrivateBrowsing.singleton.isOn
    tabManager.removeTab(tab, createTabIfNoneLeft: createIfNone)
}

extension TabTrayController: SwipeAnimatorDelegate {
    func swipeAnimator(animator: SwipeAnimator, viewWillExitContainerBounds: UIView) {
        let tabCell = animator.container as! TabCell
        if let indexPath = collectionView.indexPathForCell(tabCell) {
            let tab = tabsToDisplay[indexPath.item]
            removeTabUtil(tabManager, tab: tab)
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, Strings.Closing_tab)
        }
    }
}

extension TabTrayController: TabCellDelegate {
    func tabCellDidClose(cell: TabCell) {
        let indexPath = collectionView.indexPathForCell(cell)!
        let tab = tabsToDisplay[indexPath.item]
        removeTabUtil(tabManager, tab: tab)
    }
}

extension TabTrayController: SettingsDelegate {
    func settingsOpenURLInNewTab(url: NSURL) {
        let request = NSURLRequest(URL: url)
        openNewTab(request)
    }
}

private class TabManagerDataSource: NSObject, UICollectionViewDataSource {
    unowned var cellDelegate: protocol<TabCellDelegate, SwipeAnimatorDelegate>

    private var tabList = WeakList<Browser>()

    init(cellDelegate: protocol<TabCellDelegate, SwipeAnimatorDelegate>) {
        self.cellDelegate = cellDelegate
        super.init()

        getApp().tabManager.tabs.displayedTabsForCurrentPrivateMode.forEach {
            tabList.insert($0)
        }
    }

    func updateData() {
        tabList = WeakList<Browser>()
        getApp().tabManager.tabs.displayedTabsForCurrentPrivateMode.forEach {
            tabList.insert($0)
        }
    }

    @objc func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let tabCell = collectionView.dequeueReusableCellWithReuseIdentifier(TabCell.Identifier, forIndexPath: indexPath) as! TabCell
        tabCell.animator.delegate = cellDelegate
        tabCell.delegate = cellDelegate

        guard let tab = tabList.at(indexPath.item) else {
            assert(false)
            return tabCell
        }
        tabCell.titleLbl.text = tab.displayTitle

        if !tab.displayTitle.isEmpty {
            tabCell.accessibilityLabel = tab.displayTitle
        } else {
            tabCell.accessibilityLabel = AboutUtils.getAboutComponent(tab.url)
        }

        tabCell.isAccessibilityElement = true
        tabCell.accessibilityHint = Strings.Swipe_right_or_left_with_three_fingers_to_close_the_tab

        if let favIcon = tab.displayFavicon {
            tabCell.favicon.sd_setImageWithURL(NSURL(string: favIcon.url)!)
            tabCell.favicon.backgroundColor = BraveUX.TabTrayCellBackgroundColor
        } else {
            tabCell.favicon.image = nil
        }
        
        tabCell.background.image = tab.screenshot.image
        tab.screenshot.listenerImages.removeAll() // TODO maybe UIImageWithNotify should only ever have one listener?
        tab.screenshot.listenerImages.append(UIImageWithNotify.WeakImageView(tabCell.background))

        // TODO: Move most view logic here instead of `init` or `prepareForReuse`
        // If the current tab add heightlighting
        if getApp().tabManager.selectedTab == tab {
            tabCell.backgroundHolder.layer.borderWidth = 1
            tabCell.backgroundHolder.layer.borderColor = BraveUX.DefaultBlue.CGColor
            tabCell.shadowView.layer.shadowRadius = 5
            tabCell.shadowView.layer.shadowColor = BraveUX.DefaultBlue.CGColor
            tabCell.shadowView.layer.shadowOpacity = 1.0
            tabCell.shadowView.layer.shadowOffset = CGSize(width: 0, height: 0)
            tabCell.shadowView.layer.shadowPath = UIBezierPath(roundedRect: tabCell.bounds, cornerRadius: tabCell.backgroundHolder.layer.cornerRadius).CGPath
            tabCell.background.alpha = 1.0
        } else {
            tabCell.background.alpha = 0.7
        }
        
        return tabCell
    }

    @objc func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return tabList.count()
    }
}

@objc protocol TabSelectionDelegate: class {
    func didSelectTabAtIndex(index :Int)
}

private class TabLayoutDelegate: NSObject, UICollectionViewDelegateFlowLayout {
    weak var tabSelectionDelegate: TabSelectionDelegate?

    private var traitCollection: UITraitCollection
    private var profile: Profile
    private var numberOfColumns: Int {
        let compactLayout = profile.prefs.boolForKey("CompactTabLayout") ?? true

        // iPhone 4-6+ portrait
        if traitCollection.horizontalSizeClass == .Compact && traitCollection.verticalSizeClass == .Regular {
            return compactLayout ? TabTrayControllerUX.CompactNumberOfColumnsThin : TabTrayControllerUX.NumberOfColumnsThin
        } else {
            return TabTrayControllerUX.NumberOfColumnsWide
        }
    }

    init(profile: Profile, traitCollection: UITraitCollection) {
        self.profile = profile
        self.traitCollection = traitCollection
        super.init()
    }

    private func cellHeightForCurrentDevice() -> CGFloat {
        let compactLayout = profile.prefs.boolForKey("CompactTabLayout") ?? true
        let shortHeight = TabTrayControllerUX.TitleBoxHeight * (compactLayout ? 7 : 6)

        if self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClass.Compact {
            return shortHeight
        } else if self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClass.Compact {
            return rint(CGRectGetHeight(UIScreen.mainScreen().bounds) / 3)
        } else {
            return TabTrayControllerUX.TitleBoxHeight * 8
        }
    }

    @objc func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAtIndex section: Int) -> CGFloat {
        return TabTrayControllerUX.Margin
    }

    @objc func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: NSIndexPath) -> CGSize {
        let cellWidth = floor((collectionView.bounds.width - TabTrayControllerUX.Margin * CGFloat(numberOfColumns + 1)) / CGFloat(numberOfColumns))
        return CGSizeMake(cellWidth, self.cellHeightForCurrentDevice())
    }

    @objc func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAtIndex section: Int) -> UIEdgeInsets {
        return UIEdgeInsetsMake(TabTrayControllerUX.Margin, TabTrayControllerUX.Margin, TabTrayControllerUX.Margin, TabTrayControllerUX.Margin)
    }

    @objc func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAtIndex section: Int) -> CGFloat {
        return TabTrayControllerUX.Margin
    }

    @objc func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        tabSelectionDelegate?.didSelectTabAtIndex(indexPath.row)
    }
}

// There seems to be a bug with UIKit where when the UICollectionView changes its contentSize
// from > frame.size to <= frame.size: the contentSet animation doesn't properly happen and 'jumps' to the
// final state.
// This workaround forces the contentSize to always be larger than the frame size so the animation happens more
// smoothly. This also makes the tabs be able to 'bounce' when there are not enough to fill the screen, which I
// think is fine, but if needed we can disable user scrolling in this case.
private class TabTrayCollectionViewLayout: UICollectionViewFlowLayout {
    private override func collectionViewContentSize() -> CGSize {
        var calculatedSize = super.collectionViewContentSize()
        let collectionViewHeight = collectionView?.bounds.size.height ?? 0
        if calculatedSize.height < collectionViewHeight && collectionViewHeight > 0 {
            calculatedSize.height = collectionViewHeight + 1
        }
        return calculatedSize
    }
}

struct EmptyPrivateTabsViewUX {
    static let TitleColor = UIColor.whiteColor()
    static let TitleFont = UIFont.systemFontOfSize(22, weight: UIFontWeightMedium)
    static let DescriptionColor = UIColor.whiteColor()
    static let DescriptionFont = UIFont.systemFontOfSize(17)
    static let LearnMoreFont = UIFont.systemFontOfSize(15, weight: UIFontWeightMedium)
    static let TextMargin: CGFloat = 18
    static let LearnMoreMargin: CGFloat = 30
    static let MaxDescriptionWidth: CGFloat = 250
}
