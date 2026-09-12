//
//  LabsPlatformDelegateTests.swift
//  LabsPlatformSwiftTests
//

import XCTest
@testable import LabsPlatformSwift

@MainActor
final class LabsPlatformDelegateTests: XCTestCase {

    private final class RecordingDelegate: LabsPlatformDelegate {
        var loginFailures: [PlatformAuthFlowError] = []
        var states: [(loggedIn: Bool, isDefaultLogin: Bool)] = []

        func labsPlatformAuth(loginFlowFailedWithError error: PlatformAuthFlowError, platform: LabsPlatform) {
            loginFailures.append(error)
        }

        func labsPlatformAuth(didUpdateLoggedInState state: (loggedIn: Bool, isDefaultLogin: Bool), platform: LabsPlatform) {
            states.append(state)
        }
    }

    /// Connection refused immediately.
    private static let refused = URL(string: "http://127.0.0.1:1/")!
    /// Non-routable, so the connection attempt hangs until cancelled.
    private static let blackhole = URL(string: "http://10.255.255.1:1/")!

    private func makePlatform(tokenEndpoint: URL = refused) -> LabsPlatform {
        LabsPlatform(clientId: "test",
                     redirectUrl: "labs://test",
                     configuration: .init(authEndpoint: Self.refused, tokenEndpoint: tokenEndpoint, analyticsConfiguration: nil))
    }

    private let expiredCredential = PlatformAuthCredentials(
        accessToken: "access", expiresIn: 1, tokenType: "Bearer", refreshToken: "refresh", idToken: nil, issuedAt: .distantPast)

    // MARK: Initialization

    func testInitializeSetsShared() {
        LabsPlatform.shared = nil
        let platform = LabsPlatform.initialize(clientId: "test", redirectUrl: "labs://test",
                                               configuration: .init(authEndpoint: Self.refused, tokenEndpoint: Self.refused, analyticsConfiguration: nil))
        XCTAssertTrue(LabsPlatform.shared === platform)
        XCTAssertFalse(platform.createdByViewModifier)
    }

    // MARK: Policies

    func testDefaultRefreshPolicy() {
        let decoding = DecodingError.valueNotFound(String.self, .init(codingPath: [], debugDescription: ""))
        XCTAssertEqual(RefreshFlowFailedResult.default(for: .platformError(.noConnection)), .stayLoggedIn)
        XCTAssertEqual(RefreshFlowFailedResult.default(for: .decodingError(decoding)), .stayLoggedIn)
        XCTAssertEqual(RefreshFlowFailedResult.default(for: .platformError(.invalidSession)), .logOut)
        XCTAssertEqual(RefreshFlowFailedResult.default(for: .other(URLError(.badURL))), .logOut)
    }

    func testAuthFlowErrorClassification() {
        guard case .platformError(.invalidSession) = PlatformAuthFlowError(PlatformAuthError.invalidSession) else { return XCTFail() }
        guard case .decodingError = PlatformAuthFlowError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))) else { return XCTFail() }
        guard case .other = PlatformAuthFlowError(URLError(.badURL)) else { return XCTFail() }
    }

    func testDelegateDefaults() {
        let platform = makePlatform()
        let delegate = RecordingDelegate()

        XCTAssertTrue(delegate.labsPlatformAuth(didReceiveDefaultLoginCredentials: (username: "root", password: "root"), platform: platform))
        XCTAssertEqual(delegate.labsPlatformAuth(refreshFlowFailedWithError: .platformError(.invalidSession), platform: platform), .logOut)
        var request = URLRequest(url: URL(string: "https://platform.pennlabs.org/accounts/me/")!)
        request.setValue("value", forHTTPHeaderField: "X-Test")
        XCTAssertEqual(delegate.labsPlatformRequests(willSendRequest: request, platform: platform), request)
    }

    // MARK: Concurrency

    func testLoginIsNotReentrant() async {
        let platform = makePlatform()
        let delegate = RecordingDelegate()
        platform.delegate = delegate

        platform.loginWithPlatform()
        let first = platform.loginTask
        XCTAssertNotNil(first)
        platform.loginWithPlatform()
        XCTAssertEqual(platform.loginTask, first)

        await first?.value
        XCTAssertNil(platform.loginTask)
        XCTAssertEqual(platform.authState, .loggedOut)
        XCTAssertEqual(delegate.loginFailures.count, 1)
        guard case .platformError(.noConnection) = delegate.loginFailures.first else { return XCTFail() }
    }

    func testLogoutCancelsInFlightRefresh() async {
        let platform = makePlatform(tokenEndpoint: Self.blackhole)
        platform.authState = .loggedIn(auth: expiredCredential)

        let refresh = Task { await platform.getRefreshedAuthState() }
        for _ in 0..<100 where platform.refreshTask == nil {
            await Task.yield()
        }
        XCTAssertNotNil(platform.refreshTask)

        platform.logoutPlatform()
        let result = await refresh.value
        XCTAssertEqual(result, .loggedOut)
        XCTAssertNil(platform.refreshTask)
        XCTAssertEqual(platform.authState, .loggedOut)
    }

    func testOfflineSkipsRefresh() async {
        let platform = makePlatform()
        platform.authState = .loggedIn(auth: expiredCredential)
        platform.isNetworkAvailable = false

        let state = await platform.getRefreshedAuthState()
        XCTAssertEqual(state, .needsRefresh(auth: expiredCredential))
        XCTAssertNil(platform.refreshTask)
        XCTAssertTrue(platform.isLoggedIn)

        do {
            _ = try await platform.authorizedURLRequest(url: URL(string: "https://example.com")!, mode: .accessToken)
            XCTFail("expected refreshUnavailable")
        } catch PlatformError.refreshUnavailable {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
