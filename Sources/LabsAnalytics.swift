//
//  LabsAnalytics.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation

public class LabsAnalytics {
    let networkManager: AnalyticsNetworkManager
    var txnQueue: [AnalyticsValue] = []
    let pennkey: String
    
    
    init?(token: String, pennkey: String, url: URL) async {
        self.pennkey = pennkey
        networkManager = AnalyticsNetworkManager(token: token, url: url)
        switch(await networkManager.submit(AnalyticsTxn(pennkey: pennkey, data: []))) {
        case .failure:
            return nil
        default:
            beginPostingAnalytics()
            break;
        }
    }
    
    //THE ENTIRE APP WAITS FOR THIS CALL..........divert to a task but idk how the result is passed then
    func submit(_ data: AnalyticsValue) async -> Result<Any?, Error> {
        return await self.networkManager.submit(AnalyticsTxn(pennkey: self.pennkey, data: [data]))
    }
    
    func scheduleAnalyticsPost(_ data: AnalyticsValue) {
        txnQueue.append(data)
    }
    
    func flushQueue() {
        Task {
            let toSend = self.txnQueue
            let res = await self.networkManager.submit(AnalyticsTxn(pennkey: self.pennkey, data: toSend))
            if case .success = res {
                self.txnQueue.removeAll(where: {val in
                    toSend.contains(where: {$0 == val})
                })
            }
        }
    }
    
    
    func beginPostingAnalytics() {
        let queue = DispatchQueue.global(qos: .background)

        func dispatchEvent() {
            queue.asyncAfter(deadline: .now() + 30) {
                //copied to prevent concurrent modification
                Task {
                    let toSend = self.txnQueue
                    let res = await self.networkManager.submit(AnalyticsTxn(pennkey: self.pennkey, data: toSend))
                    if case .success = res {
                        self.txnQueue.removeAll(where: {val in
                            toSend.contains(where: {$0 == val})
                        })
                    }
                }
                dispatchEvent()
            }
        }

        dispatchEvent() // Start the loop
    }
}
