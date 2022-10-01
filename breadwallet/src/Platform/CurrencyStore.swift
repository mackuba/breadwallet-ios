//
//  BRAPIClient+Currencies.swift
//  breadwallet
//
//  Created by Ehsan Rezaie on 2018-03-12.
//  Copyright © 2018-2019 Breadwinner AG. All rights reserved.
//

import Foundation

struct FiatCurrency: Decodable {
    var name: String
    var code: String

    static var availableCurrencies: [FiatCurrency] = {
        guard let path = Bundle.main.path(forResource: "fiatcurrencies", ofType: "json") else {
            print("unable to locate currencies file")
            return []
        }

        var currencies: [FiatCurrency]?

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoder = JSONDecoder()
            currencies = try decoder.decode([FiatCurrency].self, from: data)
        } catch let e {
            print("error parsing fiat currency data: \(e)")
        }

        return currencies ?? []
    }()

    // case of code doesn't matter
    static func isCodeAvailable(_ code: String) -> Bool {
        let available = FiatCurrency.availableCurrencies.map { $0.code.lowercased() }
        return available.contains(code.lowercased())
    }
}

class CurrencyStore {
    static let shared = CurrencyStore()

    /// Get the list of supported currencies and their metadata from the bundled file
    func getCurrencyMetaData(completion: @escaping ([CurrencyId: CurrencyMetaData]) -> Void) {
        let embeddedFilePath = Bundle.main.path(forResource: "currencies", ofType: "json")!

        let currencyData = try! Data(contentsOf: URL(fileURLWithPath: embeddedFilePath))
        let currencies = try! JSONDecoder().decode([CurrencyMetaData].self, from: currencyData)

        let currencyMetaData = currencies.reduce(into: [CurrencyId: CurrencyMetaData](), { (dict, token) in
            dict[token.uid] = token
        })

        print("[CurrencyStore] tokens loaded: \(currencies.count) tokens")

        completion(currencyMetaData)
    }
}
