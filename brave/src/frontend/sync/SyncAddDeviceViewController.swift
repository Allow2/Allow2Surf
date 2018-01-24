/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

enum DeviceType {
    case mobile
    case computer
}

class SyncAddDeviceViewController: UIViewController {
    
    var scrollView: UIScrollView!
    var containerView: UIView!
    var barcodeView: SyncBarcodeView!
    var codewordsView: SyncCodewordsView!
    var modeControl: UISegmentedControl!
    var titleLabel: UILabel!
    var descriptionLabel: UILabel!
    var doneButton: RoundInterfaceButton!
    var enterWordsButton: RoundInterfaceButton!
    var pageTitle: String = Strings.Sync
    var deviceType: DeviceType = .mobile
    
    convenience init(title: String, type: DeviceType) {
        self.init()
        pageTitle = title
        deviceType = type
    }
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = pageTitle
        view.backgroundColor = SyncBackgroundColor
        
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor.white
        containerView.layer.shadowColor = UIColor(rgb: 0xC8C7CC).cgColor
        containerView.layer.shadowRadius = 0
        containerView.layer.shadowOpacity = 1.0
        containerView.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        scrollView.addSubview(containerView)
        
        guard let syncSeed = Sync.shared.syncSeedArray else {
            // TODO: Pop and error
            return
        }

        let qrSyncSeed = Niceware.shared.joinBytes(fromCombinedBytes: syncSeed)
        if qrSyncSeed.isEmpty {
            // Error
            return
        }

        Niceware.shared.passphrase(fromBytes: syncSeed) { (words, error) in
            guard let words = words, error == nil else {
                return
            }

            self.barcodeView = SyncBarcodeView(data: qrSyncSeed)
            self.codewordsView = SyncCodewordsView(data: words)

            self.setupVisuals()
        }
    }
    
    func setupVisuals() {
        containerView.addSubview(barcodeView)
        
        codewordsView.isHidden = true
        containerView.addSubview(codewordsView)
        
        modeControl = UISegmentedControl(items: [Strings.QRCode, Strings.CodeWords])
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.tintColor = BraveUX.BraveOrange
        modeControl.selectedSegmentIndex = 0
        modeControl.addTarget(self, action: #selector(SEL_changeMode), for: .valueChanged)
        containerView.addSubview(modeControl)
        
        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: UIFontWeightSemibold)
        titleLabel.textColor = BraveUX.GreyJ
        titleLabel.text = deviceType == .mobile ? Strings.SyncAddMobile : Strings.SyncAddComputer
        scrollView.addSubview(titleLabel)
        
        descriptionLabel = UILabel()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = UIFont.systemFont(ofSize: 15, weight: UIFontWeightRegular)
        descriptionLabel.textColor = BraveUX.GreyH
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.textAlignment = .center
        descriptionLabel.text = deviceType == .mobile ? Strings.SyncAddMobileDescription : Strings.SyncAddComputerDescription
        scrollView.addSubview(descriptionLabel)
        
        doneButton = RoundInterfaceButton(type: .roundedRect)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle(Strings.Done, for: .normal)
        doneButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: UIFontWeightBold)
        doneButton.setTitleColor(UIColor.white, for: .normal)
        doneButton.backgroundColor = BraveUX.Blue
        doneButton.addTarget(self, action: #selector(SEL_done), for: .touchUpInside)
        scrollView.addSubview(doneButton)
        
        enterWordsButton = RoundInterfaceButton(type: .roundedRect)
        enterWordsButton.translatesAutoresizingMaskIntoConstraints = false
        enterWordsButton.setTitle(Strings.ShowCodeWords, for: .normal)
        enterWordsButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: UIFontWeightSemibold)
        enterWordsButton.setTitleColor(BraveUX.GreyH, for: .normal)
        enterWordsButton.addTarget(self, action: #selector(SEL_showCodewords), for: .touchUpInside)
        scrollView.addSubview(enterWordsButton)
        
        edgesForExtendedLayout = UIRectEdge()
        
        scrollView.snp.makeConstraints { (make) in
            make.edges.equalTo(self.view)
        }
        
        containerView.snp.makeConstraints { (make) in
            make.top.equalTo(44)
            make.width.equalTo(self.scrollView)
            make.height.equalTo(295)
        }
        
        modeControl.snp.makeConstraints { (make) in
            make.top.equalTo(10)
            make.left.equalTo(8)
            make.right.equalTo(-8)
        }
        
        barcodeView.snp.makeConstraints { (make) in
            make.top.equalTo(65)
            make.centerX.equalTo(self.containerView)
            make.size.equalTo(BarcodeSize)
        }
        
        codewordsView.snp.makeConstraints { (make) in
            make.edges.equalTo(self.containerView).inset(UIEdgeInsetsMake(64, 0, 0, 0))
        }
        
        titleLabel.snp.makeConstraints { (make) in
            make.top.equalTo(self.containerView.snp.bottom).offset(30)
            make.centerX.equalTo(self.scrollView)
        }
        
        descriptionLabel.snp.makeConstraints { (make) in
            make.top.equalTo(self.titleLabel.snp.bottom).offset(8)
            make.leftMargin.equalTo(30)
            make.rightMargin.equalTo(-30)
        }
        
        doneButton.snp.makeConstraints { (make) in
            make.top.equalTo(self.descriptionLabel.snp.bottom).offset(30)
            make.centerX.equalTo(self.scrollView)
            make.left.equalTo(16)
            make.right.equalTo(-16)
            make.bottom.equalTo(-16)
            make.height.equalTo(50)
        }
        
        enterWordsButton.snp.makeConstraints { (make) in
            make.top.equalTo(self.doneButton.snp.bottom).offset(8)
            make.centerX.equalTo(self.scrollView)
            //make.bottom.equalTo(-10)
        }
        
        if deviceType == .computer {
            SEL_showCodewords()
        }
    }
    
    func SEL_showCodewords() {
        modeControl.selectedSegmentIndex = 1
        enterWordsButton.isHidden = true
        SEL_changeMode()
    }
    
    func SEL_changeMode() {
        barcodeView.isHidden = (modeControl.selectedSegmentIndex == 1)
        codewordsView.isHidden = (modeControl.selectedSegmentIndex == 0)
    }
    
    func SEL_done() {
        // Re-activate pop gesture in case it was removed
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        
        self.navigationController?.popToRootViewController(animated: true)
    }
}

