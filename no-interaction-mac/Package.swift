// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoInteraction",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "NoInteraction",
            path: "NoInteraction",
            exclude: ["Resources"],
            sources: [
                "App/NoInteractionApp.swift",
                "Models/Models.swift",
                "Core/AppObserver.swift",
                "Core/AXInspector.swift",
                "Core/VisionOCRScanner.swift",
                "Core/ClickAutomation.swift",
                "Core/ApproverEngine.swift",
                "UI/DashboardView.swift",
                "UI/MenuBarManager.swift"
            ]
        )
    ]
)
