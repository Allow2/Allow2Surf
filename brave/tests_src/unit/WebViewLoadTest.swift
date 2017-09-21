/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */
import Foundation
import XCTest
@testable import Client
import Shared

// Timings are too erratic to be used as part of an assertion of success,
// therefore this test is not part of regular test suite

var groupA = ["businessinsider.com", "kotaku.com", "cnn.com"]
var groupB = ["imore.com", "nytimes.com"]

class WebViewLoadTest: XCTestCase {

    func testOpenUrlUsingBraveSchema() {
        expectationForNotification(BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed, object: nil, handler:nil)
        let site = "google.ca"
        let ok = UIApplication.sharedApplication().openURL(
            NSURL(string: "brave://open-url?url=https%253A%252F%252F" + site)!)
        waitForExpectationsWithTimeout(10, handler: nil)
        XCTAssert(ok, "open url failed for site: \(site)")
    }

    func testJSPopupBlockedForNonCurrentWebView() {
        let url = NSURL(string: "http://example.com")

        let webview1 = BraveApp.getCurrentWebView()!
        expectationForNotification(BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed, object: nil, handler:nil)
        webview1.loadRequest(NSURLRequest(URL: url!))

        waitForExpectationsWithTimeout(5) { (error:NSError?) -> Void in
            if let _ = error {}
        }

        expectationForNotification(BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed, object: nil, handler:nil)
        getApp().tabManager.addTabAndSelect(NSURLRequest(URL: NSURL(string: "http://google.ca")!), configuration: WKWebViewConfiguration())
        waitForExpectationsWithTimeout(5) { (error:NSError?) -> Void in
            if let _ = error {}
        }
        let webview2 = BraveApp.getCurrentWebView()!
        assert(webview1 !== webview2)

        for i in ["alert(' ')", "prompt(' ')", "confirm(' ')"] {
            expectationForNotification("JavaScriptPopupBlockedHiddenWebView", object: nil, handler:nil)
            webview1.stringByEvaluatingJavaScriptFromString(i)
            waitForExpectationsWithTimeout(5) { (error:NSError?) -> Void in
                if let _ = error {}
            }
        }
    }


    func testLocationChangeTimeoutHack() {
        // hackerone issue 175958
        let url = NSURL(string: "http://example.com")

        let webview = BraveApp.getCurrentWebView()
        expectationForNotification(BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed, object: nil, handler:nil)
        webview!.loadRequest(NSURLRequest(URL: url!))

        waitForExpectationsWithTimeout(15) { (error:NSError?) -> Void in
            if let _ = error {
            }
        }

        let expect = expectationWithDescription("wait")

        postAsyncToMain(1) {
            webview?.stringByEvaluatingJavaScriptFromString(
                "var timer = 0;" +
                "function f() {location = 'https://facebook.com'};" +
                "timer = setInterval('f()', 10);" +
                "setTimeout(function () { clearInterval(timer) }, 5000);")
        }

        postAsyncToMain(8) {
            //TODO: the url location will flicker as it keeps getting set from facebook to example.com, this is correct,
            // not sure how to assert this behaviour just yet
            expect.fulfill()
        }

        waitForExpectationsWithTimeout(10) { (error:NSError?) -> Void in }

        XCTAssert(webview!.URL!.absoluteString!.contains("facebook"))
    }

    func testTrackingProtection() {
        let urls = ["scorecardresearch.com",
                    "imrworldwide.com",
                    "google-analytics.com",
                    "googletagservices.com",
                    "googlesyndication.com",
                    "quantserve.com",
                    "teads.tv",
                    "netshelter.net",
                    "viglink.com",
                    "bluekai.com",
                    "bkrtx.com",
                    "tubemogul.com",
                    "sitescout.com",]

        for url in urls {
            let req = NSMutableURLRequest(URL: NSURL(string: "http://" + url)!)
            req.mainDocumentURL = NSURL(string: "http://www.example.com")
            let b = TrackingProtection.singleton.shouldBlock(req)
            XCTAssert(b, "TrackingProtection failed: \(url)")
        }
    }

    func testAdblock() {
        let urls = ["teads.tv",
                    "netshelter.net",
                    "tubemogul.com",
                    "sitescout.com",
                    "sharethrough.com",]

        for url in urls {
            let req = NSMutableURLRequest(URL: NSURL(string: "http://" + url)!)
            req.mainDocumentURL = NSURL(string: "http://www.example.com")
            let b = AdBlocker.singleton.shouldBlock(req)
            XCTAssert(b)
        }
    }
}
