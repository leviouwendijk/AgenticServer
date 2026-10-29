// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "AgenticServer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "AgenticServer",
            targets: ["AgenticServer"]
        ),
        .executable(
            name: "t_as_main",
            targets: ["AgenticServerTestFlows"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/leviouwendijk/Agentic.git",
            branch: "master"
        ),
        // .package(
        //     url: "https://github.com/leviouwendijk/AgenticProviders.git",
        //     branch: "master"
        // ),
        .package(
            url: "https://github.com/leviouwendijk/AgenticRuntime.git",
            branch: "master"
        ),
        // .package(
        //     url: "https://github.com/leviouwendijk/AgenticHost.git",
        //     branch: "master"
        // ),
        // .package(
        //     url: "https://github.com/leviouwendijk/AgenticInterfaces.git",
        //     branch: "master"
        // ),
        .package(
            url: "https://github.com/leviouwendijk/Server.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/HTTP.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Primitives.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Testing.git",
            branch: "master"
        ),
    ],
    targets: [
        .target(
            name: "AgenticServer",
            dependencies: [
                .product(name: "Agentic", package: "Agentic"),
                .product(name: "AgenticRuntime", package: "AgenticRuntime"),
                .product(name: "Server", package: "Server"),
                .product(name: "HTTP", package: "HTTP"),
                .product(name: "Primitives", package: "Primitives"),
            ]
        ),
        .executableTarget(
            name: "AgenticServerTestFlows",
            dependencies: [
                "AgenticServer",
                .product(name: "Agentic", package: "Agentic"),
                .product(name: "AgenticRuntime", package: "AgenticRuntime"),
                .product(name: "Server", package: "Server"),
                .product(name: "HTTP", package: "HTTP"),
                .product(name: "Primitives", package: "Primitives"),
            ],
            path: "Testing/AgenticServerTestFlows"
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets {
    switch target.type {
    case .regular, .executable, .test, .macro:
        var settings = target.swiftSettings ?? []

        settings.append(
            .treatAllWarnings(as: .error)
        )

        settings.append(
            .unsafeFlags(
                [
                    "-continue-building-after-errors"
                ]
            )
        )

        target.swiftSettings = settings

    case .plugin, .system, .binary:
        break

    @unknown default:
        break
    }
}
