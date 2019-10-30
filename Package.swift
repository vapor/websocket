// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "websocket-kit",
    platforms: [
       .macOS(.v10_14)
    ],
    products: [
        .library(name: "WebSocketKit", targets: ["WebSocketKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", .exact("2.4.0")),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", .exact("2.4.0")),
    ],
    targets: [
        .target(name: "WebSocketKit", dependencies: [
            "NIO",
            "NIOConcurrencyHelpers",
            "NIOFoundationCompat",
            "NIOHTTP1",
            "NIOSSL",
            "NIOWebSocket"
        ]),
        .testTarget(name: "WebSocketKitTests", dependencies: ["WebSocketKit"]),
    ]
)
