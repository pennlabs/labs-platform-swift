//
//  LabsPlatformDelegateTests.swift
//  LabsPlatformSwiftTests
//

import XCTest
@testable import LabsPlatformSwift

@MainActor
final class LabsPlatformDelegateTests: XCTestCase {

    /// A delegate that implements nothing, to exercise the protocol's default implementations.
    private final class EmptyDelegate: LabsPlatformDelegate { }

    func testDefaultRefreshPolicyStaysLoggedInWithoutConnection() {
        XCTAssertEqual(RefreshFlowFailedResult.default(for: PlatformAuthError.noConnection), .stayLoggedIn)
    }

    func testDefaultRefreshPolicyStaysLoggedInOnDecodingError() {
        let error = DecodingError.valueNotFound(String.self, .init(codingPath: [], debugDescription: ""))
        XCTAssertEqual(RefreshFlowFailedResult.default(for: error), .stayLoggedIn)
    }

    func testDefaultRefreshPolicyLogsOutOnRejectedSession() {
        XCTAssertEqual(RefreshFlowFailedResult.default(for: PlatformAuthError.invalidSession), .logOut)
        XCTAssertEqual(RefreshFlowFailedResult.default(for: PlatformError.notLoggedIn), .logOut)
    }

    func testDelegateDefaultsPreserveExistingBehavior() {
        let platform = LabsPlatform(clientId: "test", redirectUrl: "labs://test", configuration: .init(analyticsConfiguration: nil))
        let delegate = EmptyDelegate()

        XCTAssertTrue(delegate.labsPlatformAuth(didReceiveDefaultLoginCredentials: (username: "root", password: "root"), platform: platform))
        XCTAssertEqual(delegate.labsPlatformAuth(refreshFlowFailedWithError: PlatformAuthError.invalidSession, platform: platform), .logOut)

        var request = URLRequest(url: URL(string: "https://platform.pennlabs.org/accounts/me/")!)
        request.setValue("value", forHTTPHeaderField: "X-Test")
        XCTAssertEqual(delegate.labsPlatformRequests(willSendRequest: request, platform: platform), request)
    }
}
