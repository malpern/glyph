// swift-tools-version: 5.10
import PackageDescription

// ReaderCore is the UI-free, Readium-free heart of the app: domain models,
// repository protocols, and their SwiftData-backed implementations. Keeping it
// free of UIKit/SwiftUI and Readium lets it be shared verbatim by future
// iPad/Mac clients and keeps the dependency direction one-way (Features -> Core).
let package = Package(
    name: "ReaderCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ReaderCore", targets: ["ReaderCore"]),
    ],
    targets: [
        .target(name: "ReaderCore"),
        .testTarget(name: "ReaderCoreTests", dependencies: ["ReaderCore"]),
    ]
)
