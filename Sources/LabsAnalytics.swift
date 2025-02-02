//
//  LabsAnalytics.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation


// TODO: Work this into the new LabsPlatform object
public final class LabsAnalytics: ObservableObject {
    private let pennkey: String
    private let networkManager: AnalyticsNetworkManager
    public let submitQueue: () async throws -> Void
    
    public init?(token: String, pennkey: String, url: URL) async {
        self.pennkey = pennkey
        
        networkManager = AnalyticsNetworkManager(token: token, pennkey: pennkey, url: url)
        
        do {
            try await networkManager.submit()
        } catch {
            return nil
        }
        
        submitQueue = networkManager.submit
    }
    
    
    
    func record(_ value: AnalyticsValue) {
        self.networkManager.addValue(value)
    }
    
    func recordAndSubmit(_ value: AnalyticsValue) async throws {
        record(value)
        try await networkManager.submit()
    }
}
