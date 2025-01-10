//
//  LabsPlatform.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 12/6/24.
//

import Foundation
import AppAuth
import SwiftUI
import UIKit

public class LabsPlatform: ObservableObject {
    public static let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://www.googleapis.com/oauth2/v4/token")!
    
    @Published public var authState: OIDAuthState?
    
    public init() {
        
    }

}



public extension View {
    
    func enableLabsPlatform(clientId: String,
                            redirectURL: URL) -> some View {
        @ObservedObject var labsPlatform = LabsPlatform()
        
        let request: OIDAuthorizationRequest = OIDAuthorizationRequest(configuration: OIDServiceConfiguration(authorizationEndpoint: LabsPlatform.authEndpoint,
                                                                                                              tokenEndpoint: LabsPlatform.tokenEndpoint),
                                                                       clientId: clientId,
                                                                       scopes: ["openid"],
                                                                       redirectURL: redirectURL,
                                                                       responseType: "code",
                                                                       additionalParameters: nil)
        
        
        
        OIDAuthState.authState(byPresenting: request, presenting: UIHostingController(rootView: self)) { state, err in
            guard let authState = state else {
                print("Failed to Authenticate")
                return
            }
            
            labsPlatform.authState = authState
            print("Authenticated.")
        }

        
        return self
            .environmentObject(labsPlatform)
    }
}
