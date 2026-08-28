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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .largeTitle) private var phaseFontSize: CGFloat = 50
  @ScaledMetric(relativeTo: .largeTitle) private var intervalFontSize: CGFloat = 72

  var body: some View {
    Group {
      switch session.status {
      case .idle:
        configurationView
      case .countingDown:
        countInView
      case .running, .paused:
        workoutView
      case .complete:
        completeView
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground).ignoresSafeArea())
    .tint(appTint)
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
        Task { await session.handleAppBecameActive() }
      }
    }
  }

  private var countInView: some View {
    VStack(spacing: 20) {
      Spacer()

      Text("GET READY")
        .font(.system(.largeTitle, design: .rounded, weight: .black))
        .accessibilityAddTraits(.isHeader)

      Text("\(session.countInRemaining)")
        .font(.system(size: 128, weight: .black, design: .rounded))
        .monospacedDigit()
        .contentTransition(.numericText())
        .accessibilityLabel(countInAccessibilityLabel)

      Text("COUNT-IN")
        .font(.caption.weight(.bold))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      Spacer()

      Button(role: .destructive) {
        session.stop()
      } label: {
        Text("Cancel")
          .font(.headline.weight(.semibold))
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.bordered)
      .tint(.red)
      .controlSize(.large)
      .frame(maxWidth: .infinity, minHeight: 54)
    }
  }

  private var configurationView: some View {
    VStack(spacing: 16) {
      GeometryReader { geometry in
        ScrollView {
          VStack(spacing: 0) {
            Text("SPLIT")
              .font(.system(size: 48, weight: .black, design: .rounded))
              .tracking(4)
              .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 32)

            workoutConfigurationPanel

            if let errorMessage = session.errorMessage {
              errorPanel(errorMessage)
                .padding(.top, 16)
            }

            Spacer(minLength: 32)
          }
          .padding(.top, 4)
          .frame(maxWidth: .infinity)
          .frame(minHeight: geometry.size.height)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
      }

      VStack(spacing: 10) {
        setupSummary
        startButton
      }
      .background(Color(.systemGroupedBackground))
    }
  }

  private var setupSummary: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        if configuration.warmupDuration > 0 {
          warmupSummaryValue
        }
        workoutSummaryValue
      }

      VStack(spacing: 4) {
        if configuration.warmupDuration > 0 {
          warmupSummaryValue
        }
        workoutSummaryValue
      }
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.horizontal, 4)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Workout summary")
    .accessibilityValue(
      "Warmup \(configuration.warmupDuration == 0 ? "none" : accessibleDuration(configuration.warmupDuration)). "
        + "Workout \(accessibleDuration(configuration.totalDuration))."
    )
  }

  private var warmupSummaryValue: some View {
    summaryValue(
      label: "WARMUP",
      value: formatted(configuration.warmupDuration)
    )
  }

  private var workoutSummaryValue: some View {
    summaryValue(
      label: "WORKOUT",
      value: formatted(configuration.totalDuration)
    )
  }

  private func summaryValue(label: String, value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 5) {
      Text(value)
        .font(.subheadline.weight(.bold).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(label)
        .font(.caption.weight(.bold))
        .foregroundStyle(.secondary)
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
          Text("START WORKOUT")
            .font(.headline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 56)
      .background(
        appTint,
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .foregroundStyle(prominentForegroundColor)
    .disabled(session.isBusy || !configuration.validationErrors.isEmpty)
    .opacity(session.isBusy || !configuration.validationErrors.isEmpty ? 0.45 : 1)
    .accessibilityLabel("Start workout")
    .accessibilityValue(startAccessibilityDescription)
  }

  private var workoutView: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 24) {
          Spacer(minLength: 8)

          if session.phase == .warmup {
            warmupProgress(
              diameter: min(max(240, geometry.size.width - 24), 320)
            )
          } else {
            splitWorkoutProgress(
              diameter: min(max(240, geometry.size.width - 24), 320)
            )
          }

          if let errorMessage = session.errorMessage {
            errorPanel(errorMessage)
          }

          Spacer(minLength: 16)

          workoutControls
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: geometry.size.height, alignment: .center)
      }
      .scrollIndicators(.hidden)
      .scrollBounceBehavior(.basedOnSize)
    }
  }

  private func warmupProgress(diameter: CGFloat) -> some View {
    VStack(spacing: 14) {
      ZStack {
        layeredProgressRing(
          diameter: diameter,
          stageFraction: intervalRemainingFraction,
          phase: .warmup
        )

        if !dynamicTypeSize.isAccessibilitySize {
          warmupProgressCenter
            .padding(36)
        }
      }
      .frame(width: diameter, height: diameter)

      if dynamicTypeSize.isAccessibilitySize {
        warmupProgressCenter
          .frame(maxWidth: .infinity)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(session.status == .paused ? "Warmup paused" : "Warmup")
    .accessibilityValue(
      "\(accessibleDuration(session.intervalRemaining)) remaining, "
        + "\(percentage(warmupElapsedFraction)) complete"
    )
  }

  private var warmupProgressCenter: some View {
    VStack(spacing: 6) {
      Text("WARMUP")
        .font(.system(.largeTitle, design: .rounded, weight: .black))
        .foregroundStyle(phaseAccentColor)

      Text(formatted(session.intervalRemaining))
        .font(
          .system(size: intervalFontSize * 0.72, weight: .black, design: .rounded)
            .monospacedDigit()
        )
        .lineLimit(1)
        .minimumScaleFactor(0.5)

      Text("REMAINING")
        .font(.caption.weight(.bold))
        .foregroundStyle(.secondary)
    }
  }

  private func splitWorkoutProgress(diameter: CGFloat) -> some View {
    VStack(spacing: 14) {
      ZStack {
        layeredProgressRing(
          diameter: diameter,
          stageFraction: intervalRemainingFraction,
          phase: session.phase,
          totalFraction: workoutRemainingFraction
        )

        if !dynamicTypeSize.isAccessibilitySize {
          splitProgressCenter
            .padding(34)
        }
      }
      .frame(width: diameter, height: diameter)
      .overlay(alignment: .topLeading) {
        splitTotalTime
          .frame(width: diameter)
          .offset(y: -62)
      }

      if dynamicTypeSize.isAccessibilitySize {
        splitProgressCenter
          .frame(maxWidth: .infinity)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      session.status == .paused
        ? "Split workout paused, \(session.phase.rawValue.capitalized) interval"
        : "Split workout, \(session.phase.rawValue.capitalized) interval"
    )
    .accessibilityValue(splitProgressAccessibilityValue)
  }

  private func layeredProgressRing(
    diameter: CGFloat,
    stageFraction: Double,
    phase: WorkoutPhase,
    totalFraction: Double? = nil
  ) -> some View {
    let totalLineWidth = min(20, max(15, diameter * 0.06))
    let stageLineWidth = totalLineWidth * 0.62

    return ZStack {
      Circle()
        .stroke(Color(.tertiarySystemFill), lineWidth: totalLineWidth)

      if let totalFraction {
        Circle()
          .trim(from: 0, to: totalFraction)
          .stroke(
            totalProgressShadeColor,
            style: StrokeStyle(lineWidth: totalLineWidth, lineCap: .round)
          )
          .rotationEffect(.degrees(-90))
      }

      Circle()
        .trim(from: 0, to: stageFraction)
        .stroke(
          progressColor(for: phase),
          style: StrokeStyle(lineWidth: stageLineWidth, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
    }
    .frame(width: diameter, height: diameter)
    .opacity(progressIndicatorOpacity)
    .animation(
      reduceMotion ? nil : .linear(duration: 0.2),
      value: totalFraction ?? 0
    )
    .animation(
      reduceMotion ? nil : .linear(duration: 0.2),
      value: stageFraction
    )
    .accessibilityHidden(true)
  }

  private var splitTotalTime: some View {
    HStack {
      VStack(alignment: .leading, spacing: 1) {
        Text("TOTAL TIME LEFT")
          .font(.caption.weight(.bold))
          .foregroundStyle(.secondary)
        Text(formatted(session.totalRemaining))
          .font(.system(.title, design: .rounded, weight: .black).monospacedDigit())
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }

      Spacer()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Total workout time remaining")
    .accessibilityValue(accessibleDuration(session.totalRemaining))
  }

  private var splitProgressCenter: some View {
    VStack(spacing: 4) {
      Text(session.phase.rawValue)
        .font(.system(size: phaseFontSize, weight: .black, design: .rounded))
        .foregroundStyle(phaseAccentColor)
        .lineLimit(1)
        .minimumScaleFactor(0.65)

      Text(formatted(session.intervalRemaining))
        .font(
          .system(size: phaseFontSize * 0.86, weight: .bold, design: .rounded)
            .monospacedDigit()
        )
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.65)

      Text("ROUND \(session.cycleNumber) OF \(session.cycleCount)")
        .font(.caption.weight(.bold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
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
          .frame(width: 112)
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
            .font(.headline.weight(.semibold))
        }
      }
      .frame(maxWidth: .infinity, minHeight: 56)
      .background(
        session.status == .running
          ? Color(.secondarySystemGroupedBackground)
          : appTint,
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .foregroundStyle(
      session.status == .running ? Color.primary : prominentForegroundColor
    )
    .disabled(session.isBusy)
    .opacity(session.isBusy ? 0.55 : 1)
  }

  private var stopButton: some View {
    Button(role: .destructive) {
      showsStopConfirmation = true
    } label: {
      Text("Stop")
        .font(.headline.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(
          Color.red.opacity(0.10),
          in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.red.opacity(0.38), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .foregroundStyle(.red)
    .disabled(session.isBusy)
    .opacity(session.isBusy ? 0.55 : 1)
  }

  private var completeView: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 20) {
          Spacer(minLength: 24)

          Text("DONE")
            .font(.system(size: 64, weight: .black, design: .rounded))
            .foregroundStyle(appTint)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)

          if let completedConfiguration = session.activeConfiguration {
            VStack(spacing: 5) {
              Text(formatted(completedConfiguration.workoutDuration))
                .font(
                  .system(.largeTitle, design: .rounded, weight: .black)
                    .monospacedDigit()
                )
              Text(completionDescription(completedConfiguration))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Workout complete")
            .accessibilityValue(
              "\(accessibleDuration(completedConfiguration.workoutDuration)). "
                + completionDescription(completedConfiguration)
            )
          }

          Spacer(minLength: 28)

          Button("Done") {
            session.stop()
          }
          .font(.headline.weight(.semibold))
          .buttonStyle(.borderedProminent)
          .foregroundStyle(prominentForegroundColor)
          .controlSize(.large)
          .frame(maxWidth: .infinity, minHeight: 54)

          Button("Repeat Workout") {
            repeatWorkout()
          }
          .font(.headline.weight(.semibold))
          .buttonStyle(.bordered)
          .controlSize(.large)
          .frame(maxWidth: .infinity, minHeight: 54)
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
    max(1, 3_600 / max(1, runSeconds + walkSeconds))
  }

  private var workoutConfigurationPanel: some View {
    VStack(spacing: 0) {
      intervalStepper("RUN", value: $runSeconds, accent: color(for: .run))
      validationMessage(for: [.invalidRunDuration, .runExceedsTotal])
        .padding(.horizontal, 16)
        .padding(.bottom, 12)

      configurationDivider

      intervalStepper("WALK", value: $walkSeconds, accent: color(for: .walk))
      validationMessage(for: [.invalidWalkDuration, .walkExceedsTotal])
        .padding(.horizontal, 16)
        .padding(.bottom, 12)

      configurationDivider
      cycleStepper
      configurationDivider
      warmupStepper
      validationMessage(for: [.invalidWarmupDuration])
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    .background(
      Color(.secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
  }

  private var configurationDivider: some View {
    Divider()
      .padding(.leading, 44)
  }

  private var cycleStepper: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          accessibleStepperHeader(
            title: "ROUNDS",
            accent: .secondary
          )
          Stepper(value: $cycleCount, in: 1...maximumCycleCount) {
            Text("\(cycleCount)")
              .font(.title3.weight(.bold).monospacedDigit())
          }
          .controlSize(.large)
        }
      } else {
        Stepper(value: $cycleCount, in: 1...maximumCycleCount) {
          standardStepperLabel(
            title: "ROUNDS",
            value: "\(cycleCount)",
            accent: .secondary
          )
        }
        .controlSize(.large)
      }
    }
    .padding(16)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Rounds")
    .accessibilityValue("\(cycleCount)")
    .accessibilityHint(
      "One round includes one run and one walk interval. Maximum \(maximumCycleCount)."
    )
    .accessibilityAdjustableAction { direction in
      adjust($cycleCount, direction: direction, step: 1, range: 1...maximumCycleCount)
    }
  }

  private var warmupStepper: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          accessibleStepperHeader(title: "WARMUP", accent: color(for: .warmup))
          Stepper(value: $warmupSeconds, in: 0...3_600, step: 150) {
            Text(warmupSeconds == 0 ? "None" : formatted(TimeInterval(warmupSeconds)))
              .font(.title3.weight(.bold).monospacedDigit())
          }
          .controlSize(.large)
        }
      } else {
        Stepper(value: $warmupSeconds, in: 0...3_600, step: 150) {
          standardStepperLabel(
            title: "WARMUP",
            value: warmupSeconds == 0 ? "None" : formatted(TimeInterval(warmupSeconds)),
            accent: color(for: .warmup)
          )
        }
        .controlSize(.large)
      }
    }
    .padding(16)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Warmup")
    .accessibilityValue(
      warmupSeconds == 0 ? "None" : accessibleDuration(TimeInterval(warmupSeconds))
    )
    .accessibilityHint("Adjusts in 2-minute 30-second increments.")
    .accessibilityAdjustableAction { direction in
      adjust($warmupSeconds, direction: direction, step: 150, range: 0...3_600)
    }
  }

  private func intervalStepper(
    _ title: String,
    value: Binding<Int>,
    accent: Color
  ) -> some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          accessibleStepperHeader(title: title, accent: accent)
          Stepper(value: value, in: 60...1_800, step: 15) {
            Text(formatted(TimeInterval(value.wrappedValue)))
              .font(.title3.weight(.bold).monospacedDigit())
          }
          .controlSize(.large)
        }
      } else {
        Stepper(value: value, in: 60...1_800, step: 15) {
          standardStepperLabel(
            title: title,
            value: formatted(TimeInterval(value.wrappedValue)),
            accent: accent
          )
        }
        .controlSize(.large)
      }
    }
    .padding(16)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title.capitalized)
    .accessibilityValue(accessibleDuration(TimeInterval(value.wrappedValue)))
    .accessibilityHint("Adjusts in 15-second increments.")
    .accessibilityAdjustableAction { direction in
      adjust(value, direction: direction, step: 15, range: 60...1_800)
    }
  }

  private func accessibleStepperHeader(title: String, accent: Color) -> some View {
    HStack(spacing: 10) {
      Circle()
        .fill(accent)
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
      Text(title)
        .font(.headline)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func standardStepperLabel(
    title: String,
    value: String,
    accent: Color
  ) -> some View {
    HStack(spacing: 10) {
      Circle()
        .fill(accent)
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
      Text(title)
        .font(.subheadline.weight(.semibold))
      Spacer(minLength: 8)
      Text(value)
        .font(.title3.weight(.bold).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
  }

  @ViewBuilder
  private func validationMessage(for errors: [WorkoutConfigurationError]) -> some View {
    if let error = configuration.validationErrors.first(where: errors.contains),
      let message = error.errorDescription
    {
      Text(message)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.red)
        .padding(.horizontal, 4)
        .accessibilityLabel("Error. \(message)")
    }
  }

  private func errorPanel(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label {
        Text(message)
          .fixedSize(horizontal: false, vertical: true)
      } icon: {
        Image(systemName: "exclamationmark.circle.fill")
          .foregroundStyle(.orange)
      }
      .font(.footnote.weight(.semibold))

      if session.shouldOfferNotificationSettings {
        Button("Open Settings") {
          session.openNotificationSettings()
        }
        .font(.footnote.weight(.bold))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    .accessibilityElement(children: .contain)
  }

  private var countInAccessibilityLabel: String {
    let seconds = session.countInRemaining
    return "Workout starts in \(seconds) \(seconds == 1 ? "second" : "seconds")"
  }

  private var startAccessibilityDescription: String {
    let split = "\(accessibleDuration(configuration.totalDuration)) split"
    guard warmupSeconds > 0 else { return split }
    return "\(split), plus \(accessibleDuration(TimeInterval(warmupSeconds))) warmup"
  }

  private func completionDescription(_ configuration: WorkoutConfiguration) -> String {
    let cycleLength = configuration.runDuration + configuration.walkDuration
    let cycles = max(1, Int(configuration.totalDuration / max(1, cycleLength)))
    let split = "\(cycles) \(cycles == 1 ? "cycle" : "cycles")"
    guard configuration.warmupDuration > 0 else { return split }
    return "\(split) · \(formatted(configuration.warmupDuration)) warmup"
  }

  private func repeatWorkout() {
    guard let completedConfiguration = session.activeConfiguration else { return }
    session.stop()
    Task {
      await session.start(configuration: completedConfiguration)
    }
  }

  private var workoutRemainingFraction: Double {
    guard session.workoutDuration > 0 else { return 0 }
    return min(1, max(0, session.totalRemaining / session.workoutDuration))
  }

  private var intervalRemainingFraction: Double {
    guard session.intervalDuration > 0 else { return 0 }
    return min(1, max(0, session.intervalRemaining / session.intervalDuration))
  }

  private var warmupElapsedFraction: Double {
    guard session.phase == .warmup, session.intervalDuration > 0 else { return 0 }
    return 1 - intervalRemainingFraction
  }

  private var progressIndicatorOpacity: Double {
    session.status == .paused ? 0.42 : 1
  }

  private func percentage(_ fraction: Double) -> String {
    "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
  }

  private var splitProgressAccessibilityValue: String {
    return "\(accessibleDuration(session.totalRemaining)) left. "
      + "\(accessibleDuration(session.intervalRemaining)) left in this interval. "
      + "Round \(session.cycleNumber) of \(session.cycleCount)."
  }

  private var appTint: Color {
    colorScheme == .dark
      ? Color(red: 0.00, green: 0.68, blue: 0.68)
      : Color(red: 0.00, green: 0.44, blue: 0.44)
  }

  private var totalProgressShadeColor: Color {
    Color.primary.opacity(colorScheme == .dark ? 0.20 : 0.14)
  }

  private func progressColor(for phase: WorkoutPhase) -> Color {
    session.status == .paused ? .secondary : color(for: phase)
  }

  private var prominentForegroundColor: Color {
    colorScheme == .dark ? .black : .white
  }

  private var phaseAccentColor: Color {
    if session.status == .paused { return .secondary }

    return color(for: session.phase)
  }

  private func color(for phase: WorkoutPhase) -> Color {
    switch (phase, colorScheme) {
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
    warmupSeconds = normalized(warmupSeconds, range: 0...3_600, step: 150)
    runSeconds = normalized(runSeconds, range: 60...1_800, step: 15)
    walkSeconds = normalized(walkSeconds, range: 60...1_800, step: 15)
    clampCycleCount()
  }

  private func normalized(_ value: Int, range: ClosedRange<Int>, step: Int) -> Int {
    let clamped = min(range.upperBound, max(range.lowerBound, value))
    let offset = clamped - range.lowerBound
    return range.lowerBound + Int(round(Double(offset) / Double(step))) * step
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
