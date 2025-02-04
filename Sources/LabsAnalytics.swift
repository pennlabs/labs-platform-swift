//
//  LabsAnalytics.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation


// TODO: Work this into the new LabsPlatform object

public extension LabsPlatform {
    actor Analytics: ObservableObject {
        public static var endpoint: URL = URL(string: "https://platform.pennlabs.org/analytics/")!
        private var queue: [AnalyticsValue] = []

        
        
        func record(_ value: AnalyticsValue) {
            self.queue.append(value)
        }
        
        
        //maybe should be on a different thread
        func recordAndSubmit(_ value: AnalyticsValue) async throws {
            record(value)
            Task {
                await submitQueue()
            }
        }
    }
}

// MARK: Network
extension LabsPlatform.Analytics {
    
    func submitQueue() async {
        guard !queue.isEmpty else { return }

        let toSubmit = queue
        queue.removeAll()

        await withTaskGroup(of: Void.self) { group in
            for value in toSubmit {
                group.addTask {
                    if !(await self.analyticsPostRequest(value)) {
                        await self.record(value)
                    }
                }
            }
            
            
        }
    }
    
    // true = successful submission (failed submissions should go back in the queue)
    private func analyticsPostRequest(_ value: AnalyticsValue) async -> Bool {
        <#implement#>
    }
}
