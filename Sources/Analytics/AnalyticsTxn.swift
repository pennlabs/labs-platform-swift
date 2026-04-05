//
//  AnalyticsTxn.swift
//  
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation
import SwiftData

@Model class AnalyticsTxn: Equatable, Hashable {
    // Penn Mobile Product ID is 1 (from analytics spec)
    var product = 1
    var pennkey: String
    var timestamp: Int
    var data: [AnalyticsValue]
    
    init(pennkey: String, timestamp: Date, data: [AnalyticsValue]) {
        self.pennkey = pennkey
        self.timestamp = Int(timestamp.timeIntervalSince1970)
        self.data = data
    }
    
    
    
    
    static func oldValuesFetchDescriptor(olderThan timestamp: Date) -> FetchDescriptor<AnalyticsTxn> {
        let intStamp = Int(timestamp.timeIntervalSince1970)
        return FetchDescriptor<AnalyticsTxn>(predicate: #Predicate { $0.timestamp < intStamp })
    }
    
    static func allValuesFetchDescriptor() -> FetchDescriptor<AnalyticsTxn> {
        return FetchDescriptor<AnalyticsTxn>()
    }
}

struct StaticAnalyticsTxnDTO: Encodable {
    let id: PersistentIdentifier
    let product = 1
    let pennkey: String
    let timestamp: Int
    let data: [AnalyticsValue]
    
    init(from txn: AnalyticsTxn) {
        self.id = txn.persistentModelID
        self.pennkey = txn.pennkey
        self.timestamp = txn.timestamp
        self.data = txn.data
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = try encoder.container(keyedBy: CodingKeys.self)
        try container.encode(product, forKey: .product)
        try container.encode(pennkey, forKey: .pennkey)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(data, forKey: .data)
        
    }
    
    enum CodingKeys: String, CodingKey {
        case product, pennkey, timestamp, data
    }
}
