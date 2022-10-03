// 
//  PayIdTests.swift
//  breadwalletTests
//
//  Created by Adrian Corscadden on 2020-04-28.
//  Copyright © 2020 Breadwinner AG. All rights reserved.
//
//  See the LICENSE file at the project root for license information.
//

import Foundation
import XCTest
@testable import breadwallet

class PayIdTests : XCTestCase {
    
    func testPaymentPathInit() {
        assertIsPayId(address: "GiveDirectly$payid.charity")
        assertIsPayId(address: "test5$payid.test.coinselect.com")
        assertIsPayId(address: "reza$payid.test.coinselect.com")
        assertIsPayId(address: "pay$wietse.com")
        assertIsPayId(address: "john.smith$dev.payid.es")
        assertIsPayId(address: "pay$zochow.ski")
        
        XCTAssertNil(ResolvableFactory.resolver(""))
        XCTAssertNil(ResolvableFactory.resolver("test5payid.test.coinselect.com"))
        XCTAssertNil(ResolvableFactory.resolver("payid.test.coinselect.com"))
        XCTAssertNil(ResolvableFactory.resolver("rAPERVgXZavGgiGv6xBgtiZurirW2yAmY"))
        XCTAssertNil(ResolvableFactory.resolver("unknown"))
        XCTAssertNil(ResolvableFactory.resolver("0x2c4d5626b6559927350db12e50143e2e8b1b9951"))
        XCTAssertNil(ResolvableFactory.resolver("$payid.charity"))
        XCTAssertNil(ResolvableFactory.resolver("payid.charity$"))
    }
    
    func assertIsPayId(address: String) {
        let payID = ResolvableFactory.resolver(address)
        XCTAssertNotNil(payID, "Resolver should not be nil for \(address)")
        XCTAssertTrue(payID!.type == .payId, "Resolver should not be type Payid for \(address)")
    }

    func handleResult(_ result: Result<(String, String?), ResolvableError>, expected: String) {
        switch result {
        case .success(let address):
            XCTAssertTrue(address.0 == expected)
        case .failure(let error):
            XCTFail("message: \(error)")
        }
    }

}
