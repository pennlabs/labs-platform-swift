//
//  LabsPlatformAuth.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 1/31/25.
//

import Foundation
import SwiftUI
import AuthenticationServices

// MARK: Login
extension LabsPlatform {
    /// Starts the interactive Platform login. Does nothing while a login is already in progress.
    /// - Tag: loginWithPlatform
    public func loginWithPlatform() {
        guard loginTask == nil else { return }
        loginTask = Task {
            defer { loginTask = nil }
            await performLogin()
        }
    }

    /// Logs out, discards cached credentials and cookies, and cancels any in-flight login or refresh.
    /// The delegate always receives `labsPlatformAuth(didUpdateLoggedInState:platform:)` with `loggedIn == false`.
    /// - Tag: logoutPlatform
    public func logoutPlatform() {
        loginTask?.cancel()
        refreshTask?.cancel()
        UserDefaults.standard.clearPlatformHTTPCookies()
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        authState = .loggedOut
    }

    private func performLogin() async {
        globalLoading = true
        guard await platformIsReachable() else {
            globalLoading = false
            failLogin(with: PlatformAuthError.noConnection)
            return
        }
        globalLoading = false

        do {
            let (url, state, verifier) = try prepareLogin()
            authState = .newLogin(url: url, state: state, verifier: verifier)
            let callback = try await authenticate(at: url)
            try Task.checkCancellation()

            switch try parseCallback(callback, expectedState: state) {
            case .defaultLogin:
                let credentials = (username: configuration.defaultAccount, password: configuration.defaultPassword)
                let accepted = delegate?.labsPlatformAuth(didReceiveDefaultLoginCredentials: credentials, platform: self) ?? true
                authState = accepted ? .loggedIn(auth: .defaultValue) : .loggedOut
            case .authorizationCode(let code):
                authState = .codeAcquired(result: AuthCompletionResult(authCode: code, state: state), verifier: verifier)
                authState = .loggedIn(auth: try await fetchToken(authorizationCode: code, verifier: verifier))
            }
        } catch is CancellationError {
            authState = .loggedOut
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            authState = .loggedOut
        } catch {
            failLogin(with: error)
        }
    }

    private func platformIsReachable() async -> Bool {
        (try? await URLSession.shared.data(for: URLRequest(url: configuration.authEndpoint))) != nil
    }

    private func prepareLogin() throws -> (url: URL, state: String, verifier: String) {
        let verifier = AuthUtilities.codeVerifier()
        let state = AuthUtilities.stateString()
        let query = "response_type=code&code_challenge=\(AuthUtilities.codeChallenge(from: verifier))&code_challenge_method=S256&client_id=\(clientId)&redirect_uri=\(authRedirect)&scope=openid%20read%20introspection&state=\(state)"
        guard let url = URL(string: "\(configuration.authEndpoint.absoluteString)?\(query)") else {
            throw PlatformAuthError.invalidUrl
        }
        return (url, state, verifier)
    }

    private func authenticate(at url: URL) async throws -> URL {
        guard let session = webAuthenticationSession, let scheme = URL(string: authRedirect)?.scheme else {
            throw PlatformAuthError.illegalState
        }
        return try await session.authenticate(using: url, callback: .customScheme(scheme), additionalHeaderFields: [:])
    }

    private func parseCallback(_ url: URL, expectedState: String) throws -> LoginCallback {
        guard let items = URLComponents(string: url.absoluteString)?.queryItems else {
            throw PlatformAuthError.invalidCallback
        }
        if items.first(where: { $0.name == "defaultlogin" })?.value == "true" {
            return .defaultLogin
        }
        if items.contains(where: { $0.name == "error" }) {
            throw PlatformAuthError.authorizationDenied
        }
        guard let code = items.first(where: { $0.name == "code" })?.value,
              items.first(where: { $0.name == "state" })?.value == expectedState else {
            throw PlatformAuthError.invalidCallback
        }
        return .authorizationCode(code)
    }

    private func failLogin(with error: any Error) {
        delegate?.labsPlatformAuth(loginFlowFailedWithError: PlatformAuthFlowError(error), platform: self)
        authState = .loggedOut
    }
}

private enum LoginCallback {
    case authorizationCode(String)
    case defaultLogin
}

// MARK: Refresh
extension LabsPlatform {
    func getCurrentAuthState() -> PlatformAuthState {
        let credential: PlatformAuthCredentials?
        switch authState {
        case .loggedIn(let auth), .needsRefresh(let auth):
            credential = auth
        default:
            credential = LabsKeychain.loadPlatformCredential()
        }
        guard let credential else { return .loggedOut }
        let expired = credential.issuedAt.addingTimeInterval(TimeInterval(credential.expiresIn)) < .now
        return expired ? .needsRefresh(auth: credential) : .loggedIn(auth: credential)
    }

    /// Refreshes an expired credential, sharing one in-flight refresh between concurrent callers.
    /// Skips the network entirely while the device is offline.
    func getRefreshedAuthState() async -> PlatformAuthState {
        if refreshTask == nil, case .needsRefresh(let auth) = getCurrentAuthState(), isNetworkAvailable {
            refreshTask = Task {
                defer { refreshTask = nil }
                let result = await refresh(auth)
                switch authState {
                case .loggedIn(auth), .needsRefresh(auth):
                    authState = result
                default:
                    break
                }
            }
        }
        await refreshTask?.value
        return getCurrentAuthState()
    }

    private func refresh(_ auth: PlatformAuthCredentials) async -> PlatformAuthState {
        for attempt in 1...Self.maxRefreshAttempts {
            do {
                let credential = try await refreshToken(auth)
                return Task.isCancelled ? .loggedOut : .loggedIn(auth: credential)
            } catch {
                guard !Task.isCancelled else { return .loggedOut }
                let flowError = PlatformAuthFlowError(error)
                switch delegate?.labsPlatformAuth(refreshFlowFailedWithError: flowError, platform: self) ?? .default(for: flowError) {
                case .stayLoggedIn:
                    return .needsRefresh(auth: auth)
                case .logOut:
                    return .loggedOut
                case .tryAgain:
                    try? await Task.sleep(for: .seconds(attempt))
                }
            }
        }
        return .loggedOut
    }
}

// MARK: Token Requests
extension LabsPlatform {
    func fetchToken(authorizationCode: String, verifier: String) async throws -> PlatformAuthCredentials {
        let request = tokenRequest(
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: authorizationCode),
            URLQueryItem(name: "redirect_uri", value: authRedirect),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code_verifier", value: verifier))
        return try await sendTokenRequest(request)
    }

    func refreshToken(_ auth: PlatformAuthCredentials) async throws -> PlatformAuthCredentials {
        let request = tokenRequest(
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: auth.refreshToken),
            URLQueryItem(name: "client_id", value: clientId))
        delegate?.labsPlatformAuth(willPerformRefreshRequest: request, platform: self)

        let refreshed = try await sendTokenRequest(request)
        guard refreshed.idToken == nil else { return refreshed }
        return PlatformAuthCredentials(
            accessToken: refreshed.accessToken,
            expiresIn: refreshed.expiresIn,
            tokenType: refreshed.tokenType,
            refreshToken: refreshed.refreshToken,
            idToken: auth.idToken,
            issuedAt: refreshed.issuedAt)
    }

    private func tokenRequest(_ fields: URLQueryItem...) -> URLRequest {
        var components = URLComponents()
        components.queryItems = fields
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        return request
    }

    private func sendTokenRequest(_ request: URLRequest) async throws -> PlatformAuthCredentials {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw PlatformAuthError.noConnection
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw PlatformAuthError.invalidSession
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PlatformAuthCredentials.self, from: data)
    }
}

// MARK: Platform Debug Options
extension LabsPlatform {
    public func debugForceRefresh() {
        guard let token = LabsKeychain.loadPlatformCredential() else {
            return
        }

        let newToken = PlatformAuthCredentials(accessToken: token.accessToken,
                                               expiresIn: token.expiresIn,
                                               tokenType: token.tokenType,
                                               refreshToken: token.refreshToken,
                                               idToken: token.idToken,
                                               issuedAt: Date.distantPast)
        LabsKeychain.savePlatformCredential(newToken)
        self.authState = .loggedIn(auth: newToken)
    }
}

// MARK: Auth Models
struct PlatformAuthLoadingView: View {
    var body: some View {
        VStack(alignment: .center) {
            Text("Penn Labs")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Loading your account details...")
                .italic()
            ProgressView()
        }
    }
}


struct PlatformAuthCredentials: Codable, Equatable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String
    let refreshToken: String
    let idToken: String?
    let issuedAt: Date

    init(accessToken: String, expiresIn: Int, tokenType: String, refreshToken: String, idToken: String?, issuedAt: Date) {
        self.tokenType = tokenType
        self.idToken = idToken
        self.accessToken = accessToken
        self.expiresIn = expiresIn
        self.issuedAt = issuedAt
        self.refreshToken = refreshToken
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accessToken = try container.decode(String.self, forKey: .accessToken)
        self.expiresIn = try container.decode(Int.self, forKey: .expiresIn)
        self.tokenType = try container.decode(String.self, forKey: .tokenType)
        self.refreshToken = try container.decode(String.self, forKey: .refreshToken)
        self.idToken = try? container.decode(String.self, forKey: .idToken)

        // IssuedAt time calculated this way because an auth credential can also be decoded from Keychain
        // and doing so would cause the date to change. This way, we use the date in the struct unless it doesn't exist.
        self.issuedAt = (try? container.decode(Date.self, forKey: .issuedAt)) ?? Date.now
    }

    static let defaultValue: PlatformAuthCredentials = .init(
        accessToken: "root",
        expiresIn: 2592000, // 30 days
        tokenType: "Bearer",
        refreshToken: "123456789",
        idToken: "",
        issuedAt: Date.now
    )
}

enum PlatformAuthState: Equatable, CustomDebugStringConvertible, Sendable {
    var debugDescription: String {
        switch self {
        case .idle:
            "Idle"
        case .loggedOut:
            "Logged Out"
        case .newLogin:
            "Starting new login"
        case .codeAcquired:
            "Acquired authorization code"
        case .refreshing:
            "Refreshing access token"
        case .needsRefresh:
            "Current access token expired, needs refresh"
        case .loggedIn:
            "Logged in"
        }
    }

    static func == (lhs: PlatformAuthState, rhs: PlatformAuthState) -> Bool {
        return lhs.debugDescription == rhs.debugDescription
    }

    case idle
    case loggedOut
    case newLogin(url: URL, state: String, verifier: String)
    case codeAcquired(result: AuthCompletionResult, verifier: String)
    case refreshing(state: String)
    case needsRefresh(auth: PlatformAuthCredentials)
    case loggedIn(auth: PlatformAuthCredentials)
}

public enum PlatformAuthError: Int, LocalizedError, Sendable {
    case invalidUrl = 0
    case invalidCallback = 1
    case illegalState = 2
    case authTimeout = 3
    case invalidSession = 4
    case noConnection = 5
    /// Platform redirected back with an `error` query item (consent denied or client misconfigured).
    case authorizationDenied = 6

    public var errorDescription: String? {
        switch self {
        case .invalidUrl, .illegalState:
            "The Penn Labs Platform login could not be started."
        case .invalidCallback:
            "The Penn Labs Platform returned an invalid login response."
        case .authTimeout:
            "The Penn Labs Platform login timed out."
        case .invalidSession:
            "Your Penn Labs Platform session is no longer valid."
        case .noConnection:
            "Unable to connect to the Penn Labs Platform. Are you connected to the internet?"
        case .authorizationDenied:
            "Unable to login to the Penn Labs Platform. Check your client configuration and try again."
        }
    }
}

struct AuthCompletionResult {
    let authCode: String
    let state: String
}
