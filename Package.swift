// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProgressiveBlur",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ProgressiveBlur", targets: ["ProgressiveBlur"])
    ],
    targets: [
        .executableTarget(
            name: "ProgressiveBlur",
            path: "Sources",
            exclude: [
                "Graphics/Shaders.metal"
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Vision")
            ]
        )
    ]
)
