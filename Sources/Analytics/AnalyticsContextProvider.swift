//
//  AnalyticsContextProvider.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import SwiftUI



/*
  
 var body: some View {
 
    AnalyticsContextProvider { context in
        Text("Hello")
            .onTapGesture {
                context.log("text")
            }
    }
 
 
    DiningDetailView()
        .analytics("commons")
 
 }
 
 */

public struct AnalyticsContextProvider<Content: View>: View {
    @EnvironmentObject var analytics: LabsPlatform.Analytics
    @Environment(\.labsAnalyticsPath) var path: String

    public var content: (AnalyticsContext) -> Content
    public let subkey: String

    public init(subkey: String, @ViewBuilder content: @escaping (AnalyticsContext) -> Content) {
        self.content = content
        self.subkey = subkey
    }

    public var body: some View {
        content(AnalyticsContext(analytics: analytics, key: "\(path).\(subkey)"))
    }
}

public extension View {
    private func logViewAnalytics(subkey: String? = nil) -> some View {
        @Environment(\.labsAnalyticsPath) var path: String
        @EnvironmentObject var analytics: LabsPlatform.Analytics
        let key = subkey == nil ? path : "\(path).\(subkey!)"
        return (
            self
                .onAppear {
                    Task {
                        await analytics.record(AnalyticsValue(key: "\(key).appear", value: 1, timestamp: Date.now))
                    }
                }
                .onDisappear {
                    Task {
                        await analytics.record(AnalyticsValue(key: "\(key).disappear", value: 1, timestamp: Date.now))
                    }
                }
        )
    }
    
    
    func analytics(_ subkey: String?, logViewAppearances: Bool) -> some View {
        @Environment(\.labsAnalyticsPath) var path: String
        let key = subkey == nil ? path : "\(path).\(subkey!)"
        let view = logViewAppearances ? self.logViewAnalytics(subkey: key) as! Self : self
        
        return view.environment(\.labsAnalyticsPath, key)
        }
}
