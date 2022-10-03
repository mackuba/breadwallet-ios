// 
//  RequestUrlTests.swift
//  breadwalletTests
//
//  Created by Adrian Corscadden on 2019-10-06.
//  Copyright © 2019 Breadwinner AG. All rights reserved.
//
//  See the LICENSE file at the project root for license information.
//

import XCTest
@testable import breadwallet

class RequestUrlTests : XCTestCase {

    //MARK: Without Amounts
    func testBTCLegacyUri() {
        let address = "12A1MyfXbW6RhdRAZEqofac5jCQQjwEPBu"
        let uri = TestCurrencies.btc.addressURI(address)
        XCTAssertNotNil(uri)
        XCTAssertEqual(uri, "bitcoin:12A1MyfXbW6RhdRAZEqofac5jCQQjwEPBu")
    }
    
    func testBTCSegwitUri() {
        let address = "bc1qgu4y0m03kerspt2vzgr8aysplxvuasrxpyejer"
        let uri = TestCurrencies.btc.addressURI(address)
        XCTAssertNotNil(uri)
        XCTAssertEqual(uri, "bitcoin:bc1qgu4y0m03kerspt2vzgr8aysplxvuasrxpyejer")
    }
    
    func testEthUri() {
        let address = "0xbDFdAd139440D2Db9BA2aa3B7081C2dE39291508"
        let uri = TestCurrencies.eth.addressURI(address)
        XCTAssertNotNil(uri)
        XCTAssertEqual(uri, "ethereum:0xbDFdAd139440D2Db9BA2aa3B7081C2dE39291508")
    }
    
    //MARK: With Amounts
    func testBTCLegacyUriWithAmount() {
        let address = "12A1MyfXbW6RhdRAZEqofac5jCQQjwEPBu"
        let amount = Amount(tokenString: "1", currency: TestCurrencies.btc)
        let uri = PaymentRequest.requestString(withAddress: address, forAmount: amount)
        XCTAssertNotNil(uri)
        XCTAssertEqual(uri, "bitcoin:12A1MyfXbW6RhdRAZEqofac5jCQQjwEPBu?amount=1")
    }
    
    func testBTCSegwitUriWithAmount() {
        let address = "bc1qgu4y0m03kerspt2vzgr8aysplxvuasrxpyejer"
        let amount = Amount(tokenString: "1", currency: TestCurrencies.btc)
        let uri = PaymentRequest.requestString(withAddress: address, forAmount: amount)
        XCTAssertNotNil(uri)
        XCTAssertEqual(uri, "bitcoin:bc1qgu4y0m03kerspt2vzgr8aysplxvuasrxpyejer?amount=1")
    }

    func testEthUriWithAmount() {
        let address = "0xbDFdAd139440D2Db9BA2aa3B7081C2dE39291508"
        let amount = Amount(tokenString: "1", currency: TestCurrencies.eth)
        let uri = PaymentRequest.requestString(withAddress: address, forAmount: amount)
        XCTAssertNotNil(uri)
        XCTAssertEqual(uri, "ethereum:0xbDFdAd139440D2Db9BA2aa3B7081C2dE39291508?amount=1")
    }
}
