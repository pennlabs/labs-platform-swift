//
//  AnalyticsProperty.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import SwiftUI

@propertyWrapper
public struct TrackLabsAnalytics: View {
    public var wrappedValue: any View
    @EnvironmentObject var analytics: LabsAnalytics
    @Environment(\.labsAnalyticsPath) var path: String
    let subkey: String
    
    public var body: some View {
        AnyView(wrappedValue)
            .environment(\.labsAnalyticsPath, "\(path).\(subkey)")
    }
    
}
