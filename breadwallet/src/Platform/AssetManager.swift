//
//  BRAPIClient+Bundles.swift
//  breadwallet
//
//  Created by Samuel Sutch on 3/31/17.
//  Copyright © 2017-2019 Breadwinner AG. All rights reserved.
//

import Foundation

// Platform bundle management
class AssetManager {
    // updates asset bundles with names included in the AssetBundles.plist file
    // if we are in a staging/debug/test environment the bundle names will have "-staging" appended to them
    func unpackBundles() {
        // ensure we can create the bundle directory
        try! self.ensureBundlePaths()

        let path = Bundle.main.path(forResource: "AssetBundles", ofType: "plist")!
        var names = NSArray(contentsOfFile: path) as! [String]

        if E.isDebug || E.isTestFlight {
            names = names.map { n in return n + "-staging" }
        }

        let grp = DispatchGroup()
        let queue = DispatchQueue.global(qos: .utility)

        queue.async {
            for (_, name) in names.enumerated() {
                if let archive = AssetArchive(name: name) {
                    grp.enter()
                    archive.update(completionHandler: {
                        queue.async(flags: .barrier) {
                            grp.leave()
                        }
                    })
                }
            }
            grp.wait()
        }
    }
    
    var bundleDirUrl: URL {
        let fm = FileManager.default
        let docsUrl = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let bundleDirUrl = docsUrl.appendingPathComponent("bundles", isDirectory: true)
        return bundleDirUrl
    }
    
    fileprivate func ensureBundlePaths() throws {
        let fm = FileManager.default
        var attrs = try? fm.attributesOfItem(atPath: bundleDirUrl.path)
        if attrs == nil {
            try fm.createDirectory(atPath: bundleDirUrl.path, withIntermediateDirectories: true, attributes: nil)
            attrs = try fm.attributesOfItem(atPath: bundleDirUrl.path)
        }
    }
}
