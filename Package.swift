// swift-tools-version: 5.9
//
//  Package.swift
//  KitoPhotoEditor
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import PackageDescription

let package = Package(
    name: "KitoPhotoEditor",
    platforms: [.iOS(.v17)],
    products: [.library(name: "KitoPhotoEditor", targets: ["KitoPhotoEditor"])],
    targets: [
        .target(name: "KitoPhotoEditor"),
        .testTarget(name: "KitoPhotoEditorTests", dependencies: ["KitoPhotoEditor"]),
    ]
)
