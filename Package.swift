// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MioAmp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MioAmp", targets: ["MioAmpApp"]),
        .executable(name: "AudioProbe", targets: ["AudioProbe"]),
        .library(name: "MioAmpContracts", targets: ["Contracts"]),
        .library(name: "MioAmpAudio", targets: ["Audio"]),
        .library(name: "MioAmpAudioAnalysis", targets: ["AudioAnalysis"]),
        .library(name: "MioAmpVisualizations", targets: ["Visualizations"]),
        .library(name: "MioAmpLibrary", targets: ["Library"]),
        .library(name: "MioAmpSkins", targets: ["Skins"]),
        .library(name: "MioAmpPlayerUI", targets: ["PlayerUI"]),
        .library(name: "MioAmpMacIntegration", targets: ["MacIntegration"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [
        .target(
            name: "CAudioDecoders",
            path: "Packages/MioAmpKit/Sources/CAudioDecoders",
            publicHeadersPath: "include"
        ),
        .target(
            name: "CVisualizationBridge",
            path: "Packages/MioAmpKit/Sources/CVisualizationBridge",
            publicHeadersPath: "include"
        ),
        .target(name: "Contracts", path: "Packages/MioAmpKit/Sources/Contracts"),
        .target(
            name: "AudioAnalysis",
            dependencies: ["Contracts", "CVisualizationBridge"],
            path: "Packages/MioAmpKit/Sources/AudioAnalysis"
        ),
        .target(
            name: "Visualizations",
            dependencies: ["Contracts"],
            path: "Packages/MioAmpKit/Sources/Visualizations"
        ),
        .target(
            name: "Audio",
            dependencies: [
                "Contracts",
                "CAudioDecoders",
                "AudioAnalysis",
            ],
            path: "Packages/MioAmpKit/Sources/Audio"
        ),
        .target(
            name: "Library",
            dependencies: ["Contracts"],
            path: "Packages/MioAmpKit/Sources/Library"
        ),
        .target(
            name: "Skins",
            dependencies: [
                "Contracts",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Packages/MioAmpKit/Sources/Skins"
        ),
        .target(
            name: "PlayerUI",
            dependencies: ["Contracts", "Skins", "Visualizations"],
            path: "Packages/MioAmpKit/Sources/PlayerUI"
        ),
        .target(
            name: "MacIntegration",
            dependencies: ["Contracts", "Audio", "Library"],
            path: "Packages/MioAmpKit/Sources/MacIntegration"
        ),
        .target(
            name: "TestSupport",
            dependencies: ["Contracts"],
            path: "Packages/MioAmpKit/Sources/TestSupport"
        ),
        .executableTarget(
            name: "MioAmpApp",
            dependencies: ["Contracts", "Audio", "Library", "Skins", "PlayerUI", "MacIntegration"],
            path: "MioAmp/App"
        ),
        .executableTarget(
            name: "AudioProbe",
            dependencies: ["Contracts", "Audio"],
            path: "Tools/AudioProbe"
        ),
        .testTarget(
            name: "ContractsTests",
            dependencies: ["Contracts", "TestSupport"],
            path: "Packages/MioAmpKit/Tests/ContractsTests"
        ),
        .testTarget(
            name: "AudioTests",
            dependencies: ["Contracts", "Audio"],
            path: "Packages/MioAmpKit/Tests/AudioTests"
        ),
        .testTarget(
            name: "AudioAnalysisTests",
            dependencies: ["Contracts", "AudioAnalysis"],
            path: "Packages/MioAmpKit/Tests/AudioAnalysisTests"
        ),
        .testTarget(
            name: "VisualizationsTests",
            dependencies: ["Contracts", "Visualizations"],
            path: "Packages/MioAmpKit/Tests/VisualizationsTests"
        ),
        .testTarget(
            name: "LibraryTests",
            dependencies: ["Contracts", "Library", "TestSupport"],
            path: "Packages/MioAmpKit/Tests/LibraryTests"
        ),
        .testTarget(
            name: "PlayerUITests",
            dependencies: ["Contracts", "PlayerUI", "Skins"],
            path: "Packages/MioAmpKit/Tests/PlayerUITests"
        ),
        .testTarget(
            name: "SkinsTests",
            dependencies: [
                "Contracts",
                "Skins",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Packages/MioAmpKit/Tests/SkinsTests"
        ),
        .testTarget(
            name: "MacIntegrationTests",
            dependencies: ["Contracts", "Audio", "Library", "MacIntegration", "TestSupport"],
            path: "Packages/MioAmpKit/Tests/MacIntegrationTests"
        ),
    ]
)
