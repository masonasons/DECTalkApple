// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DECtalkApple",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
    ],
    products: [
        .library(name: "DECtalkKit", targets: ["DECtalkKit"]),
    ],
    targets: [
        // Prebuilt DECtalk engine (the ~90 dapi/src *.c files + dtk_shim) as a
        // static xcframework. Build/refresh it with engine/build-xcframework.sh.
        .binaryTarget(
            name: "DECtalkEngine",
            path: "engine/DECtalkEngine.xcframework"
        ),
        // Swift wrapper: turns text into AVAudioPCMBuffers via the C shim.
        .target(
            name: "DECtalkKit",
            dependencies: ["DECtalkEngine"],
            resources: [
                .copy("Resources/dtalk_us.dic"),
            ]
        ),
        .testTarget(
            name: "DECtalkKitTests",
            dependencies: ["DECtalkKit"]
        ),
    ]
)
