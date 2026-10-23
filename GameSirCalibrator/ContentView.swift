import SwiftUI

struct Measurement {
    var left = StickStats()
    var right = StickStats()
}

enum Phase { case idle, rest, sweep, done }

struct ContentView: View {
    let gamepads: Gamepads
    @State private var selectedID: Gamepad.ID?
    @State private var phase = Phase.idle
    @State private var current = Measurement()
    @State private var before: Measurement?
    @State private var showGuide = false

    private var pad: Gamepad? { gamepads.pads.first { $0.id == selectedID } ?? gamepads.pads.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = gamepads.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            if let pad {
                header(pad)
                HStack(spacing: 24) {
                    StickView(title: "Left stick", live: pad.left, stats: current.left)
                    StickView(title: "Right stick", live: pad.right, stats: current.right)
                }
                triggers(pad)
                controls
                if phase == .done { ResultsView(current: current, before: before) }
            } else {
                ContentUnavailableView(
                    "No controller", systemImage: "gamecontroller",
                    description: Text("Connect your controller with the dongle or Bluetooth. In Switch mode a GameSir pad shows up as \"Pro Controller\"."))
            }
        }
        .padding(20)
        .frame(width: 520)
        .task(id: phase) { await sample() }
        .sheet(isPresented: $showGuide) {
            GuideSheet {
                before = current
                start()
            }
        }
    }

    private func header(_ pad: Gamepad) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if gamepads.pads.count > 1 {
                Picker("Controller", selection: Binding(get: { pad.id }, set: { selectedID = $0 })) {
                    ForEach(gamepads.pads) { Text($0.name).tag($0.id) }
                }
            } else {
                Text(pad.name).font(.title2.bold())
            }
            Text("Reading: \(pad.source)").font(.caption).foregroundStyle(.secondary)
            if pad.rightIsAmbiguous {
                Toggle("Right stick is on Rx/Ry", isOn: Bindable(pad).rightUsesRxRy)
            }
        }
    }

    @ViewBuilder private func triggers(_ pad: Gamepad) -> some View {
        let triggers = pad.triggers
        if triggers.isEmpty {
            Text("No analog triggers reported. In Switch mode the triggers are on/off buttons, so their travel can't be measured.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ForEach(triggers, id: \.name) { trigger in
                LabeledContent(trigger.name) { ProgressView(value: trigger.value) }
            }
        }
    }

    @ViewBuilder private var controls: some View {
        switch phase {
        case .idle:
            Button("Measure sticks") { before = nil; start() }.keyboardShortcut(.defaultAction)
        case .rest:
            Label("Hands off. Measuring the resting position…", systemImage: "hand.raised")
        case .sweep:
            VStack(alignment: .leading, spacing: 8) {
                Text("Rotate both sticks around their edge 3 times, then press Done.")
                HStack {
                    Text("Edge covered: left \(percent(current.left.coverage)), right \(percent(current.right.coverage))")
                        .monospacedDigit().foregroundStyle(.secondary)
                    Spacer()
                    Button("Done") { phase = .done }.keyboardShortcut(.defaultAction)
                }
            }
        case .done:
            HStack {
                Button("Start over") { before = nil; start() }
                Spacer()
                Button("Calibrate…") { showGuide = true }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func start() {
        current = Measurement()
        phase = .rest
    }

    /// Samples the selected pad at ~125 Hz: 2 s at rest, then until the user presses Done.
    private func sample() async {
        let started = ContinuousClock.now
        while !Task.isCancelled, phase == .rest || phase == .sweep {
            if let pad {
                if phase == .rest {
                    current.left.rest.append(pad.left)
                    current.right.rest.append(pad.right)
                } else {
                    current.left.sweep.append(pad.left)
                    current.right.sweep.append(pad.right)
                }
            }
            if phase == .rest, ContinuousClock.now - started > .seconds(2) { phase = .sweep }
            try? await Task.sleep(for: .milliseconds(8))
        }
    }
}

/// The stick's travel: full-range circle, the edge it reached (blue), its resting point (orange), and where it is now.
struct StickView: View {
    let title: String
    let live: SIMD2<Double>
    let stats: StickStats

    var body: some View {
        VStack {
            Text(title).font(.headline)
            Canvas { context, size in
                let r = min(size.width, size.height) / 2 - 6
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                func point(_ p: SIMD2<Double>) -> CGPoint { CGPoint(x: c.x + p.x * r, y: c.y + p.y * r) }
                func dot(_ p: SIMD2<Double>, _ d: CGFloat) -> Path {
                    Path(ellipseIn: CGRect(x: point(p).x - d / 2, y: point(p).y - d / 2, width: d, height: d))
                }

                var grid = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                grid.move(to: CGPoint(x: c.x - r, y: c.y))
                grid.addLine(to: CGPoint(x: c.x + r, y: c.y))
                grid.move(to: CGPoint(x: c.x, y: c.y - r))
                grid.addLine(to: CGPoint(x: c.x, y: c.y + r))
                context.stroke(grid, with: .style(.quaternary), lineWidth: 1)

                let edge = stats.outline.compactMap { $0 }
                if edge.count > 2 {
                    var path = Path()
                    path.addLines(edge.map(point))
                    path.closeSubpath()
                    context.stroke(path, with: .style(.tint), lineWidth: 2)
                }
                if !stats.rest.isEmpty { context.fill(dot(stats.centre, 8), with: .color(.orange)) }
                context.fill(dot(live, 12), with: .style(.primary))
            }
            .frame(width: 220, height: 220)
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityValue("x \(decimal(live.x)), y \(decimal(live.y))")
            Text("x \(decimal(live.x))   y \(decimal(live.y))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

struct ResultsView: View {
    let current: Measurement
    let before: Measurement?

    private let rows: [(name: String, key: KeyPath<StickStats, Double?>, limit: Double?)] = [
        ("Centre offset", \.centreOffset, StickStats.goodCentreOffset),
        ("Noise at rest", \.noise, nil),
        ("Roundness error", \.roundnessError, StickStats.goodRoundnessError),
        ("Reach", \.reach, nil),
        ("Suggested deadzone", \.suggestedDeadzone, nil),
    ]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text(before == nil ? "Result" : "Before → after").foregroundStyle(.secondary)
                Text("Left").bold()
                Text("Right").bold()
            }
            Divider()
            ForEach(rows, id: \.name) { row in
                GridRow {
                    Text(row.name)
                    cell(\.left, row.key, row.limit)
                    cell(\.right, row.key, row.limit)
                }
            }
        }
        let coverage = min(current.left.coverage, current.right.coverage)
        if coverage < 0.9 {
            Label("Only \(percent(coverage)) of the edge was reached, so roundness is less reliable. Rotate further next time.",
                  systemImage: "exclamationmark.circle")
                .font(.callout).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cell(_ stick: KeyPath<Measurement, StickStats>, _ key: KeyPath<StickStats, Double?>, _ limit: Double?) -> some View {
        let now = current[keyPath: stick][keyPath: key]
        let was = before?[keyPath: stick][keyPath: key]
        let ok = now.flatMap { now in limit.map { now <= $0 } }
        return HStack(spacing: 4) {
            Text((was.map { percent($0) + " → " } ?? "") + (now.map(percent) ?? "–")).monospacedDigit()
            if let ok {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ok ? .green : .orange)
                    .accessibilityLabel(ok ? "Good" : "Needs calibration")
            }
        }
    }
}

struct GuideSheet: View {
    let onFinish: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var guide = guides[0]
    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Controller", selection: $guide) {
                ForEach(guides) { Text($0.model).tag($0) }
            }
            .onChange(of: guide) { step = 0 }
            Text("Step \(step + 1) of \(guide.steps.count)").font(.caption).foregroundStyle(.secondary)
            Text(guide.steps[step])
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Back") { step -= 1 }.disabled(step == 0)
                if step < guide.steps.count - 1 {
                    Button("Next") { step += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Measure again") { dismiss(); onFinish() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

private func percent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(1))) }
private func decimal(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2))) }
