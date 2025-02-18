//
//  AnalyticsTxn.swift
//  
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation

struct AnalyticsTxn: Codable, Equatable, Hashable {
    // Penn Mobile Product ID is 1 (from analytics spec)
    let product = 1
    let pennkey: String
    let timestamp: Int
    let data: [AnalyticsValue]
    
    init(pennkey: String, timestamp: Date, data: [AnalyticsValue]) {
        self.pennkey = pennkey
        self.timestamp = Int(timestamp.timeIntervalSince1970)
        self.data = data
    }
    
    
}
