//
//  AnalyticsTxn.swift
//  
//
//  Created by Jonathan Melitski on 11/25/24.
//

struct AnalyticsTxn: Codable {
    // Penn Mobile Product ID is 1 (from analytics spec)
    let product = 1
    let pennkey: String
    let data: [AnalyticsValue]
    
    init(pennkey: String, data: [AnalyticsValue]) {
        self.pennkey = pennkey
        self.data = data
    }
}
