/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
import Storage
import SnapKit

let kNotificationLeftSlideOutClicked = "kNotificationLeftSlideOutClicked"
let kNotificationBraveButtonClicked = "kNotificationBraveButtonClicked"


class BraveTopViewController : UIViewController {
    var browserViewController:BraveBrowserViewController
    var mainSidePanel:MainSidePanelViewController
    var rightSidePanel:BraveRightSidePanelViewController
    var clickDetectionView = UIButton()
    var leftConstraint: Constraint? = nil
    var rightConstraint: Constraint? = nil
    var leftSidePanelButtonAndUnderlay: ButtonWithUnderlayView?
    init(browserViewController:BraveBrowserViewController) {
        self.browserViewController = browserViewController
        mainSidePanel = MainSidePanelViewController()
        rightSidePanel = BraveRightSidePanelViewController()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    private func addVC(vc: UIViewController) {
        addChildViewController(vc)
        view.addSubview(vc.view)
        vc.didMoveToParentViewController(self)
    }

    override func viewDidLoad() {
        view.accessibilityLabel = "HighestView"
        view.backgroundColor = BraveUX.TopLevelBackgroundColor

        browserViewController.view.accessibilityLabel = "BrowserViewController"

        addVC(browserViewController)
        addVC(mainSidePanel)
        addVC(rightSidePanel)


        mainSidePanel.view.snp_makeConstraints {
            make in
            make.bottom.left.top.equalTo(view)
            make.width.equalTo(0)
        }

        rightSidePanel.view.snp_makeConstraints {
            make in
            make.bottom.right.top.equalTo(view)
            make.width.equalTo(0)
        }

        clickDetectionView.backgroundColor = UIColor(white: 80/255, alpha: 0.3)

        setupBrowserConstraints()

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(onClickLeftSlideOut), name: kNotificationLeftSlideOutClicked, object: nil)

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(onClickBraveButton), name: kNotificationBraveButtonClicked, object: nil)

        clickDetectionView.addTarget(self, action: #selector(BraveTopViewController.dismissAllSidePanels), forControlEvents: UIControlEvents.TouchUpInside)

        mainSidePanel.browserViewController = browserViewController
    }

    @objc func dismissAllSidePanels() {
        if leftPanelShowing() {
            mainSidePanel.willHide()
            togglePanel(mainSidePanel)
            leftSidePanelButtonAndUnderlay?.selected = false
            leftSidePanelButtonAndUnderlay?.underlay.hidden = true
        }

        if rightPanelShowing() {
            togglePanel(rightSidePanel)
        }
    }

    private func setupBrowserConstraints() {
        browserViewController.view.snp_makeConstraints {
            make in
            make.bottom.equalTo(view)
            make.top.equalTo(snp_topLayoutGuideTop)
            let _rightConstraint = make.right.equalTo(view).constraint
            let _leftConstraint = make.left.equalTo(view).constraint

            if UIDevice.currentDevice().userInterfaceIdiom == .Phone {
                rightConstraint = _rightConstraint
                leftConstraint = _leftConstraint
            }
        }

        if UIDevice.currentDevice().userInterfaceIdiom != .Phone {
            browserViewController.header.snp_makeConstraints { make in
                if rightConstraint == nil {
                    leftConstraint = make.left.equalTo(view).constraint
                    rightConstraint = make.right.equalTo(view).constraint
                }
            }
        }
    }

    override func preferredStatusBarStyle() -> UIStatusBarStyle {
        return PrivateBrowsing.singleton.isOn ? .LightContent : .Default
    }

    func leftPanelShowing() -> Bool {
        return mainSidePanel.view.frame.width == CGFloat(BraveUX.WidthOfSlideOut)
    }

    func rightPanelShowing() -> Bool {
        return rightSidePanel.view.frame.width == CGFloat(BraveUX.WidthOfSlideOut)
    }

    override func prefersStatusBarHidden() -> Bool {
        if UIDevice.currentDevice().userInterfaceIdiom != .Phone {
            return super.prefersStatusBarHidden()
        }

        if BraveApp.isIPhoneLandscape() {
            return true
        }

        return leftPanelShowing() || rightPanelShowing()
    }

    func onClickLeftSlideOut(notification: NSNotification) {
        leftSidePanelButtonAndUnderlay = notification.object as? ButtonWithUnderlayView
        if !rightSidePanel.view.hidden {
            togglePanel(rightSidePanel)
        }
        togglePanel(mainSidePanel)

        // Dismiss keyboard if it is showing.
        UIApplication.sharedApplication().sendAction(#selector(UIResponder.resignFirstResponder), to:nil, from:nil, forEvent:nil)
    }

    func onClickBraveButton(notification: NSNotification) {
        if !mainSidePanel.view.hidden {
            togglePanel(mainSidePanel)
        }
        
        browserViewController.tabManager.selectedTab?.webView?.checkScriptBlockedAndBroadcastStats()
        togglePanel(rightSidePanel)
    }

    func togglePanel(panel: SidePanelBaseViewController) {
        let willShow = panel.view.hidden
        if panel === mainSidePanel {
            leftSidePanelButtonAndUnderlay?.selected = willShow
            leftSidePanelButtonAndUnderlay?.hideUnderlay(!willShow)
        } else if panel.view.hidden && !panel.canShow {
            return
        }

        if clickDetectionView.superview != nil {
            clickDetectionView.userInteractionEnabled = false
            UIView.animateWithDuration(0.2, animations: {
                self.clickDetectionView.alpha = 0
                }, completion: { _ in
                    self.clickDetectionView.removeFromSuperview()
            } )
        }

        if willShow {
            clickDetectionView.alpha = 0
            clickDetectionView.userInteractionEnabled = true

            view.addSubview(clickDetectionView)
            clickDetectionView.snp_remakeConstraints {
                make in
                make.top.bottom.equalTo(browserViewController.view)
                make.right.equalTo(rightSidePanel.view.snp_left)
                make.left.equalTo(mainSidePanel.view.snp_right)
            }
            clickDetectionView.layoutIfNeeded()

            UIView.animateWithDuration(0.25) {
                self.clickDetectionView.alpha = 1
            }
        }

        if willShow {
            // this will set the profile and trigger DB query, be careful
            panel.setHomePanelDelegate(self)
        }
        panel.showPanel(willShow, parentSideConstraints: [leftConstraint, rightConstraint])
    }

    func updateBookmarkStatus(isBookmarked: Bool) {
//        let currentURL = browserViewController.urlBar.currentURL
        let currentTab = browserViewController.tabManager.selectedTab
        let currentURL = currentTab?.displayURL
        mainSidePanel.updateBookmarkStatus(isBookmarked, url: currentURL)
    }
}

extension BraveTopViewController : HomePanelDelegate {
    func homePanelDidRequestToSignIn(homePanel: HomePanel) {}
    func homePanelDidRequestToCreateAccount(homePanel: HomePanel) {}
    func homePanel(homePanel: HomePanel, didSelectURL url: NSURL, visitType: VisitType) {
        print("selected \(url)")
        browserViewController.urlBar.leaveSearchMode()
        browserViewController.tabManager.selectedTab?.loadRequest(NSURLRequest(URL: url))
        togglePanel(mainSidePanel)
    }
}
