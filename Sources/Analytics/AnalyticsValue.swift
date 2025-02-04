//
//  AnalyticsValue.swift
//  
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation

public struct AnalyticsValue: Codable, Equatable, Sendable {
    let key: String
    let value: Int

    init(key: String, value: Int, timestamp: Date) {
        self.key = key.replacingOccurrences(of: " ", with: "_")
        self.value = value
    }
}
