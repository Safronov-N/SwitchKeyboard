// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwitchKeyboard",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SwitchKeyboardCore", targets: ["SwitchKeyboardCore"]),
        .executable(name: "SwitchKeyboard", targets: ["SwitchKeyboard"])
    ],
    targets: [
        .target(name: "SwitchKeyboardCore"),
        .executableTarget(name: "SwitchKeyboard", dependencies: ["SwitchKeyboardCore"]),
        .testTarget(name: "SwitchKeyboardCoreTests", dependencies: ["SwitchKeyboardCore"])
    ],
    swiftLanguageModes: [.v5]
)
