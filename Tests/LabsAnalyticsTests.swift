//
//  LabsAnalyticsTests.swift
//  LabsAnalyticsTests
//
//  Created by Jonathan Melitski on 11/25/24.
//

import XCTest
@testable import LabsPlatformSwift

final class LabsAnalyticsTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
        
        let txn: AnalyticsTxn = AnalyticsTxn(pennkey: "melitski", data: [])
        let val = try JSONEncoder().encode(txn)
        let str = String(data: val, encoding: .utf8)
        print("\(str)")
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
