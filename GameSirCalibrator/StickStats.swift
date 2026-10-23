import Foundation

/// Measures one analog stick: drift while resting, then travel and roundness while rotated.
/// Samples are in the normalized -1...1 space `Gamepad` reports. Results are fractions of the
/// stick's own swept travel, so they compare across pads whatever their raw resolution.
struct StickStats {
    // ponytail: tuning knobs; real sticks vary, so adjust these after testing more pads.
    static let goodCentreOffset = 0.03
    static let goodRoundnessError = 0.10
    static let deadzoneMargin = 0.02
    /// A sector counts as visited once the stick has been pushed past this fraction of its travel.
    static let edgeThreshold = 0.5
    static let sectors = 72  // 5° each

    var rest: [SIMD2<Double>] = []
    var sweep: [SIMD2<Double>] = []

    /// Average resting position, in raw normalized units.
    var centre: SIMD2<Double> { rest.isEmpty ? .zero : rest.reduce(.zero, +) / Double(rest.count) }

    /// Half the swept travel on each axis.
    var scale: SIMD2<Double>? {
        guard let first = sweep.first else { return nil }
        let (lo, hi) = sweep.reduce((first, first)) { (pointwiseMin($0.0, $1), pointwiseMax($0.1, $1)) }
        let s = (hi - lo) / 2
        return s.min() > 0 ? s : nil
    }

    /// How far the resting stick sits from zero, as a fraction of travel.
    var centreOffset: Double? { scale.map { length(centre / $0) } }

    /// Largest wobble around the resting position, as a fraction of travel.
    var noise: Double? {
        guard let s = scale, !rest.isEmpty else { return nil }
        let c = centre
        return rest.map { length(($0 - c) / s) }.max()
    }

    /// Average travel across both axes, as a fraction of the full HID range.
    var reach: Double? { scale.map { ($0.x + $0.y) / 2 } }

    /// The farthest sample in each 5° sector (raw units, ordered by angle), nil where the stick hasn't been.
    var outline: [SIMD2<Double>?] {
        var far = [SIMD2<Double>?](repeating: nil, count: Self.sectors)
        guard let s = scale else { return far }
        for p in sweep {
            let q = p / s
            let sector = Int((atan2(q.y, q.x) + .pi) / (2 * .pi) * Double(Self.sectors)) % Self.sectors
            if far[sector].map({ length(q) > length($0 / s) }) ?? true { far[sector] = p }
        }
        return far
    }

    /// Radius of each visited sector's farthest point, as a fraction of travel.
    private var edgeRadii: [Double] {
        guard let s = scale else { return [] }
        return outline.compactMap { $0.map { length($0 / s) } }.filter { $0 > Self.edgeThreshold }
    }

    /// Fraction of the 72 sectors the stick has reached the edge of.
    var coverage: Double { Double(edgeRadii.count) / Double(Self.sectors) }

    /// Mean distance of the edge from a perfect circle (0 = perfectly round).
    var roundnessError: Double? {
        let r = edgeRadii
        return r.isEmpty ? nil : r.map { abs($0 - 1) }.reduce(0, +) / Double(r.count)
    }

    /// Smallest deadzone that hides this stick's resting drift and noise.
    var suggestedDeadzone: Double? {
        guard let offset = centreOffset, let noise else { return nil }
        return offset + noise + Self.deadzoneMargin
    }

    private func length(_ v: SIMD2<Double>) -> Double { (v * v).sum().squareRoot() }
}
