/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */
import UIKit
import SnapKit

protocol TabWidgetDelegate: class {
    func tabWidgetClose(tab: TabWidget)
    func tabWidgetSelected(tab: TabWidget)
    func tabWidgetDragMoved(tab: TabWidget, distance: CGFloat, isEnding: Bool)
    func tabWidgetDragStarted(tab: TabWidget)
}

let labelInsetFromRight = CGFloat(24)

class TabDragClone : UIImageView {
    let parent: TabWidget
    required init(parent: TabWidget, frame: CGRect) {
        self.parent = parent
        super.init(frame: frame)
        layer.borderWidth = 1
        layer.borderColor = UIColor.blackColor().colorWithAlphaComponent(0.4).CGColor
        backgroundColor = UIColor.blackColor().colorWithAlphaComponent(0.2)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var lastLocation:CGPoint?
    var translation:CGPoint!
    func detectPan(recognizer:UIPanGestureRecognizer) {
        if lastLocation == nil {
            lastLocation = self.center
        }
        translation = recognizer.translationInView(superview!)
        center = CGPointMake(lastLocation!.x + translation.x, lastLocation!.y)
    }

    override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {
        self.superview?.bringSubviewToFront(self)
        lastLocation = self.center
    }

    override func touchesEnded(touches: Set<UITouch>, withEvent event: UIEvent?) {
        if let lastLocation = lastLocation {
            center = lastLocation
        }
        lastLocation = nil
        alpha = 1.0
    }
}

class TabWidget : UIView {
    let title = UIButton()
    let close = UIButton()
    weak var delegate: TabWidgetDelegate?
    private(set) weak var browser: Browser?
    var widthConstraint: Constraint? = nil

    // Drag and drop items
    var dragClone: TabDragClone?
    let spacerRight = UIView()
    var pan: UIPanGestureRecognizer!
    let separatorLine = UIView() // visibility is controlled by TabsBarViewController

    init(browser: Browser, parentScrollView: UIScrollView) {
        super.init(frame: CGRectZero)
        parentScrollView.addSubview(spacerRight)

        self.translatesAutoresizingMaskIntoConstraints = false
        self.browser = browser

        if let wv = browser.webView {
            wv.delegatesForPageState.append(BraveWebView.Weak_WebPageStateDelegate(value: self))
        }


        close.addTarget(self, action: #selector(clicked), forControlEvents: .TouchUpInside)
        title.addTarget(self, action: #selector(selected), forControlEvents: .TouchUpInside)
        title.setTitle("", forState: .Normal)
        [close, title, separatorLine].forEach { addSubview($0) }

        close.setImage(UIImage(named: "stop")?.imageWithRenderingMode(.AlwaysTemplate), forState: .Normal)
        close.snp_makeConstraints(closure: { (make) in
            make.top.bottom.equalTo(self)
            make.left.equalTo(self).inset(4)
            make.width.equalTo(24)
        })
        close.tintColor = UIColor.blackColor()

        reinstallConstraints()

        separatorLine.backgroundColor = UIColor.blackColor().colorWithAlphaComponent(0.2)
        separatorLine.snp_makeConstraints { (make) in
            make.left.equalTo(self)
            make.width.equalTo(1)
            make.height.equalTo(22)
            make.centerY.equalTo(self.snp_centerY)
        }

        deselect()

        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        let g = UILongPressGestureRecognizer(target: self, action: #selector(longPress))
        g.delegate = self
        title.addGestureRecognizer(g)

        pan = UIPanGestureRecognizer(target:self, action:#selector(detectPan(_:)))
        parentScrollView.addGestureRecognizer(pan)
        pan.delegate = self

    }

    func reinstallConstraints() {
        title.snp_remakeConstraints { (make) in
            make.top.bottom.equalTo(self)
            make.left.equalTo(close.snp_right)
            make.right.equalTo(self).inset(labelInsetFromRight)
        }
    }

    func breakConstraintsForShrinking() {
        title.snp_remakeConstraints { (make) in
            make.top.bottom.equalTo(self)
            make.left.lessThanOrEqualTo(close.snp_right)
            make.width.lessThanOrEqualTo(title.frame.width)
            make.right.greaterThanOrEqualTo(self).inset(labelInsetFromRight)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func clicked() {
        delegate?.tabWidgetClose(self)
    }

    func deselect() {
        backgroundColor = UIColor.init(white: 0.0, alpha: 0.1)
        title.titleLabel!.font = UIFont.systemFontOfSize(12)
        title.setTitleColor(PrivateBrowsing.singleton.isOn ? UIColor(white: 1.0, alpha: 0.4) : UIColor(white: 0.0, alpha: 0.4), forState: .Normal)
        close.hidden = true
        close.tintColor = PrivateBrowsing.singleton.isOn ? UIColor.whiteColor() : UIColor.blackColor()
    }

    func selected() {
        delegate?.tabWidgetSelected(self)
    }

    func setStyleToSelected() {
        title.titleLabel!.font = UIFont.systemFontOfSize(12, weight: UIFontWeightSemibold)
        title.setTitleColor(PrivateBrowsing.singleton.isOn ? UIColor.whiteColor() : UIColor.blackColor(), forState: .Normal)
        backgroundColor = UIColor.clearColor()
        close.hidden = false
        
    }

    func isSelectedStyle() -> Bool {
        return !close.hidden
    }

    private var titleUpdateScheduled = false
    func updateTitle_throttled() {
        if titleUpdateScheduled {
            return
        }
        titleUpdateScheduled = true
        postAsyncToMain(0.2) { [weak self] in
            self?.titleUpdateScheduled = false
            if let t = self?.browser?.webView?.title where !t.isEmpty {
                self?.setTitle(t)
            }
        }
    }

    func setTitle(title: String?) {
        if let title = title where title != "localhost" {
            self.title.setTitle(title, forState: .Normal)
        } else {
            self.title.setTitle("", forState: .Normal)
        }
    }
}

extension TabWidget : WebPageStateDelegate {
    func webView(webView: UIWebView, urlChanged: String) {
        if let t = browser?.url?.baseDomain() where  title.titleLabel?.text?.isEmpty ?? true {
            setTitle(t)
        }

        updateTitle_throttled()
    }

    func webView(webView: UIWebView, progressChanged: Float) {
        updateTitle_throttled()
    }

    func webView(webView: UIWebView, isLoading: Bool) {}
    func webView(webView: UIWebView, canGoBack: Bool) {}
    func webView(webView: UIWebView, canGoForward: Bool) {}
}

extension TabWidget : UIGestureRecognizerDelegate {
    func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWithGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

extension TabWidget {
    func remakeLayout(prev prev: UIView, width: CGFloat, scrollView: UIView) {
        snp_remakeConstraints("tab: \(title.titleLabel?.text) ") {
            make in
            widthConstraint = make.width.equalTo(width).constraint
            make.height.equalTo(tabHeight)
            make.left.equalTo(prev.snp_right)
            make.top.equalTo(0)
        }

        spacerRight.snp_remakeConstraints("spacer: \(title.titleLabel?.text) ", closure:
            { (make) in
                make.top.equalTo(scrollView)
                make.height.equalTo(tabHeight)
                make.left.equalTo(snp_right)
                make.width.equalTo(0)
                make.top.equalTo(0)
        })
    }

    func longPress(g: UILongPressGestureRecognizer) {
        if g.state == .Ended {
            postAsyncToMain(0.1) {
                if let dragClone = self.dragClone where dragClone.lastLocation == nil {
                    dragClone.removeFromSuperview()
                    self.dragClone = nil
                    self.alpha = 1.0
                }
            }
        }

        if dragClone != nil || g.state != .Began {
            return
        }

        delegate?.tabWidgetDragStarted(self)

        dragClone = TabDragClone(parent: self, frame: frame)
        UIGraphicsBeginImageContextWithOptions(bounds.size, false, 0.0)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        layer.renderInContext(context)
        let screenShot = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        dragClone!.image = screenShot
        superview!.addSubview(dragClone!)
        alpha = 0
    }

    func detectPan(recognizer:UIPanGestureRecognizer) {
        if let dragClone = dragClone {
            dragClone.detectPan(recognizer)
            delegate?.tabWidgetDragMoved(self, distance: recognizer.translationInView(superview!).x, isEnding: recognizer.state == .Ended)
        }
    }
}

