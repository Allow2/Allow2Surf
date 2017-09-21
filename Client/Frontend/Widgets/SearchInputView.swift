/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import SnapKit
import Shared

private struct SearchInputViewUX {

    static let horizontalSpacing: CGFloat = 16
    static let titleFont: UIFont = UIFont.systemFontOfSize(16)
    static let titleColor: UIColor = UIColor.lightGrayColor()
    static let inputColor: UIColor = UIConstants.HighlightBlue
    static let borderColor: UIColor = UIConstants.SeparatorColor
    static let borderLineWidth: CGFloat = 0.5
    static let closeButtonSize: CGFloat = 36
}

@objc protocol SearchInputViewDelegate: class {

    func searchInputView(searchView: SearchInputView, didChangeTextTo text: String)

    func searchInputViewBeganEditing(searchView: SearchInputView)

    func searchInputViewFinishedEditing(searchView: SearchInputView)
}

class SearchInputView: UIView {

    weak var delegate: SearchInputViewDelegate?

    var showBottomBorder: Bool = false {
        didSet {
            bottomBorder.hidden = !showBottomBorder
        }
    }

    lazy var inputField: UITextField = {
        let textField = UITextField()
        textField.delegate = self
        textField.textColor = SearchInputViewUX.inputColor
        textField.tintColor = SearchInputViewUX.inputColor
        textField.addTarget(self, action: #selector(SearchInputView.SELinputTextDidChange(_:)), forControlEvents: .EditingChanged)
        textField.accessibilityLabel = Strings.Search_Input_Field
        textField.autocorrectionType = .No
        textField.autocapitalizationType = .None
        return textField
    }()

    lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = Strings.Search
        label.font = SearchInputViewUX.titleFont
        label.textColor = SearchInputViewUX.titleColor
        return label
    }()

    lazy var searchIcon: UIImageView = {
        return UIImageView(image: UIImage(named: "quickSearch"))
    }()

    private lazy var closeButton: UIButton = {
        let button = UIButton()
        button.addTarget(self, action: #selector(SearchInputView.SELtappedClose), forControlEvents: .TouchUpInside)
        button.setImage(UIImage(named: "clear"), forState: .Normal)
        button.accessibilityLabel = Strings.Clear_Search
        return button
    }()

    private var centerContainer = UIView()

    private lazy var bottomBorder: UIView = {
        let border = UIView()
        border.backgroundColor = SearchInputViewUX.borderColor
        return border
    }()

    private lazy var overlay: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.whiteColor()
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(SearchInputView.SELtappedSearch)))

        view.isAccessibilityElement = true
        view.accessibilityLabel = Strings.Enter_Search_Mode
        return view
    }()

    private(set) var isEditing = false {
        didSet {
            if isEditing {
                overlay.hidden = true
                inputField.hidden = false
                inputField.accessibilityElementsHidden = false
                closeButton.hidden = false
                closeButton.accessibilityElementsHidden = false
            } else {
                overlay.hidden = false
                inputField.hidden = true
                inputField.accessibilityElementsHidden = true
                closeButton.hidden = true
                closeButton.accessibilityElementsHidden = true
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = UIColor.whiteColor()
        userInteractionEnabled = true

        addSubview(inputField)
        addSubview(closeButton)

        centerContainer.addSubview(searchIcon)
        centerContainer.addSubview(titleLabel)
        overlay.addSubview(centerContainer)
        addSubview(overlay)
        addSubview(bottomBorder)

        setupConstraints()

        setEditing(false)
    }

    private func setupConstraints() {
        centerContainer.snp_makeConstraints { make in
            make.center.equalTo(overlay)
        }

        overlay.snp_makeConstraints { make in
            make.edges.equalTo(self)
        }

        searchIcon.snp_makeConstraints { make in
            make.right.equalTo(titleLabel.snp_left).offset(-SearchInputViewUX.horizontalSpacing)
            make.centerY.equalTo(centerContainer)
        }

        titleLabel.snp_makeConstraints { make in
            make.center.equalTo(centerContainer)
        }

        inputField.snp_makeConstraints { make in
            make.left.equalTo(self).offset(SearchInputViewUX.horizontalSpacing)
            make.centerY.equalTo(self)
            make.right.equalTo(closeButton.snp_left).offset(-SearchInputViewUX.horizontalSpacing)
        }

        closeButton.snp_makeConstraints { make in
            make.right.equalTo(self).offset(-SearchInputViewUX.horizontalSpacing)
            make.centerY.equalTo(self)
            make.size.equalTo(SearchInputViewUX.closeButtonSize)
        }

        bottomBorder.snp_makeConstraints { make in
            make.left.right.bottom.equalTo(self)
            make.height.equalTo(SearchInputViewUX.borderLineWidth)
        }
    }

    // didSet callbacks don't trigger when a property is being set in the init() call 
    // but calling a method that does works fine.
    private func setEditing(editing: Bool) {
        isEditing = editing
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Selectors
extension SearchInputView {

    @objc private func SELtappedSearch() {
        isEditing = true
        inputField.becomeFirstResponder()
        delegate?.searchInputViewBeganEditing(self)
    }

    @objc private func SELtappedClose() {
        isEditing = false
        delegate?.searchInputViewFinishedEditing(self)
        inputField.text = nil
        inputField.resignFirstResponder()
    }

    @objc private func SELinputTextDidChange(textField: UITextField) {
        delegate?.searchInputView(self, didChangeTextTo: textField.text ?? "")
    }
}

// MARK: - UITextFieldDelegate
extension SearchInputView: UITextFieldDelegate {

    func textFieldDidEndEditing(textField: UITextField) {
        // If there is no text, go back to showing the title view
        if (textField.text?.characters.count ?? 0) == 0 {
            isEditing = false
            delegate?.searchInputViewFinishedEditing(self)
        }
    }
}
