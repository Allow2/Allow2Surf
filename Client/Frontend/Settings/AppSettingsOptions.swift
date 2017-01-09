/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

import SwiftKeychainWrapper
import LocalAuthentication
import Allow2

// This file contains all of the settings available in the main settings screen of the app.

private var ShowDebugSettings: Bool = false
private var DebugSettingsClickCount: Int = 0

// For great debugging!
class HiddenSetting: Setting {
    let settings: SettingsTableViewController

    init(settings: SettingsTableViewController) {
        self.settings = settings
        super.init(title: nil)
    }

    override var hidden: Bool {
        return !ShowDebugSettings
    }
}


class DeleteExportedDataSetting: HiddenSetting {
    override var title: NSAttributedString? {
        // Not localized for now.
        return NSAttributedString(string: "Debug: delete exported databases", attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor])
    }

    override func onClick(navigationController: UINavigationController?) {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0]
        let fileManager = NSFileManager.defaultManager()
        do {
            let files = try fileManager.contentsOfDirectoryAtPath(documentsPath)
            for file in files {
                if file.startsWith("browser.") || file.startsWith("logins.") {
                    try fileManager.removeItemInDirectory(documentsPath, named: file)
                }
            }
        } catch {
            print("Couldn't delete exported data: \(error).")
        }
    }
}

class ExportBrowserDataSetting: HiddenSetting {
    override var title: NSAttributedString? {
        // Not localized for now.
        return NSAttributedString(string: "Debug: copy databases to app container", attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor])
    }

    override func onClick(navigationController: UINavigationController?) {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0]
        do {
            let log = Logger.syncLogger
            try self.settings.profile.files.copyMatching(fromRelativeDirectory: "", toAbsoluteDirectory: documentsPath) { file in
                log.debug("Matcher: \(file)")
                return file.startsWith("browser.") || file.startsWith("logins.")
            }
        } catch {
            print("Couldn't export browser data: \(error).")
        }
    }
}

// Opens the the license page in a new tab
class LicenseAndAcknowledgementsSetting: Setting {
    override var url: NSURL? {
        return NSURL(string: WebServer.sharedInstance.URLForResource("license", module: "about"))
    }

    override func onClick(navigationController: UINavigationController?) {
        setUpAndPushSettingsContentViewController(navigationController)
    }
}

// Opens the on-boarding screen again
class ShowIntroductionSetting: Setting {
    let profile: Profile

    init(settings: SettingsTableViewController) {
        self.profile = settings.profile
        super.init(title: NSAttributedString(string: Strings.ShowTour, attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor]))
    }

    override func onClick(navigationController: UINavigationController?) {
        navigationController?.dismissViewControllerAnimated(true, completion: {
            if let appDelegate = UIApplication.sharedApplication().delegate as? AppDelegate {
                appDelegate.browserViewController.presentIntroViewController(true)
            }
        })
    }
}

// Opens the search settings pane
class SearchSetting: Setting {
    let profile: Profile

    override var accessoryType: UITableViewCellAccessoryType { return .DisclosureIndicator }

    override var style: UITableViewCellStyle { return .Value1 }

    override var status: NSAttributedString { return NSAttributedString(string: profile.searchEngines.defaultEngine.shortName) }

    override var accessibilityIdentifier: String? { return "Search" }

    init(settings: SettingsTableViewController) {
        self.profile = settings.profile
        super.init(title: NSAttributedString(string: Strings.DefaultSearchEngine, attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor]))
    }

    override func onClick(navigationController: UINavigationController?) {
        let viewController = SearchSettingsTableViewController()
        viewController.model = profile.searchEngines
        navigationController?.pushViewController(viewController, animated: true)
    }
}

class LoginsSetting: Setting {
    let profile: Profile
    ///var tabManager: TabManager!
    weak var navigationController: UINavigationController?

    override var accessoryType: UITableViewCellAccessoryType { return .DisclosureIndicator }

    override var accessibilityIdentifier: String? { return "Logins" }

    init(settings: SettingsTableViewController, delegate: SettingsDelegate?) {
        self.profile = settings.profile
        ///self.tabManager = settings.tabManager
        self.navigationController = settings.navigationController

        let loginsTitle = Strings.Logins
        super.init(title: NSAttributedString(string: loginsTitle, attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor]),
                   delegate: delegate)
    }

    private func navigateToLoginsList() {
        let viewController = LoginListViewController(profile: profile)
        viewController.settingsDelegate = delegate
        navigationController?.pushViewController(viewController, animated: true)
    }
}


class ClearPrivateDataSetting: Setting {
    let profile: Profile
    //var tabManager: TabManager!

    override var accessoryType: UITableViewCellAccessoryType { return .DisclosureIndicator }

    override var accessibilityIdentifier: String? { return "ClearPrivateData" }

    init(settings: SettingsTableViewController) {
        self.profile = settings.profile
        //self.tabManager = settings.tabManager

        let clearTitle = Strings.ClearPrivateData
        super.init(title: NSAttributedString(string: clearTitle, attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor]))
    }

    override func onClick(navigationController: UINavigationController?) {
        let viewController = ClearPrivateDataTableViewController()
        viewController.profile = profile
        //viewController.tabManager = tabManager
        navigationController?.pushViewController(viewController, animated: true)
    }
}

class Allow2Setting: Setting {
    let profile: Profile
    //var tabManager: TabManager!
    
    override var accessoryType: UITableViewCellAccessoryType { return .DisclosureIndicator }
    
    override var accessibilityIdentifier: String? { return "SetupAllow2" }
    
    init(settings: SettingsTableViewController) {
        self.profile = settings.profile
        
        let allow2Title = "Allow2"
        super.init(title: NSAttributedString(string: allow2Title, attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor]))
    }
    
    override func onClick(navigationController: UINavigationController?) {
        /*let viewController = */
        //viewController.profile = profile
        //viewController.tabManager = tabManager
        //navigationController?.pushViewController(viewController, animated: true)
        
        if Allow2.sharedInstance.isPaired {
            let alert = UIAlertController(title: "Paired", message: "Once paired with Allow2, Brave can only be unpaired by the controlling account by logging in to the Allow2 web portal.", preferredStyle: .Alert)
            alert.addAction(UIAlertAction(title: "OK", style: .Cancel) { (action) in })
            navigationController?.presentViewController(alert, animated: true, completion: nil)
            return
        }
        
        pairWithAllow2(navigationController)
        
    }
    
    func pairWithAllow2(navigationController: UINavigationController?) {
        let alert = UIAlertController(title: "Pair with Allow2", message: "Enter Details", preferredStyle: .Alert)
        alert.addTextFieldWithConfigurationHandler({(textField: UITextField!) in
            textField.placeholder = "Username"
            textField.secureTextEntry = false
        })
        alert.addTextFieldWithConfigurationHandler({(textField: UITextField!) in
            textField.placeholder = "Password"
            textField.secureTextEntry = true
        })
        alert.addTextFieldWithConfigurationHandler({(textField: UITextField!) in
            textField.placeholder = "Device Name"
            textField.secureTextEntry = false
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .Cancel) { (action) in
            })
        alert.addAction(UIAlertAction(title: "Pair", style: .Default, handler:{ (action) in
            let user = (alert.textFields![0] as UITextField).text!.stringByTrimmingCharactersInSet(.whitespaceAndNewlineCharacterSet())
            let password = (alert.textFields![1] as UITextField).text!
            let deviceName = (alert.textFields![2] as UITextField).text!.stringByTrimmingCharactersInSet(.whitespaceAndNewlineCharacterSet())
            
            guard (user.characters.count > 0) && (password.characters.count > 0) && (deviceName.characters.count > 0) else {
                print("Cancelled")
                return
            }
            
            UIApplication.sharedApplication().beginIgnoringInteractionEvents()
            UIApplication.sharedApplication().networkActivityIndicatorVisible = true
            Allow2.sharedInstance.pair(user, password: password, deviceName: deviceName) { (res) in
                print("paired")
                UIApplication.sharedApplication().endIgnoringInteractionEvents()
                UIApplication.sharedApplication().networkActivityIndicatorVisible = false
            }
        }))
        navigationController?.presentViewController(alert, animated: true, completion: nil)
    }
    
}


class PrivacyPolicySetting: Setting {
    override var title: NSAttributedString? {
        return NSAttributedString(string: Strings.Privacy_Policy, attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor])
    }

    override var url: NSURL? {
        return NSURL(string: "https://www.brave.com/ios_privacy.html")
    }

    override func onClick(navigationController: UINavigationController?) {
        setUpAndPushSettingsContentViewController(navigationController)
    }
}

