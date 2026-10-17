// swift-tools-version: 6.0
import PackageDescription

// TodayCore is plain Swift + Foundation: no EventKit, SwiftUI or WidgetKit.
// That keeps every household rule testable with `swift test` on Linux as well
// as macOS, and lets the app and the widget extension share one engine.
// TodaySources holds the Apple-only adapters (EventKit); on Linux it compiles
// to nothing.
let package = Package(
    name: "TodayKit",
    platforms: [.iOS("27.0"), .macOS(.v15)],
    products: [
        .library(name: "TodayCore", targets: ["TodayCore"]),
        .library(name: "TodaySources", targets: ["TodaySources"]),
    ],
    targets: [
        .target(name: "TodayCore"),
        .target(name: "TodaySources", dependencies: ["TodayCore"]),
        // `swift run today-plan 2026-10-20` prints a seeded day's plan.
        .executableTarget(name: "today-plan", dependencies: ["TodayCore"]),
        // Golden/ holds expected text the tests read by path, not resources.
        .testTarget(name: "TodayCoreTests", dependencies: ["TodayCore"], exclude: ["Golden"]),
        .testTarget(name: "TodaySourcesTests", dependencies: ["TodaySources", "TodayCore"]),
    ]
)
