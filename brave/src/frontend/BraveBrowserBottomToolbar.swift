/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// This is bottom toolbar

import SnapKit
import Shared

extension UIImage{

    func alpha(value:CGFloat)->UIImage
    {
        UIGraphicsBeginImageContextWithOptions(self.size, false, 0.0)

        let ctx = UIGraphicsGetCurrentContext();
        let area = CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height);

        CGContextScaleCTM(ctx!, 1, -1);
        CGContextTranslateCTM(ctx!, 0, -area.size.height);
        CGContextSetBlendMode(ctx!, .Multiply);
        CGContextSetAlpha(ctx!, value);
        CGContextDrawImage(ctx!, area, self.CGImage!);

        let newImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        return newImage!;
    }
}

class BraveBrowserBottomToolbar : BrowserToolbar {
    static var tabsCount = 1

    lazy var tabsButton: TabsButton = {
        let tabsButton = TabsButton()
        tabsButton.titleLabel.text = "\(tabsCount)"
        tabsButton.addTarget(self, action: #selector(BraveBrowserBottomToolbar.onClickShowTabs), forControlEvents: UIControlEvents.TouchUpInside)
        tabsButton.accessibilityLabel = Strings.Show_Tabs
        tabsButton.accessibilityIdentifier = "Toolbar.ShowTabs"
        return tabsButton
    }()

    var leftSpacer = UIView()
    var rightSpacer = UIView()

    private weak var clonedTabsButton: TabsButton?
    var tabsContainer = UIView()

    private static weak var currentInstance: BraveBrowserBottomToolbar?

    override init(frame: CGRect) {

        super.init(frame: frame)

        BraveBrowserBottomToolbar.currentInstance = self

        tabsContainer.addSubview(tabsButton)
        addSubview(tabsContainer)

        bringSubviewToFront(backButton)
        bringSubviewToFront(forwardButton)

        addSubview(leftSpacer)
        addSubview(rightSpacer)
        rightSpacer.userInteractionEnabled = false
        leftSpacer.userInteractionEnabled = false

        [backButton, forwardButton, shareButton].forEach {
            if let img = $0.currentImage {
                $0.setImage(img.alpha(BraveUX.BackForwardDisabledButtonAlpha), forState: .Disabled)
            }
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func applyTheme(themeName: String) {
        super.applyTheme(themeName)
        tabsButton.applyTheme(themeName)
    }

    class func updateTabCountDuplicatedButton(count: Int, animated: Bool) {
        guard let instance = BraveBrowserBottomToolbar.currentInstance else { return }
        tabsCount = count
        URLBarView.updateTabCount(instance.tabsButton,
                                  clonedTabsButton: &instance.clonedTabsButton, count: count, animated: animated)
    }

    func setAlphaOnAllExceptTabButton(alpha: CGFloat) {
        actionButtons.forEach { $0.alpha = alpha }
    }

    func onClickShowTabs() {
        setAlphaOnAllExceptTabButton(0)
        BraveURLBarView.tabButtonPressed()
    }

    func leavingTabTrayMode() {
        setAlphaOnAllExceptTabButton(1.0)
    }

    override func updateConstraints() {
        super.updateConstraints()

        func common(make: ConstraintMaker, bottomInset: Int = 0) {
            make.top.equalTo(self)
            make.bottom.equalTo(self).inset(bottomInset)
            make.width.equalTo(self).dividedBy(5)
        }

        backButton.snp_remakeConstraints { make in
            common(make)
            make.left.equalTo(self)
        }

        forwardButton.snp_remakeConstraints { make in
            common(make)
            make.left.equalTo(backButton.snp_right)
        }

        shareButton.snp_remakeConstraints { make in
            common(make)
            make.centerX.equalTo(self)
        }

        addTabButton.snp_remakeConstraints { make in
            common(make)
            make.left.equalTo(shareButton.snp_right)
        }

        tabsContainer.snp_remakeConstraints { make in
            common(make)
            make.right.equalTo(self)
        }

        tabsButton.snp_remakeConstraints { make in
            make.center.equalTo(tabsContainer)
            make.top.equalTo(tabsContainer)
            make.bottom.equalTo(tabsContainer)
            make.width.equalTo(tabsButton.snp_height)
        }
    }

    override func updatePageStatus(isWebPage isWebPage: Bool) {
        super.updatePageStatus(isWebPage: isWebPage)
        
        let isPrivate = getApp().browserViewController.tabManager.selectedTab?.isPrivate ?? false
        if isPrivate {
            postAsyncToMain(0) {
                // ensure theme is applied after inital styling
                self.applyTheme(Theme.PrivateMode)
            }
        }
    }
}
