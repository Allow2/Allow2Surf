/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import Shared
import SnapKit
import XCGLogger

private let log = Logger.browserLogger

protocol BrowserLocationViewDelegate {
    func browserLocationViewDidTapLocation(browserLocationView: BrowserLocationView)
    func browserLocationViewDidLongPressLocation(browserLocationView: BrowserLocationView)
    func browserLocationViewDidTapReaderMode(browserLocationView: BrowserLocationView)
    /// - returns: whether the long-press was handled by the delegate; i.e. return `false` when the conditions for even starting handling long-press were not satisfied
    func browserLocationViewDidLongPressReaderMode(browserLocationView: BrowserLocationView) -> Bool
    func browserLocationViewLocationAccessibilityActions(browserLocationView: BrowserLocationView) -> [UIAccessibilityCustomAction]?
    func browserLocationViewDidTapReload(browserLocationView: BrowserLocationView)
    func browserLocationViewDidTapStop(browserLocationView: BrowserLocationView)
}

struct BrowserLocationViewUX {
    static let HostFontColor = UIColor.blackColor()
    static let BaseURLFontColor = UIColor.grayColor()
    static let BaseURLPitch = 0.75
    static let HostPitch = 1.0
    static let LocationContentInset = 8

    static let Themes: [String: Theme] = {
        var themes = [String: Theme]()
        
        // TODO: Currently fontColor theme adjustments are being overriden by the textColor.
        // This should be cleaned up.
        
        var theme = Theme()
        theme.URLFontColor = BraveUX.LocationBarTextColor_URLBaseComponent
        theme.hostFontColor = BraveUX.LocationBarTextColor_URLHostComponent
        theme.textColor = BraveUX.LocationBarTextColor
        theme.backgroundColor = BraveUX.LocationBarBackgroundColor
        themes[Theme.NormalMode] = theme
        
        theme = Theme()
        theme.URLFontColor = BraveUX.LocationBarTextColor_URLBaseComponent
        theme.hostFontColor = BraveUX.LocationBarTextColor_URLHostComponent
        theme.textColor = .whiteColor()
        theme.backgroundColor = BraveUX.LocationBarBackgroundColor_PrivateMode
        themes[Theme.PrivateMode] = theme

        return themes
    }()
}

class BrowserLocationView: UIView {
    var delegate: BrowserLocationViewDelegate?
    var longPressRecognizer: UILongPressGestureRecognizer!
    var tapRecognizer: UITapGestureRecognizer!

    // Variable colors should be overwritten by theme
    dynamic var baseURLFontColor: UIColor = BrowserLocationViewUX.BaseURLFontColor {
        didSet { updateTextWithURL() }
    }

    dynamic var hostFontColor: UIColor = BrowserLocationViewUX.HostFontColor {
        didSet { updateTextWithURL() }
    }
    
    // The color of the URL after it has loaded
    dynamic var fullURLFontColor: UIColor = BraveUX.LocationBarTextColor {
        didSet {
            updateTextWithURL()
            // Reset placeholder text, which will auto-adjust based on this new color
            self.urlTextField.attributedPlaceholder = self.placeholder
        }
    }

    var url: NSURL? {
        didSet {
            let wasHidden = lockImageView.hidden
            lockImageView.hidden = url?.scheme != "https"
            if wasHidden != lockImageView.hidden {
                UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil)
            }
            updateTextWithURL()
            setNeedsUpdateConstraints()
        }
    }

    var readerModeState: ReaderModeState {
        get {
            return readerModeButton.readerModeState
        }
        set (newReaderModeState) {
            if newReaderModeState != self.readerModeButton.readerModeState {
                let wasHidden = readerModeButton.hidden
                self.readerModeButton.readerModeState = newReaderModeState
                readerModeButton.hidden = (newReaderModeState == ReaderModeState.Unavailable)
                if wasHidden != readerModeButton.hidden {
                    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil)
                }
                UIView.animateWithDuration(0.1, animations: { () -> Void in
                    if newReaderModeState == ReaderModeState.Unavailable {
                        self.readerModeButton.alpha = 0.0
                    } else {
                        self.readerModeButton.alpha = 1.0
                    }
                    self.setNeedsUpdateConstraints()
                    self.layoutIfNeeded()
                })
            }
        }
    }

    /// Returns constant placeholder text with current URL color
    var placeholder: NSAttributedString {
        let placeholderText = Strings.Search_or_enter_address
        return NSAttributedString(string: placeholderText, attributes: [NSForegroundColorAttributeName: self.fullURLFontColor.colorWithAlphaComponent(0.5)])
    }

    lazy var urlTextField: UITextField = {
        let urlTextField = DisplayTextField()

        self.longPressRecognizer.delegate = self
        urlTextField.addGestureRecognizer(self.longPressRecognizer)
        self.tapRecognizer.delegate = self
        urlTextField.addGestureRecognizer(self.tapRecognizer)

        urlTextField.attributedPlaceholder = self.placeholder
        urlTextField.accessibilityIdentifier = "url"
        urlTextField.accessibilityActionsSource = self
        urlTextField.font = UIConstants.DefaultChromeFont
        return urlTextField
    }()

    private lazy var lockImageView: UIImageView = {
        let lockImageView = UIImageView(image: UIImage(named: "lock_verified"))
        lockImageView.hidden = true
        lockImageView.isAccessibilityElement = true
        lockImageView.contentMode = UIViewContentMode.Center
        lockImageView.accessibilityLabel = Strings.Secure_connection
        return lockImageView
    }()

    private lazy var readerModeButton: ReaderModeButton = {
        let readerModeButton = ReaderModeButton(frame: CGRectZero)
        readerModeButton.hidden = true
        readerModeButton.addTarget(self, action: #selector(BrowserLocationView.SELtapReaderModeButton), forControlEvents: .TouchUpInside)
        readerModeButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(BrowserLocationView.SELlongPressReaderModeButton(_:))))
        readerModeButton.isAccessibilityElement = true
        readerModeButton.accessibilityLabel = Strings.Reader_View
        readerModeButton.accessibilityCustomActions = [UIAccessibilityCustomAction(name: Strings.Add_to_Reading_List, target: self, selector: #selector(BrowserLocationView.SELreaderModeCustomAction))]
        return readerModeButton
    }()

    let stopReloadButton = UIButton()

    func stopReloadButtonIsLoading(isLoading: Bool) {
        stopReloadButton.selected = isLoading
        stopReloadButton.accessibilityLabel = isLoading ? Strings.Stop : Strings.Reload
    }

    func didClickStopReload() {
        if stopReloadButton.accessibilityLabel == Strings.Stop {
            delegate?.browserLocationViewDidTapStop(self)
        } else {
            delegate?.browserLocationViewDidTapReload(self)
        }
    }

    // Prefixing with brave to distinguish from progress view that firefox has (which we hide)
    var braveProgressView: UIView = UIView(frame: CGRectMake(0, 0, 0, CGFloat(URLBarViewUX.LocationHeight)))

    override init(frame: CGRect) {
        super.init(frame: frame)

        stopReloadButton.accessibilityIdentifier = "BrowserToolbar.stopReloadButton"
        
        stopReloadButton.setImage(UIImage.templateImage(named: "reload"), forState: .Normal)
        stopReloadButton.setImage(UIImage.templateImage(named: "stop"), forState: .Selected)
        // Setup the state dependent visuals
        stopReloadButtonIsLoading(false)
        
        stopReloadButton.addTarget(self, action: #selector(BrowserLocationView.didClickStopReload), forControlEvents: UIControlEvents.TouchUpInside)

        longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(BrowserLocationView.SELlongPressLocation(_:)))
        tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(BrowserLocationView.SELtapLocation(_:)))

        addSubview(urlTextField)
        addSubview(lockImageView)
        addSubview(readerModeButton)
        addSubview(stopReloadButton)

        braveProgressView.accessibilityLabel = "braveProgressView"
        braveProgressView.backgroundColor = PrivateBrowsing.singleton.isOn ? BraveUX.ProgressBarDarkColor : BraveUX.ProgressBarColor
        braveProgressView.layer.cornerRadius = BraveUX.TextFieldCornerRadius
        braveProgressView.layer.masksToBounds = true
        self.addSubview(braveProgressView)
        self.sendSubviewToBack(braveProgressView)
    }

    override var accessibilityElements: [AnyObject]! {
        get {
            return [lockImageView, urlTextField, readerModeButton].filter { !$0.hidden }
        }
        set {
            super.accessibilityElements = newValue
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateConstraints() {

        lockImageView.snp_makeConstraints { make in
            make.centerY.equalTo(self)
            make.left.equalTo(self).offset(BrowserLocationViewUX.LocationContentInset)
            make.width.equalTo(self.lockImageView.intrinsicContentSize().width)
        }

        readerModeButton.snp_makeConstraints { make in
            make.right.equalTo(stopReloadButton.snp_left).inset(-6)
            make.height.centerY.equalTo(self)
            make.width.equalTo(20)
        }

        stopReloadButton.snp_makeConstraints { make in
            make.right.equalTo(self).inset(BrowserLocationViewUX.LocationContentInset)
            make.height.centerY.equalTo(self)
            make.width.equalTo(20)
        }

        urlTextField.snp_remakeConstraints { make in
            make.top.bottom.equalTo(self)

            if lockImageView.hidden {
                make.left.equalTo(self).offset(BrowserLocationViewUX.LocationContentInset)
            } else {
                make.left.equalTo(self.lockImageView.snp_right).offset(BrowserLocationViewUX.LocationContentInset)
            }

            if readerModeButton.hidden {
                make.right.equalTo(self.stopReloadButton.snp_left)
            } else {
                make.right.equalTo(self.readerModeButton.snp_left).inset(-4)
            }
        }

        super.updateConstraints()
    }

    func SELtapReaderModeButton() {
        delegate?.browserLocationViewDidTapReaderMode(self)
    }

    func SELlongPressReaderModeButton(recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == UIGestureRecognizerState.Began {
            delegate?.browserLocationViewDidLongPressReaderMode(self)
        }
    }

    func SELlongPressLocation(recognizer: UITapGestureRecognizer) {
        if recognizer.state == UIGestureRecognizerState.Began {
            delegate?.browserLocationViewDidLongPressLocation(self)
        }
    }

    func SELtapLocation(recognizer: UITapGestureRecognizer) {
        delegate?.browserLocationViewDidTapLocation(self)
    }

    func SELreaderModeCustomAction() -> Bool {
        return delegate?.browserLocationViewDidLongPressReaderMode(self) ?? false
    }

    private func updateTextWithURL() {
        if url == nil {
            urlTextField.text = ""
            return
        }

        if let httplessURL = url?.absoluteDisplayString(), let baseDomain = url?.baseDomain() {
            // Highlight the base domain of the current URL.
            let attributedString = NSMutableAttributedString(string: httplessURL)
            let nsRange = NSMakeRange(0, httplessURL.characters.count)
            attributedString.addAttribute(NSForegroundColorAttributeName, value: baseURLFontColor, range: nsRange)
            attributedString.colorSubstring(baseDomain, withColor: hostFontColor)
            attributedString.addAttribute(UIAccessibilitySpeechAttributePitch, value: NSNumber(double: BrowserLocationViewUX.BaseURLPitch), range: nsRange)
            attributedString.pitchSubstring(baseDomain, withPitch: BrowserLocationViewUX.HostPitch)
            urlTextField.attributedText = attributedString
        } else {
            // If we're unable to highlight the domain, just use the URL as is.
            urlTextField.text = url?.absoluteString
        }
        postAsyncToMain(0.1) {
            self.urlTextField.textColor = self.fullURLFontColor
        }
    }
}

extension BrowserLocationView: UIGestureRecognizerDelegate {
    func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWithGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailByGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // If the longPressRecognizer is active, fail all other recognizers to avoid conflicts.
        return gestureRecognizer == longPressRecognizer
    }
}

extension BrowserLocationView: AccessibilityActionsSource {
    func accessibilityCustomActionsForView(view: UIView) -> [UIAccessibilityCustomAction]? {
        if view === urlTextField {
            return delegate?.browserLocationViewLocationAccessibilityActions(self)
        }
        return nil
    }
}

extension BrowserLocationView: Themeable {
    func applyTheme(themeName: String) {
        guard let theme = BrowserLocationViewUX.Themes[themeName] else {
            log.error("Unable to apply unknown theme \(themeName)")
            return
        }
        baseURLFontColor = theme.URLFontColor!
        hostFontColor = theme.hostFontColor!
        fullURLFontColor = theme.textColor!
        stopReloadButton.tintColor = theme.textColor!
        backgroundColor = theme.backgroundColor
    }
}

private class ReaderModeButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        tintColor = BraveUX.ActionButtonTintColor
        setImage(UIImage(named: "reader.png")!.imageWithRenderingMode(.AlwaysTemplate), forState: UIControlState.Normal)
        setImage(UIImage(named: "reader_active.png"), forState: UIControlState.Selected)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var _readerModeState: ReaderModeState = ReaderModeState.Unavailable
    
    var readerModeState: ReaderModeState {
        get {
            return _readerModeState;
        }
        set (newReaderModeState) {
            _readerModeState = newReaderModeState
            switch _readerModeState {
            case .Available:
                self.enabled = true
                self.selected = false
            case .Unavailable:
                self.enabled = false
                self.selected = false
            case .Active:
                self.enabled = true
                self.selected = true
            }
        }
    }
}

private class DisplayTextField: UITextField {
    weak var accessibilityActionsSource: AccessibilityActionsSource?

    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            return accessibilityActionsSource?.accessibilityCustomActionsForView(self)
        }
        set {
            super.accessibilityCustomActions = newValue
        }
    }

    private override func canBecomeFirstResponder() -> Bool {
        return false
    }
}
