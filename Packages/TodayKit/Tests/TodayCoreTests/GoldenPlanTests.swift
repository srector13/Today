import Foundation
import Testing
@testable import TodayCore

/// The seeded days rendered as text, compared with `Golden/<date>.txt`.
///
/// A change to the engine or the sample rules that moves anything on these
/// days fails here with a readable diff. After checking the new output is
/// right, rewrite the files with:
///
///     TODAY_UPDATE_GOLDENS=1 swift test --filter GoldenPlanTests
@Suite("Seeded days (golden text)")
struct GoldenPlanTests {
    static let goldenDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Golden")

    @Test(arguments: SampleHousehold.seededDays)
    func matchesGolden(_ date: LocalDate) throws {
        let rendered = PlanText.render(SampleHousehold.plan(for: date), planner: Fixture.planner)
        let file = Self.goldenDirectory.appendingPathComponent("\(date.iso).txt")
        if ProcessInfo.processInfo.environment["TODAY_UPDATE_GOLDENS"] == "1" {
            try rendered.write(to: file, atomically: true, encoding: .utf8)
            return
        }
        let golden = try String(contentsOf: file, encoding: .utf8)
        if rendered != golden {
            let renderedLines = rendered.components(separatedBy: "\n")
            let goldenLines = golden.components(separatedBy: "\n")
            let firstDifference = zip(renderedLines, goldenLines).enumerated().first { $0.element.0 != $0.element.1 }
            let line = firstDifference?.offset ?? min(renderedLines.count, goldenLines.count)
            Issue.record("""
            \(date.iso) differs from Golden/\(date.iso).txt at line \(line + 1):
              golden:   \(line < goldenLines.count ? goldenLines[line] : "<end>")
              rendered: \(line < renderedLines.count ? renderedLines[line] : "<end>")
            Full rendering:
            \(rendered)
            """)
        }
    }
}
