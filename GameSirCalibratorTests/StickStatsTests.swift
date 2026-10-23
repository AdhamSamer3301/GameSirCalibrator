import Foundation
import Testing
@testable import GameSirCalibrator

struct StickStatsTests {
    /// Points around a circle of `radius`; `square` pushes them out to a square instead.
    func ring(radius: Double, square: Bool = false, count: Int = 720) -> [SIMD2<Double>] {
        (0..<count).map {
            let a = Double($0) / Double(count) * 2 * .pi
            let p = SIMD2(cos(a), sin(a))
            return p * radius / (square ? max(abs(p.x), abs(p.y)) : 1)
        }
    }

    @Test func centredRoundStickPasses() {
        let stats = StickStats(rest: Array(repeating: .zero, count: 100), sweep: ring(radius: 0.8))
        #expect(stats.centreOffset! < 1e-9)
        #expect(stats.noise! < 1e-9)
        #expect(stats.roundnessError! < 0.01)
        #expect(abs(stats.reach! - 0.8) < 0.001)
        #expect(stats.coverage == 1)
    }

    @Test func driftIsMeasuredAgainstTravel() {
        // Resting 0.04 off-centre on a stick that only travels 0.8 is 5% drift.
        let stats = StickStats(rest: [SIMD2(0.04, 0)], sweep: ring(radius: 0.8))
        #expect(abs(stats.centreOffset! - 0.05) < 1e-9)
        #expect(abs(stats.suggestedDeadzone! - (0.05 + StickStats.deadzoneMargin)) < 1e-9)
    }

    @Test func squareOutputFailsRoundness() {
        let stats = StickStats(rest: [.zero], sweep: ring(radius: 0.8, square: true))
        #expect(stats.roundnessError! > StickStats.goodRoundnessError)
    }

    @Test func partialSweepReportsCoverage() {
        let stats = StickStats(rest: [.zero], sweep: Array(ring(radius: 1).prefix(360)) + [SIMD2(0, -1)])
        #expect(abs(stats.coverage - 0.5) < 0.05)
    }

    @Test func decodesSwitchProFullReport() {
        var report = [UInt8](repeating: 0, count: 49)
        report[0] = 0x30
        report[6...8] = [0x23, 0x61, 0x45]  // left: x = 0x123, y = 0x456
        report[9...11] = [0x00, 0x08, 0x80]  // right: x = y = 2048 (centred)
        let sticks = Gamepad.switchProSticks(report)!
        #expect(sticks.left == SIMD2(Double(0x123 - 2048) / 2048, Double(2048 - 0x456) / 2048))
        #expect(sticks.right == .zero)

        report[0] = 0x3F
        #expect(Gamepad.switchProSticks(report) == nil)
    }
}
