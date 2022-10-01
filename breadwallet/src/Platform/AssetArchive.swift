//
//  AssetArchive.swift
//  breadwallet
//
//  Created by Ehsan Rezaie on 2019-02-13.
//  Copyright © 2019 Breadwinner AG. All rights reserved.
//

import Foundation

open class AssetArchive {
    let name: String
    private let fileManager: FileManager
    private let extractedPath: String
    let extractedUrl: URL

    private var extractedDirExists: Bool {
        return fileManager.fileExists(atPath: extractedPath)
    }

    private static var bundleDirUrl: URL {
        let fm = FileManager.default
        let docsUrl = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let bundleDirUrl = docsUrl.appendingPathComponent("bundles", isDirectory: true)
        return bundleDirUrl
    }

    init?(name: String) {
        self.name = name
        self.fileManager = FileManager.default

        let bundleDirUrl = Self.bundleDirUrl
        extractedUrl = bundleDirUrl.appendingPathComponent("\(name)-extracted", isDirectory: true)
        extractedPath = extractedUrl.path
    }

    func update(completionHandler: @escaping () -> Void) {
        guard !extractedDirExists else {
            completionHandler()
            return
        }

        try! fileManager.createDirectory(
            atPath: extractedPath, withIntermediateDirectories: true, attributes: nil
        )

        let bundledArchiveUrl = Bundle.main.url(forResource: name, withExtension: "tar")!

        try! BRTar.createFilesAndDirectoriesAtPath(extractedPath, withTarPath: bundledArchiveUrl.path)

        completionHandler()
    }
}
