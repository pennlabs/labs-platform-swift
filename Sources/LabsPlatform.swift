//
//  LabsPlatform.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 12/6/24.
//

import Foundation
import SwiftUI
import UIKit

// TODO: Labs Platform should not be conditionally intialized, it should instead support a state that is non-logged in, whose functions (that require login) descriptively fail when in guest mode.

// TODO: As far as prompting a login goes, we know that LabsPlatform will exist in the environment of all its subviews. As a result, I've exposed a loginWithPlatform function (currently the exact same as the privately-implemented version, but could be different), and just say that guest mode is where this call does not take place.

// TODO: Write real docs (without using TODO:)

/*
 
 View {
    Subview()
 }
 .enableLabsPlatform(clientId: "...", redirectUrl: URL(...))
 
-------- Subview.swift
 
 @EnvironmentObject var platform: LabsPlatform
 
 Text("Log in with Pennkey")
    .onTapGesture {
        platform.loginWithPlatform()
    }
 
--------
 
 */

// pennlabs-platform://pennmobile/auth

@MainActor
public final class LabsPlatform: ObservableObject {
    public static var authEndpoint = URL(string: "https://platform.pennlabs.org/accounts/authorize")!
    public static var tokenEndpoint = URL(string: "https://platform.pennlabs.org/accounts/token/")!

    public private(set) static var shared: LabsPlatform?
    @Published var analytics: Analytics
    @Published var authState: PlatformAuthState = .loggedOut
    let clientId: String
    let authRedirect: String
    
    public init(clientId: String, redirectUrl: URL) {
        // get initial state from cache
        self.clientId = clientId
        self.authRedirect = redirectUrl.absoluteString
        self.analytics = Analytics()
        self.authState = getCurrentAuthState()
        LabsPlatform.shared = self
    }
    
}

struct PlatformProvider<Content: View>: View {
    @ObservedObject var platform: LabsPlatform
    var content: () -> Content
    
    init(clientId: String, redirectUrl: URL, content: @escaping () -> Content) {
        self.platform = LabsPlatform(clientId: clientId, redirectUrl: redirectUrl)
        self.content = content
        
    }

    var body: some View {
        let showSheet = Binding { platform.authState.showWebViewSheet } set: { new in
            if platform.authState.showWebViewSheet {
                platform.authState = new ? platform.authState : .loggedOut
            }
        }
        
        content()
            .environmentObject(platform.analytics)
            .sheet(isPresented: showSheet) {
                if case .newLogin(let url, _, _) = platform.authState {
                    AuthWebView(url: url, redirect: platform.authRedirect, callback: platform.handleCallback)
                } else {
                    PlatformAuthLoadingView()
                }
            }
    }
}

public extension View {
    /// Enables Labs Platform for all subviews.
    ///
    /// > Note: This should be called on the highest SwiftUI View in the view hierarchy, regardless of whether there is a guest mode or not.
    /// > That is, call this method at the highest view in the viewport, then at the time of login, call [`LabsPlatform.loginWithPlatform()`](x-source-tag://loginWithPlatform)
    ///
    /// - Parameters:
    ///     - clientId: A Platform-granted clientId that has permission to get JWTs
    ///     - redirectUrl: A valid redirect URI (allowed by the Platform application)
    ///
    /// - Returns: The original view with a `LabsPlatform.Analytics` environment object. The  `LabsPlatform` instance can be accessed as a singleton: `LabsPlatform.instance`.
    /// - Tag: enableLabsPlatform
    func enableLabsPlatform(clientId: String, redirectUrl: URL) -> some View {
        return PlatformProvider(clientId: clientId, redirectUrl: redirectUrl) {
            self
        }
    }
}
