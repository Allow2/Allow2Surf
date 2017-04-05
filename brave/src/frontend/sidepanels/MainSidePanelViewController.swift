/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Storage
import SnapKit
import Shared

class MainSidePanelViewController : SidePanelBaseViewController {

    let bookmarksPanel = BookmarksPanel()
    private var bookmarksNavController:UINavigationController!
    
    let history = HistoryPanel()

    var bookmarksButton = UIButton()
    var historyButton = UIButton()

    var settingsButton = UIButton()

    let topButtonsView = UIView()
    let addBookmarkButton = UIButton()

    let divider = UIView()
    
    // Buttons swap out the full page, meaning only one can be active at a time
    var pageButtons: Dictionary<UIButton, UIViewController> {
        return [
            bookmarksButton: bookmarksNavController,
            historyButton: history,
        ]
    }

    override func setupUIElements() {
        super.setupUIElements()
        
        bookmarksNavController = UINavigationController(rootViewController: bookmarksPanel)
        bookmarksNavController.view.backgroundColor = UIColor.whiteColor()
        containerView.addSubview(topButtonsView)

        topButtonsView.addSubview(bookmarksButton)
        topButtonsView.addSubview(historyButton)
        topButtonsView.addSubview(addBookmarkButton)
        topButtonsView.addSubview(settingsButton)
        topButtonsView.addSubview(divider)

        divider.backgroundColor = BraveUX.ColorForSidebarLineSeparators

        settingsButton.setImage(UIImage(named: "settings")?.imageWithRenderingMode(.AlwaysTemplate), forState: .Normal)
        settingsButton.addTarget(self, action: #selector(onClickSettingsButton), forControlEvents: .TouchUpInside)
        settingsButton.accessibilityLabel = Strings.Settings

        bookmarksButton.setImage(UIImage(named: "bookmarklist"), forState: .Normal)
        bookmarksButton.accessibilityLabel = Strings.Show_Bookmarks
        
        historyButton.setImage(UIImage(named: "history"), forState: .Normal)
        historyButton.accessibilityLabel = Strings.Show_History

        addBookmarkButton.addTarget(self, action: #selector(onClickBookmarksButton), forControlEvents: .TouchUpInside)
        addBookmarkButton.setImage(UIImage(named: "bookmark"), forState: .Normal)
        addBookmarkButton.setImage(UIImage(named: "bookmarkMarked"), forState: .Selected)
        addBookmarkButton.accessibilityLabel = Strings.Add_Bookmark
        
        pageButtons.keys.forEach { $0.addTarget(self, action: #selector(onClickPageButton), forControlEvents: .TouchUpInside) }
        
        settingsButton.tintColor = BraveUX.ActionButtonTintColor
        addBookmarkButton.tintColor = BraveUX.ActionButtonTintColor

        containerView.addSubview(history.view)
        containerView.addSubview(bookmarksNavController.view)
        
        // Setup the bookmarks button as default
        onClickPageButton(bookmarksButton)

        bookmarksNavController.view.hidden = false

        containerView.bringSubviewToFront(topButtonsView)

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(historyItemAdded), name: kNotificationSiteAddedToHistory, object: nil)
    }

    @objc func historyItemAdded() {
        telemetry(action: "page changed", props: nil)
        if self.view.hidden {
            return
        }
        postAsyncToMain {
            self.history.refresh()
        }
    }
    
    func willHide() {
        //check if we are editing bookmark, if so pop controller then continue
        if self.bookmarksNavController?.visibleViewController is BookmarkEditingViewController {
           self.bookmarksNavController?.popViewControllerAnimated(false)
        }
        if self.bookmarksPanel.currentBookmarksPanel().tableView.editing {
            self.bookmarksPanel.currentBookmarksPanel().disableTableEditingMode()
        }
    }
    
    func onClickSettingsButton() {
        if getApp().profile == nil {
            return
        }

        let settingsTableViewController = BraveSettingsView(style: .Grouped)
        settingsTableViewController.profile = getApp().profile

        let controller = SettingsNavigationController(rootViewController: settingsTableViewController)
        controller.modalPresentationStyle = UIModalPresentationStyle.FormSheet
        presentViewController(controller, animated: true, completion: nil)
    }

    //For this function to be called there *must* be a selected tab and URL
    //since we disable the button when there's no URL
    //see MainSidePanelViewController#updateBookmarkStatus(isBookmarked,url)
    func onClickBookmarksButton() {
        guard let tab = browserViewController?.tabManager.selectedTab else { return }
        guard let url = tab.displayURL?.absoluteString else { return }
        
        //switch to bookmarks 'tab' in case we're looking at history and tapped the add/remove bookmark button
        onClickPageButton(bookmarksButton)

        //TODO -- need to separate the knowledge of whether current site is bookmarked or not from this UI button
        //tracked in https://github.com/brave/browser-ios/issues/375
        if addBookmarkButton.selected {
            browserViewController?.removeBookmark(url) {
                self.bookmarksPanel.currentBookmarksPanel().reloadData()
            }
        } else {
            var folderId:String? = nil
            var folderTitle:String? = nil
            if let currentFolder = self.bookmarksPanel.currentBookmarksPanel().bookmarkFolder {
                folderId = currentFolder.guid
                folderTitle = currentFolder.title
            }

            browserViewController?.addBookmark(url, title: tab.title, folderId: folderId, folderTitle: folderTitle).upon { _ in
                postAsyncToMain {
                    self.bookmarksPanel.currentBookmarksPanel().reloadData()
                }
            }
        }
    }

    override func setupConstraints() {
        super.setupConstraints()
        
        topButtonsView.snp_remakeConstraints {
            make in
            make.top.equalTo(containerView).offset(spaceForStatusBar())
            make.left.right.equalTo(containerView)
            make.height.equalTo(44.0)
        }

        func common(make: ConstraintMaker) {
            make.bottom.equalTo(self.topButtonsView)
            make.height.equalTo(UIConstants.ToolbarHeight)
            make.width.equalTo(60)
        }

        settingsButton.snp_remakeConstraints {
            make in
            common(make)
            make.centerX.equalTo(self.topButtonsView).multipliedBy(0.25)
        }

        divider.snp_remakeConstraints {
            make in
            make.bottom.equalTo(self.topButtonsView)
            make.width.equalTo(self.topButtonsView)
            make.height.equalTo(1.0)
        }

        historyButton.snp_remakeConstraints {
            make in
            make.bottom.equalTo(self.topButtonsView)
            make.height.equalTo(UIConstants.ToolbarHeight)
            make.centerX.equalTo(self.topButtonsView).multipliedBy(0.75)
        }

        bookmarksButton.snp_remakeConstraints {
            make in
            make.bottom.equalTo(self.topButtonsView)
            make.height.equalTo(UIConstants.ToolbarHeight)
            make.centerX.equalTo(self.topButtonsView).multipliedBy(1.25)
        }

        addBookmarkButton.snp_remakeConstraints {
            make in
            make.bottom.equalTo(self.topButtonsView)
            make.height.equalTo(UIConstants.ToolbarHeight)
            make.centerX.equalTo(self.topButtonsView).multipliedBy(1.75)
        }

        bookmarksNavController.view.snp_remakeConstraints { make in
            make.left.right.bottom.equalTo(containerView)
            make.top.equalTo(topButtonsView.snp_bottom)
        }

        history.view.snp_remakeConstraints { make in
            make.left.right.bottom.equalTo(containerView)
            make.top.equalTo(topButtonsView.snp_bottom)
        }
    }
    
    func onClickPageButton(sender: UIButton) {
        guard let newView = self.pageButtons[sender]?.view else { return }
        
        // Hide all old views
        self.pageButtons.forEach { (btn, controller) in
            btn.selected = false
            btn.tintColor = BraveUX.ActionButtonTintColor
            controller.view.hidden = true
        }
        
        // Setup the new view
        newView.hidden = false
        sender.selected = true
        sender.tintColor = BraveUX.ActionButtonSelectedTintColor
    }

    override func setHomePanelDelegate(delegate: HomePanelDelegate?) {
        bookmarksPanel.profile = getApp().profile
        history.profile = getApp().profile
        bookmarksPanel.homePanelDelegate = delegate
        history.homePanelDelegate = delegate
        
        if (delegate != nil) {
            bookmarksPanel.reloadData()
            history.reloadData()
        }
    }

    
    func updateBookmarkStatus(isBookmarked: Bool, url: NSURL?) {
        //URL will be passed as nil by updateBookmarkStatus from BraveTopViewController
        if url == nil {
            //disable button for homescreen/empty url
            addBookmarkButton.selected = false
            addBookmarkButton.enabled = false
        }
        else {
            addBookmarkButton.enabled = true
            addBookmarkButton.selected = isBookmarked
        }
    }
}


