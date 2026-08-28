import SwiftUI

struct ContentView: View {
  @AppStorage("cycleCount") private var cycleCount = 15
  @AppStorage("warmupSeconds") private var warmupSeconds = 0
  @AppStorage("runSeconds") private var runSeconds = 60
  @AppStorage("walkSeconds") private var walkSeconds = 60
  @StateObject private var session = WorkoutSessionController()
  @State private var showsStopConfirmation = false
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.colorScheme) private var colorScheme
  @ScaledMetric(relativeTo: .largeTitle) private var phaseFontSize: CGFloat = 68
  @ScaledMetric(relativeTo: .largeTitle) private var intervalFontSize: CGFloat = 64

  var body: some View {
    Group {
      switch session.status {
      case .idle:
        configurationView
      case .running, .paused:
        workoutView
      case .complete:
        completeView
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
    .tint(Color(red: 0.00, green: 0.498, blue: 0.498))
    .confirmationDialog(
      "End workout?",
      isPresented: $showsStopConfirmation,
      titleVisibility: .visible
    ) {
      Button("End Workout", role: .destructive) {
        session.stop()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Your current workout will end.")
    }
    .onAppear(perform: migrateLegacyDurationsIfNeeded)
    .onChange(of: runSeconds) { _, _ in clampCycleCount() }
    .onChange(of: walkSeconds) { _, _ in clampCycleCount() }
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .active {
        session.refresh()
      }
    }
  }

  private var configurationView: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 28) {
          Text("SPLIT")
            .font(.system(size: 48, weight: .black, design: .rounded))
            .tracking(4)
            .accessibilityAddTraits(.isHeader)

          warmupStepper

          VStack(alignment: .leading, spacing: 12) {
            Text("INTERVALS")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
              .padding(.leading, 4)
              .accessibilityAddTraits(.isHeader)

            intervalStepper("RUN", value: $runSeconds)
            intervalStepper("WALK", value: $walkSeconds)
            cycleStepper
          }

          if let errorMessage = session.errorMessage {
            VStack(spacing: 10) {
              Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

              Button("Open Settings") {
                session.openNotificationSettings()
              }
              .font(.footnote.weight(.semibold))
            }
          }

          startButton
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: geometry.size.height, alignment: .center)
      }
      .scrollIndicators(.hidden)
      .scrollBounceBehavior(.basedOnSize)
    }
  }

  private var startButton: some View {
    Button {
      Task {
        await session.start(configuration: configuration)
      }
    } label: {
      Group {
        if session.isBusy {
          ProgressView()
        } else {
          VStack(spacing: 3) {
            Text("Start Workout")
              .font(.headline)
            Text(startDurationDescription)
              .font(.subheadline)
              .opacity(0.9)
              .multilineTextAlignment(.center)
          }
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
    }
    .buttonStyle(.borderedProminent)
    .disabled(session.isBusy || !configuration.validationErrors.isEmpty)
    .accessibilityLabel("Start workout")
    .accessibilityValue(startAccessibilityDescription)
  }

  private var workoutView: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 18) {
          workoutRemaining

          Spacer(minLength: 28)

          workoutState

          Spacer(minLength: 28)

          if let errorMessage = session.errorMessage {
            Text(errorMessage)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }

          workoutControls
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: geometry.size.height)
      }
      .scrollIndicators(.hidden)
      .scrollBounceBehavior(.basedOnSize)
    }
  }

  private var workoutRemaining: some View {
    HStack {
      Text("WORKOUT REMAINING")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Spacer()
      Text(formatted(session.totalRemaining))
        .font(.title3.monospacedDigit().weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Workout remaining")
    .accessibilityValue(accessibleDuration(session.totalRemaining))
  }

  private var workoutState: some View {
    VStack(spacing: 14) {
      if session.status == .paused {
        Text("PAUSED")
          .font(.system(size: phaseFontSize, weight: .black, design: .rounded))
          .lineLimit(1)
          .minimumScaleFactor(0.5)

        Text("\(session.phase.rawValue) PHASE")
          .font(.headline)
          .foregroundStyle(.secondary)
      } else {
        Text(session.phase.rawValue)
          .font(.system(size: phaseFontSize, weight: .black, design: .rounded))
          .lineLimit(1)
          .minimumScaleFactor(0.5)

        Capsule()
          .fill(phaseAccentColor)
          .frame(width: 52, height: 6)
          .accessibilityHidden(true)
      }

      VStack(spacing: 6) {
        Text(formatted(session.intervalRemaining))
          .font(
            .system(size: intervalFontSize, weight: .medium, design: .rounded)
              .monospacedDigit()
          )
          .lineLimit(1)
          .minimumScaleFactor(0.5)

        Text("INTERVAL REMAINING")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Interval remaining")
      .accessibilityValue(accessibleDuration(session.intervalRemaining))
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(
      session.status == .paused
        ? "Paused during \(session.phase.rawValue.capitalized)"
        : session.phase.rawValue.capitalized
    )
  }

  @ViewBuilder
  private var workoutControls: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(spacing: 12) {
        pauseResumeButton
        stopButton
      }
    } else {
      HStack(spacing: 12) {
        pauseResumeButton
        stopButton
      }
    }
  }

  private var pauseResumeButton: some View {
    Button {
      if session.status == .running {
        session.pause()
      } else {
        Task { await session.resume() }
      }
    } label: {
      Group {
        if session.isBusy {
          ProgressView()
        } else {
          Text(session.status == .running ? "Pause" : "Resume")
        }
      }
      .frame(maxWidth: .infinity, minHeight: 44)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .disabled(session.isBusy)
  }

  private var stopButton: some View {
    Button("Stop", role: .destructive) {
      showsStopConfirmation = true
    }
    .buttonStyle(.bordered)
    .controlSize(.large)
    .frame(minWidth: 96, minHeight: 44)
    .disabled(session.isBusy)
  }

  private var completeView: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 24) {
          Spacer(minLength: 24)

          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 72))
            .foregroundStyle(Color.accentColor)
            .accessibilityHidden(true)

          Text("Workout Complete")
            .font(.largeTitle.bold())
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)

          Spacer(minLength: 24)

          Button("Done") {
            session.stop()
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .frame(maxWidth: .infinity, minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: geometry.size.height)
      }
      .scrollIndicators(.hidden)
      .scrollBounceBehavior(.basedOnSize)
    }
  }

  private var configuration: WorkoutConfiguration {
    WorkoutConfiguration(
      cycles: cycleCount,
      warmupSeconds: warmupSeconds,
      runSeconds: runSeconds,
      walkSeconds: walkSeconds
    )
  }

  private var maximumCycleCount: Int {
    max(1, 3_600 / (runSeconds + walkSeconds))
  }

  private var cycleStepper: some View {
    stepperCard {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          accessibleStepperHeader(title: "CYCLES", detail: "RUN + WALK")
          Stepper(value: $cycleCount, in: 1...maximumCycleCount) {
            Text("\(cycleCount)")
              .font(.title3.monospacedDigit().weight(.medium))
          }
          .controlSize(.large)
        }
      } else {
        Stepper(value: $cycleCount, in: 1...maximumCycleCount) {
          standardStepperLabel(title: "CYCLES", detail: "RUN + WALK", value: "\(cycleCount)")
        }
        .controlSize(.large)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Cycles")
    .accessibilityValue("\(cycleCount)")
    .accessibilityHint("One cycle includes one run interval and one walk interval.")
    .accessibilityAdjustableAction { direction in
      adjust($cycleCount, direction: direction, step: 1, range: 1...maximumCycleCount)
    }
  }

  private var warmupStepper: some View {
    stepperCard {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          accessibleStepperHeader(title: "WARMUP", detail: "OPTIONAL · 2:30 STEPS")
          Stepper(value: $warmupSeconds, in: 0...3_600, step: 150) {
            Text(warmupSeconds == 0 ? "Off" : formatted(TimeInterval(warmupSeconds)))
              .font(.title3.monospacedDigit().weight(.medium))
          }
          .controlSize(.large)
        }
      } else {
        Stepper(value: $warmupSeconds, in: 0...3_600, step: 150) {
          standardStepperLabel(
            title: "WARMUP",
            detail: "OPTIONAL · 2:30 STEPS",
            value: warmupSeconds == 0 ? "Off" : formatted(TimeInterval(warmupSeconds))
          )
        }
        .controlSize(.large)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Warmup")
    .accessibilityValue(
      warmupSeconds == 0 ? "Off" : accessibleDuration(TimeInterval(warmupSeconds))
    )
    .accessibilityHint("Adjusts in 2-minute 30-second increments.")
    .accessibilityAdjustableAction { direction in
      adjust($warmupSeconds, direction: direction, step: 150, range: 0...3_600)
    }
  }

  private func intervalStepper(_ title: String, value: Binding<Int>) -> some View {
    stepperCard {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          accessibleStepperHeader(title: title, detail: "15 SECOND STEPS")
          Stepper(value: value, in: 60...1_800, step: 15) {
            Text(formatted(TimeInterval(value.wrappedValue)))
              .font(.title3.monospacedDigit().weight(.medium))
          }
          .controlSize(.large)
        }
      } else {
        Stepper(value: value, in: 60...1_800, step: 15) {
          standardStepperLabel(
            title: title,
            detail: "15 SEC STEPS",
            value: formatted(TimeInterval(value.wrappedValue))
          )
        }
        .controlSize(.large)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title.capitalized)
    .accessibilityValue(accessibleDuration(TimeInterval(value.wrappedValue)))
    .accessibilityHint("Adjusts in 15-second increments.")
    .accessibilityAdjustableAction { direction in
      adjust(value, direction: direction, step: 15, range: 60...1_800)
    }
  }

  private func stepperCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
      .padding(16)
      .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
  }

  private func accessibleStepperHeader(title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.headline)
        .fixedSize(horizontal: false, vertical: true)
      Text(detail)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func standardStepperLabel(title: String, detail: String, value: String) -> some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline.weight(.semibold))
        Text(detail)
          .font(.caption2.weight(.medium))
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      Text(value)
        .font(.title3.monospacedDigit().weight(.medium))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
  }

  private var startDurationDescription: String {
    let split = "\(formatted(configuration.totalDuration)) split"
    guard warmupSeconds > 0 else { return split }
    return "\(split) + \(formatted(TimeInterval(warmupSeconds))) warmup"
  }

  private var startAccessibilityDescription: String {
    let split = "\(accessibleDuration(configuration.totalDuration)) split"
    guard warmupSeconds > 0 else { return split }
    return "\(split), plus \(accessibleDuration(TimeInterval(warmupSeconds))) warmup"
  }

  private var phaseAccentColor: Color {
    if session.status == .paused { return .secondary }

    switch (session.phase, colorScheme) {
    case (.warmup, .light): return Color(red: 0.70, green: 0.34, blue: 0.00)
    case (.run, .light): return Color(red: 0.00, green: 0.43, blue: 0.18)
    case (.walk, .light): return Color(red: 0.00, green: 0.38, blue: 0.66)
    case (.warmup, .dark): return .orange
    case (.run, .dark): return .green
    case (.walk, .dark): return .cyan
    @unknown default: return .primary
    }
  }

  private func migrateLegacyDurationsIfNeeded() {
    let defaults = UserDefaults.standard
    if defaults.object(forKey: "warmupSeconds") == nil,
      let legacyWarmupMinutes = defaults.object(forKey: "warmupMinutes") as? Int
    {
      let legacySeconds = max(0, legacyWarmupMinutes * 60)
      let nearestStep = ((legacySeconds + 75) / 150) * 150
      warmupSeconds = legacySeconds == 0 ? 0 : max(150, min(3_600, nearestStep))
    }
    if defaults.object(forKey: "runSeconds") == nil,
      let legacyRunMinutes = defaults.object(forKey: "runMinutes") as? Int
    {
      runSeconds = legacyRunMinutes * 60
    }
    if defaults.object(forKey: "walkSeconds") == nil,
      let legacyWalkMinutes = defaults.object(forKey: "walkMinutes") as? Int
    {
      walkSeconds = legacyWalkMinutes * 60
    }
    if defaults.object(forKey: "cycleCount") == nil,
      let legacyTotalMinutes = defaults.object(forKey: "totalMinutes") as? Int
    {
      cycleCount = max(
        1,
        min(legacyTotalMinutes * 60 / (runSeconds + walkSeconds), maximumCycleCount)
      )
    }
    clampCycleCount()
  }

  private func clampCycleCount() {
    cycleCount = min(max(1, cycleCount), maximumCycleCount)
  }

  private func formatted(_ duration: TimeInterval) -> String {
    let seconds = max(0, Int(ceil(duration)))
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    let remainingSeconds = seconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
    }
    return String(format: "%d:%02d", minutes, remainingSeconds)
  }

  private func accessibleDuration(_ duration: TimeInterval) -> String {
    let seconds = max(0, Int(ceil(duration)))
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    let remainingSeconds = seconds % 60
    var components: [String] = []

    if hours > 0 {
      components.append("\(hours) \(hours == 1 ? "hour" : "hours")")
    }
    if minutes > 0 {
      components.append(accessibleMinutes(minutes))
    }
    if remainingSeconds > 0 || components.isEmpty {
      components.append(
        "\(remainingSeconds) \(remainingSeconds == 1 ? "second" : "seconds")"
      )
    }

    return components.joined(separator: ", ")
  }

  private func accessibleMinutes(_ minutes: Int) -> String {
    "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
  }

  private func adjust(
    _ value: Binding<Int>,
    direction: AccessibilityAdjustmentDirection,
    step: Int,
    range: ClosedRange<Int>
  ) {
    switch direction {
    case .increment:
      value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
    case .decrement:
      value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
    @unknown default:
      break
    }
  }
}

#Preview {
  ContentView()
}
