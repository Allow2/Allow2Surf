/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Storage
import SnapKit

class SidePanelBaseViewController : UIViewController {

    var browserViewController:BrowserViewController?

    // Wrap everything in a UIScrollView the view animation will not try to shrink the view
    // add subviews to containerView not self.view
    let containerView = UIView()

    var canShow: Bool { return true }

    // Set false for a right side panel
    var isLeftSidePanel = true
    
    let shadow = UIImageView()

    var parentSideConstraints: [Constraint?]?

    override func loadView() {
        self.view = UIScrollView(frame: UIScreen.mainScreen().bounds)
    }

    func viewAsScrollView() -> UIScrollView {
        return self.view as! UIScrollView
    }

    func setupContainerViewSize() {
        containerView.frame = CGRectMake(0, 0, CGFloat(BraveUX.WidthOfSlideOut), self.view.frame.height)
        viewAsScrollView().contentSize = CGSizeMake(containerView.frame.width, containerView.frame.height)
    }

    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animateAlongsideTransition({
            _ in
            self.setupContainerViewSize()
            }, completion: nil)

        super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)
    }

    override func viewDidLoad() {
        viewAsScrollView().scrollEnabled = false

        view.addSubview(containerView)
        setupContainerViewSize()
        containerView.backgroundColor = BraveUX.BackgroundColorForSideToolbars

        view.hidden = true
    }

    /// This should just be called one time to initially setup the UI elements for the side panels
    func setupUIElements() {
        shadow.image = UIImage(named: "panel_shadow")
        shadow.contentMode = .ScaleToFill
        shadow.alpha = 0.5

        if !isLeftSidePanel {
            shadow.transform = CGAffineTransformMakeScale(-1, 1)
        }

        if BraveUX.PanelShadowWidth > 0 {
            view.addSubview(shadow)

            shadow.snp_makeConstraints { make in
                if isLeftSidePanel {
                    make.right.top.equalTo(containerView)
                } else {
                    make.left.equalTo(view)
                    make.top.equalTo(view.superview!)
                }
                make.width.equalTo(BraveUX.PanelShadowWidth)

                let b = UIScreen.mainScreen().bounds
                make.height.equalTo(max(b.width, b.height))
            }
        }
    }

    func setupConstraints() {
        if shadow.image == nil { // arbitrary item check to see if func needs calling
            setupUIElements()
        }
    }

    func spaceForStatusBar() -> Double {
        let spacer = BraveApp.isIPhoneLandscape() ? 0.0 : 20.0
        return spacer
    }

    func verticalBottomPositionMainToolbar() -> Double {
        return Double(UIConstants.ToolbarHeight) + spaceForStatusBar()
    }

    func showPanel(showing: Bool, parentSideConstraints: [Constraint?]? = nil) {
        if (parentSideConstraints != nil) {
            self.parentSideConstraints = parentSideConstraints
        }

        if (showing) {
            view.hidden = false
            setupConstraints()
        }
        view.layoutIfNeeded()

        let width = showing ? BraveUX.WidthOfSlideOut : 0
        let animation = {
            guard let superview = self.view.superview else { return }
            self.view.snp_remakeConstraints {
                make in
                if self.isLeftSidePanel {
                    make.bottom.left.top.equalTo(superview)
                } else {
                    make.bottom.right.top.equalTo(superview)
                }
                make.width.equalTo(width)
            }

            if let constraints = self.parentSideConstraints {
                if UIDevice.currentDevice().userInterfaceIdiom == .Pad {
                    if let c = constraints.first where c != nil && self.isLeftSidePanel {
                        c!.updateOffset(width)
                    } else if let c = constraints.last where c != nil && !self.isLeftSidePanel {
                        c!.updateOffset(-width)
                    }
                } else {
                    for c in constraints where c != nil {
                        c!.updateOffset(self.isLeftSidePanel ? width : -width)
                    }
                }
            }
            
            superview.layoutIfNeeded()
            guard let topVC = getApp().rootViewController.visibleViewController else { return }
            topVC.setNeedsStatusBarAppearanceUpdate()
        }

        var percentComplete = Double(view.frame.width) / Double(BraveUX.WidthOfSlideOut)
        if showing {
            percentComplete = 1.0 - percentComplete
        }
        let duration = 0.2 * percentComplete
        UIView.animateWithDuration(duration, animations: animation)
        if (!showing) { // for reasons unknown, wheh put in a animation completion block, this is called immediately
            postAsyncToMain(duration) { self.view.hidden = true }
        }
    }

    func setHomePanelDelegate(delegate: HomePanelDelegate?) {}

}



