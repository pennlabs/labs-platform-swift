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


// TODO: Another concern is that of concurrency when I go to add analytics. Should something be an actor here?


public final class LabsPlatform: ObservableObject {
    public static let authEndpoint = URL(string: "https://platform.pennlabs.org/accounts/authorize")!
    public static let tokenEndpoint = URL(string: "https://platform.pennlabs.org/accounts/token/")!
    
    @Published var authState: PlatformAuthState = .loggedOut
    let clientId: String
    let redirectUrl: URL
    
    public init(clientId: String, redirectUrl: URL) {
        // get initial state from cache
        self.clientId = clientId
        self.redirectUrl = redirectUrl
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
            // TODO: May need to change when I implement a guest mode
            platform.authState = new ? platform.authState : .loggedOut
        }
        
        content()
            .environmentObject(platform)
            .sheet(isPresented: showSheet) {
                AuthWebView(platform: platform)
            }
    }
}

public extension View {
    func enableLabsPlatform(clientId: String, redirectUrl: URL) -> some View {
        return PlatformProvider(clientId: clientId, redirectUrl: redirectUrl) {
            self
        }
    }
}
