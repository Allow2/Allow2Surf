/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import SnapKit
import Shared
import XCGLogger

private let log = Logger.browserLogger

enum ReaderModeBarButtonType {
    case MarkAsRead, MarkAsUnread, Settings, AddToReadingList, RemoveFromReadingList

    private var localizedDescription: String {
        switch self {
        case .MarkAsRead: return Strings.Mark_as_Read
        case .MarkAsUnread: return Strings.Mark_as_Unread
        case .Settings: return Strings.Reader_Mode_Settings
        case .AddToReadingList: return Strings.Add_to_Reading_List
        case .RemoveFromReadingList: return Strings.Remove_from_Reading_List
        }
    }

    private var imageName: String {
        switch self {
        case .MarkAsRead: return "MarkAsRead"
        case .MarkAsUnread: return "MarkAsUnread"
        case .Settings: return "SettingsSerif"
        case .AddToReadingList: return "addToReadingList"
        case .RemoveFromReadingList: return "removeFromReadingList"
        }
    }

    private var image: UIImage? {
        let image = UIImage(named: imageName)
        image?.accessibilityLabel = localizedDescription
        return image
    }
}

protocol ReaderModeBarViewDelegate {
    func readerModeBar(readerModeBar: ReaderModeBarView, didSelectButton buttonType: ReaderModeBarButtonType)
}

struct ReaderModeBarViewUX {

    static let Themes: [String: Theme] = {
        var themes = [String: Theme]()
        var theme = Theme()
        theme.backgroundColor = UIConstants.PrivateModeReaderModeBackgroundColor
        theme.buttonTintColor = UIColor.whiteColor()
        themes[Theme.PrivateMode] = theme

        theme = Theme()
        theme.backgroundColor = UIColor.whiteColor()
        theme.buttonTintColor = UIColor.darkGrayColor()
        themes[Theme.NormalMode] = theme

        return themes
    }()
}

class ReaderModeBarView: UIView {
    var delegate: ReaderModeBarViewDelegate?
    var settingsButton: UIButton!

    dynamic var buttonTintColor: UIColor = UIColor.clearColor() {
        didSet {
            settingsButton.tintColor = self.buttonTintColor
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        // This class is glued on to the bottom of the urlbar, and is outside of that frame, so we have to manually
        // route clicks here. See see BrowserViewController.ViewToCaptureReaderModeTap
        // TODO: Redo urlbar layout so that we can place this within the frame *if* we decide to keep the reader settings attached to urlbar
        settingsButton = UIButton()
        settingsButton.setTitleColor(BraveUX.BraveOrange, forState: .Normal)
        settingsButton.titleLabel?.font = UIFont.boldSystemFontOfSize(UIFont.systemFontSize() - 1)
        settingsButton.setTitle(Strings.Reader_Mode_Settings, forState: .Normal)
        settingsButton.addTarget(self, action: #selector(ReaderModeBarView.SELtappedSettingsButton), forControlEvents: .TouchUpInside)
        settingsButton.accessibilityLabel = Strings.Reader_Mode_Settings
        addSubview(settingsButton)

        settingsButton.snp_makeConstraints { make in
            make.centerX.centerY.equalTo(self)

        }
        self.backgroundColor = UIColor.whiteColor().colorWithAlphaComponent(1.0)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawRect(rect: CGRect) {
        super.drawRect(rect)
        let context = UIGraphicsGetCurrentContext()
        CGContextSetLineWidth(context!, 0.5)
        CGContextSetRGBStrokeColor(context!, 0.1, 0.1, 0.1, 1.0)
        CGContextSetStrokeColorWithColor(context!, UIColor.grayColor().CGColor)
        CGContextBeginPath(context!)
        CGContextMoveToPoint(context!, 0, frame.height)
        CGContextAddLineToPoint(context!, frame.width, frame.height)
        CGContextStrokePath(context!)
    }

    func SELtappedSettingsButton() {
        delegate?.readerModeBar(self, didSelectButton: .Settings)
    }

}

//extension ReaderModeBarView: Themeable {
//    func applyTheme(themeName: String) {
//        guard let theme = ReaderModeBarViewUX.Themes[themeName] else {
//            log.error("Unable to apply unknown theme \(themeName)")
//            return
//        }
//
//        backgroundColor = theme.backgroundColor
//        buttonTintColor = theme.buttonTintColor!
//    }
//}
