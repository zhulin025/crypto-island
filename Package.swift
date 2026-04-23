// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CryptoIsland",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "CryptoIsland", targets: ["CryptoIsland"])
    ],
    targets: [
        .executableTarget(
            name: "CryptoIsland",
            path: ".",
            exclude: ["Package.swift"]
        )
    ]
)
