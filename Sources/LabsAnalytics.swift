//
//  LabsAnalytics.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation

public final class LabsAnalytics: ObservableObject {
    private let pennkey: String
    let networkManager: AnalyticsNetworkManager
    
    
    
    public init(token: String, pennkey: String, url: URL) {
        self.pennkey = pennkey
        
        networkManager = AnalyticsNetworkManager(token: token, pennkey: pennkey, url: url)
    }
    
    
    func send(_ value: AnalyticsValue) {
        self.networkManager.submitValue(value)
    }
    
    
    
    
    
}
