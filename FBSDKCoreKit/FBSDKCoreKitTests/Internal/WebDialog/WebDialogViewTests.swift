/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSDKCoreKit
import TestTools
import XCTest

class WebDialogViewTests: XCTestCase, WebDialogViewDelegate {

  var webView = TestWebView()
  var factory = TestWebViewFactory()
  let frame = CGRect(origin: .zero, size: CGSize(width: 10, height: 10))
  lazy var dialog = FBWebDialogView(frame: frame)
  var delegateDidFailWithErrorWasCalled = false
  var capturedDelegateDidFailError: Error?
  var capturedDidCompleteResults: [String: String]?
  var webDialogViewDidCancelWasCalled = false
  var webDialogViewDidFinishLoadWasCalled = false
  var urlOpener = TestInternalURLOpener()

  override func setUp() {
    super.setUp()

    webView = factory.webView
    FBWebDialogView.configure(withWebViewProvider: factory, urlOpener: urlOpener)
    dialog.delegate = self
  }

  func testCreatingWithDefaults() {
    FBWebDialogView.reset()
    let dialog = FBWebDialogView(frame: .zero)

    XCTAssertNil(
      dialog.webView,
      "Should not have a webview by default"
    )
    XCTAssertNil(
      FBWebDialogView.urlOpener,
      "Should not have a url opener by default"
    )
  }

  func testRequestsWebView() {
    XCTAssertEqual(
      factory.capturedFrame,
      .zero,
      "Should request a webview with a frame of zero"
    )
  }

  func testSetsWebViewAsSubview() {
    XCTAssertNotNil(
      dialog.subviews.first as? TestWebView,
      "Should add the webview from the factory as a subview"
    )
  }

  func testSetsSelfAsNavigationDelegate() {
    guard let delegate = webView.navigationDelegate
    else {
      return XCTFail("Should add a child webview on creation")
    }
    XCTAssertEqual(
      ObjectIdentifier(delegate),
      ObjectIdentifier(dialog),
      "Should set the dialog as the webview's navigation delegate"
    )
  }

  func testActivityIndicatorDefaultState() {
    XCTAssertTrue(
      activityIndicatorView.hidesWhenStopped,
      "The activity indicator view should hide when stopped"
    )
    XCTAssertFalse(
      activityIndicatorView.isAnimating,
      "The activity indicator view should not animate by default"
    )
  }

  func testLoadingURL() {
    dialog.load(SampleURLs.valid)

    XCTAssertEqual(
      webView.capturedRequest,
      URLRequest(url: SampleURLs.valid),
      "Should attempt to load the request in the webview"
    )
    XCTAssertTrue(
      activityIndicatorView.isAnimating,
      "Should start animating the activity indicator during loading"
    )
  }

  func testStopLoadingURL() {
    dialog.load(SampleURLs.valid)
    dialog.stopLoading()

    XCTAssertEqual(
      webView.stopLoadingCallCount,
      1,
      "Stopping the dialog view should stop loading the request in the webview"
    )
    XCTAssertFalse(
      activityIndicatorView.isAnimating,
      "Should stop animating the activity indicator when loading stops"
    )
  }

  func testLayingOutSubviewsWithoutEnoughSpace() {
    dialog.bounds = CGRect(origin: .zero, size: .zero)
    dialog.draw(.zero)
    dialog.layoutSubviews()

    XCTAssertEqual(
      dialog.frame,
      .init(x: 5, y: 5, width: 0, height: 0),
      "Should set the expected frame when layout out subviews"
    )
  }

  func testLayingOutSubviewsWithEnoughSpace() {
    dialog.bounds = CGRect(origin: .zero, size: CGSize(width: 50, height: 50))
    dialog.draw(.zero)
    dialog.layoutSubviews()

    XCTAssertEqual(
      dialog.frame,
      .init(x: -20, y: -20, width: 50, height: 50),
      "Should set the expected frame when layout out subviews"
    )
  }

  // MARK: - Delegate Methods

  func testFailingNavigationWithRecognizedError() {
    dialog.webView(WKWebView(), didFail: nil, withError: SampleError())

    XCTAssertFalse(
      activityIndicatorView.isAnimating,
      "Should stop animating the activity indicator when the navigation fails"
    )
    XCTAssertTrue(
      delegateDidFailWithErrorWasCalled,
      "Should invoke the delegate for an unrecognized error"
    )
    XCTAssertTrue(
      capturedDelegateDidFailError is SampleError,
      "Should propage the error from the failure"
    )
  }

  func testFailingNavigationWithCancellationError() {
    let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
    dialog.webView(WKWebView(), didFail: nil, withError: error)

    XCTAssertFalse(
      delegateDidFailWithErrorWasCalled,
      "Should not invoke the delegate for a cancellation error"
    )
  }

  func testFailingNavigationWithWebKitError() {
    let error = NSError(domain: "WebKitErrorDomain", code: 102, userInfo: nil)
    dialog.webView(WKWebView(), didFail: nil, withError: error)

    XCTAssertFalse(
      delegateDidFailWithErrorWasCalled,
      "Should not invoke the delegate for a webkit error"
    )
  }

  func testDecideNavigationPolicyWithConnectScheme() {
    var policy: WKNavigationActionPolicy?
    dialog.webView(
      WKWebView(),
      decidePolicyFor: TestWebKitNavigationAction(
        stubbedRequest: URLRequest(url: URLs.connectURL)
      )
    ) {
      policy = $0
    }

    XCTAssertEqual(policy, .cancel)
    XCTAssertEqual(capturedDidCompleteResults, [:])
  }

  func testDecideNavigationPolicyWithQueryAndFragment() {
    [
      (URLs.connectURLWithQuery, ["bar": "baz"]),
      (URLs.connectURLWithFragment, ["fragment": ""]),
      (URLs.connectURLWithQueryAndFragment, ["bar": "baz", "fragment": ""])
    ].forEach {
      let (url, expectedResults) = $0
      capturedDidCompleteResults = nil

      var policy: WKNavigationActionPolicy?
      dialog.webView(
        WKWebView(),
        decidePolicyFor: TestWebKitNavigationAction(
          stubbedRequest: URLRequest(url: url)
        )
      ) {
        policy = $0
      }

      XCTAssertEqual(policy, .cancel)
      XCTAssertEqual(capturedDidCompleteResults, expectedResults)
    }
  }

  func testDecideNavigationPolicyWithCancelledUrl() {
    var policy: WKNavigationActionPolicy?
    dialog.webView(
      WKWebView(),
      decidePolicyFor: TestWebKitNavigationAction(
        stubbedRequest: URLRequest(url: URLs.cancelURLWithoutError)
      )
    ) {
      policy = $0
    }

    XCTAssertEqual(policy, .cancel)
    XCTAssertNil(
      capturedDidCompleteResults,
      "Should not pass parameters on deciding the navigation policy of a cancelled url"
    )
    XCTAssertTrue(
      webDialogViewDidCancelWasCalled,
      "Should inform the delegate when a url cancels the navigation"
    )
  }

  func testDecideNavigationPolicyWithCancelledUrlWithError() {
    var policy: WKNavigationActionPolicy?
    dialog.webView(
      WKWebView(),
      decidePolicyFor: TestWebKitNavigationAction(
        stubbedRequest: URLRequest(url: URLs.cancelURLWithError)
      )
    ) {
      policy = $0
    }

    XCTAssertEqual(policy, .cancel)
    XCTAssertNil(
      capturedDidCompleteResults,
      "Should not pass parameters on deciding the navigation policy of a cancelled url"
    )
    XCTAssertTrue(
      delegateDidFailWithErrorWasCalled,
      "Should invoke the delegate with failure when the url is cancelled and contains an error"
    )
    guard
      let error = capturedDelegateDidFailError as NSError?,
      error.domain == "com.facebook.sdk.core",
      error.code == 999
    else {
      return XCTFail("Should create an error from the URL and call the delegate with it")
    }
  }

  func testDecideNavigationPolicyWithActivatedNavigationType() {
    var policy: WKNavigationActionPolicy?
    dialog.webView(
      WKWebView(),
      decidePolicyFor: TestWebKitNavigationAction(
        stubbedRequest: URLRequest(url: SampleURLs.valid),
        navigationType: .linkActivated
      )
    ) {
      policy = $0
    }

    XCTAssertEqual(urlOpener.capturedOpenURL, SampleURLs.valid)
    urlOpener.capturedOpenURLCompletion?(true)
    XCTAssertEqual(
      policy,
      .cancel,
      "Completing with a successful url opening will should set the policy to cancelled"
    )

    policy = nil

    urlOpener.capturedOpenURLCompletion?(false)
    XCTAssertEqual(
      policy,
      .cancel,
      "Completing with a failed url opening will should set the policy to cancelled"
    )
  }

  func testDecideNavigationPolicyWithoutConnectUrlWithoutActivatedNavigationType() {
    var policy: WKNavigationActionPolicy?
    dialog.webView(
      WKWebView(),
      decidePolicyFor: TestWebKitNavigationAction(
        stubbedRequest: URLRequest(url: SampleURLs.valid),
        navigationType: .other
      )
    ) {
      policy = $0
    }

    XCTAssertNil(urlOpener.capturedOpenURL)
    XCTAssertEqual(
      policy,
      .allow,
      "The default navigation policy should be allowed"
    )
  }

  func testDidFinishNavigation() {
    dialog.webView(
      WKWebView(),
      didFinish: nil
    )
    XCTAssertFalse(
      activityIndicatorView.isAnimating,
      "Finishing loading should stop the activity indicator"
    )
    XCTAssertTrue(
      webDialogViewDidFinishLoadWasCalled,
      "Should call the delegate method when loading is finished"
    )
  }

  // MARK: - Helpers

  enum URLs {
    // swiftlint:disable force_unwrapping
    static let connectURL = URL(string: "fbconnect://foo")!
    static let connectURLWithQuery = URL(string: "fbconnect://foo?bar=baz")!
    static let connectURLWithFragment = URL(string: "fbconnect://foo#fragment")!
    static let connectURLWithQueryAndFragment = URL(string: "fbconnect://foo?bar=baz#fragment")!
    static let cancelURLWithoutError = URL(string: "fbconnect://cancel")!
    static let cancelURLWithError = URL(string: "fbconnect://cancel?error_code=999&error_message=anErrorOhNO")!
    // swiftlint:enable force_unwrapping
  }

  var activityIndicatorView: UIActivityIndicatorView {
    guard let loadingIndicator = webView.subviews.first as? UIActivityIndicatorView else {
      fatalError("Should provide an activity indicator view during setup")
    }
    return loadingIndicator
  }

  func webDialogView(
    _ webDialogView: FBWebDialogView,
    didCompleteWithResults results: [String: Any]
  ) {
    capturedDidCompleteResults = results as? [String: String]
  }

  func webDialogView(
    _ webDialogView: FBWebDialogView,
    didFailWithError error: Error
  ) {
    delegateDidFailWithErrorWasCalled = true
    capturedDelegateDidFailError = error
  }

  func webDialogViewDidCancel(_ webDialogView: FBWebDialogView) {
    webDialogViewDidCancelWasCalled = true
  }

  func webDialogViewDidFinishLoad(_ webDialogView: FBWebDialogView) {
    webDialogViewDidFinishLoadWasCalled = true
  }
}
