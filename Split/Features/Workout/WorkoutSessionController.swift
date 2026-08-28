import Combine
import Foundation
import UIKit

@MainActor
final class WorkoutSessionController: ObservableObject {
  enum Status: Equatable {
    case idle
    case countingDown
    case running
    case paused
    case complete
  }

  @Published private(set) var status: Status = .idle
  @Published private(set) var phase: WorkoutPhase = .run
  @Published private(set) var intervalDuration: TimeInterval = 0
  @Published private(set) var intervalRemaining: TimeInterval = 0
  @Published private(set) var totalRemaining: TimeInterval = 0
  @Published private(set) var workoutDuration: TimeInterval = 0
  @Published private(set) var cycleNumber = 0
  @Published private(set) var cycleCount = 0
  @Published private(set) var countInRemaining = 0
  @Published private(set) var isBusy = false
  @Published private(set) var shouldOfferNotificationSettings = false
  @Published var errorMessage: String?

  private let notificationScheduler: NotificationScheduler
  private let sessionStore: ActiveWorkoutSessionStore
  private var sessionID: UUID?
  private var plan: IntervalPlan?
  private var elapsedBeforeRun: TimeInterval = 0
  private var runStartedAt: Date?
  private var timer: Timer?
  private var notificationReconciliationTask: Task<Void, Never>?
  private var announcementTask: Task<Void, Never>?
  private static let countInDuration: TimeInterval = 5

  var activeConfiguration: WorkoutConfiguration? {
    plan?.configuration
  }

  init(
    notificationScheduler: NotificationScheduler = NotificationScheduler(),
    sessionStore: ActiveWorkoutSessionStore = ActiveWorkoutSessionStore()
  ) {
    self.notificationScheduler = notificationScheduler
    self.sessionStore = sessionStore
    restoreSession()

    notificationReconciliationTask = Task { [weak self] in
      await self?.reconcileRestoredNotifications()
    }
  }

  func start(configuration: WorkoutConfiguration) async {
    guard status == .idle, !isBusy else { return }
    notificationReconciliationTask?.cancel()
    notificationReconciliationTask = nil
    isBusy = true
    defer { isBusy = false }
    errorMessage = nil
    shouldOfferNotificationSettings = false
    let newSessionID = UUID()
    var enteredCountIn = false

    do {
      try configuration.validate()
      try await notificationScheduler.ensureSoundPermission()
      let newPlan = IntervalPlan(configuration: configuration)
      let startDate = Date().addingTimeInterval(Self.countInDuration)
      await notificationScheduler.cancelStalePending()

      sessionID = newSessionID
      plan = newPlan
      workoutDuration = newPlan.configuration.totalDuration
      elapsedBeforeRun = 0
      runStartedAt = startDate
      status = .countingDown
      countInRemaining = Int(Self.countInDuration)
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      enteredCountIn = true
      persistSession()
      startTimer()

      try await notificationScheduler.schedule(
        plan: newPlan,
        sessionID: newSessionID,
        elapsed: 0,
        anchoredAt: startDate
      )

      guard sessionID == newSessionID, status == .countingDown || status == .running else {
        notificationScheduler.cancelPending(plan: newPlan, sessionID: newSessionID)
        return
      }
      refresh()
    } catch {
      if enteredCountIn, sessionID != newSessionID {
        return
      }
      let failedPlan = plan
      let failedSessionID = sessionID
      stopTimer()
      plan = nil
      sessionID = nil
      elapsedBeforeRun = 0
      runStartedAt = nil
      status = .idle
      countInRemaining = 0
      sessionStore.clear()
      if let failedPlan, let failedSessionID {
        notificationScheduler.cancelPending(plan: failedPlan, sessionID: failedSessionID)
      }
      present(error)
    }
  }

  func pause() {
    guard status == .running else { return }
    let now = Date()
    elapsedBeforeRun = elapsed(at: now)
    runStartedAt = nil
    status = .paused
    persistSession()
    stopTimer()
    updateDisplay(at: now, providesHaptic: false)

    if let plan, let sessionID {
      notificationScheduler.cancelPending(plan: plan, sessionID: sessionID)
    }
    announce("Workout paused")
  }

  func resume() async {
    guard status == .paused, !isBusy, let plan else { return }
    isBusy = true
    defer { isBusy = false }
    errorMessage = nil
    shouldOfferNotificationSettings = false

    do {
      try await notificationScheduler.ensureSoundPermission()
      let resumeDate = Date()
      let resumedSessionID = sessionID ?? UUID()
      try await notificationScheduler.schedule(
        plan: plan,
        sessionID: resumedSessionID,
        elapsed: elapsedBeforeRun,
        anchoredAt: resumeDate
      )
      sessionID = resumedSessionID
      runStartedAt = resumeDate
      status = .running
      persistSession()
      updateDisplay(at: resumeDate, providesHaptic: false)
      startTimer()
      announce("Workout resumed. \(phase.rawValue.capitalized) interval")
    } catch {
      if let sessionID {
        notificationScheduler.cancelPending(plan: plan, sessionID: sessionID)
      }
      present(error)
    }
  }

  func stop() {
    notificationReconciliationTask?.cancel()
    notificationReconciliationTask = nil
    announcementTask?.cancel()
    announcementTask = nil
    stopTimer()
    let stoppedPlan = plan
    let stoppedSessionID = sessionID
    plan = nil
    sessionID = nil
    elapsedBeforeRun = 0
    runStartedAt = nil
    status = .idle
    errorMessage = nil
    shouldOfferNotificationSettings = false
    intervalDuration = 0
    intervalRemaining = 0
    totalRemaining = 0
    workoutDuration = 0
    cycleNumber = 0
    cycleCount = 0
    countInRemaining = 0
    sessionStore.clear()

    if let stoppedPlan, let stoppedSessionID {
      notificationScheduler.cancelPending(plan: stoppedPlan, sessionID: stoppedSessionID)
      Task {
        await notificationScheduler.clearDelivered(sessionID: stoppedSessionID)
      }
    }
  }

  func refresh() {
    guard status == .countingDown || status == .running else { return }
    if status == .countingDown {
      updateCountIn(at: Date())
      return
    }
    updateDisplay(at: Date(), providesHaptic: true)
  }

  func openNotificationSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }

  func handleAppBecameActive() async {
    refresh()
    guard shouldOfferNotificationSettings else { return }

    do {
      try await notificationScheduler.ensureSoundPermission()
      errorMessage = nil
      shouldOfferNotificationSettings = false
    } catch {
      present(error, announces: false)
    }
  }

  private func elapsed(at date: Date) -> TimeInterval {
    guard let runStartedAt else { return elapsedBeforeRun }
    return elapsedBeforeRun + max(0, date.timeIntervalSince(runStartedAt))
  }

  private func updateDisplay(at date: Date, providesHaptic: Bool) {
    guard let plan else { return }
    let previousPhase = phase
    let snapshot = plan.snapshot(at: elapsed(at: date))
    phase = snapshot.phase
    intervalDuration = snapshot.intervalDuration
    intervalRemaining = snapshot.intervalRemaining
    totalRemaining = snapshot.totalRemaining
    workoutDuration = plan.configuration.totalDuration
    cycleNumber = snapshot.cycleNumber
    cycleCount = snapshot.cycleCount

    if snapshot.isComplete {
      finish(providesFeedback: providesHaptic)
    } else if providesHaptic, previousPhase != snapshot.phase {
      let generator = UINotificationFeedbackGenerator()
      generator.notificationOccurred(snapshot.phase == .run ? .success : .warning)
      announce(
        "\(snapshot.phase.rawValue.capitalized) interval. "
          + "\(accessibleDuration(snapshot.intervalRemaining)) remaining",
        after: 1.5
      )
    }
  }

  private func updateCountIn(at date: Date) {
    guard let runStartedAt else { return }
    let previousRemaining = countInRemaining
    countInRemaining = max(0, Int(ceil(runStartedAt.timeIntervalSince(date))))

    if date >= runStartedAt {
      countInRemaining = 0
      status = .running
      persistSession()
      updateDisplay(at: date, providesHaptic: false)
      announce("\(phase.rawValue.capitalized) started", after: phase == .run ? 1.5 : 0)
    } else if previousRemaining != countInRemaining {
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
  }

  private func finish(providesFeedback: Bool) {
    elapsedBeforeRun = plan?.configuration.workoutDuration ?? elapsedBeforeRun
    runStartedAt = nil
    intervalRemaining = 0
    totalRemaining = 0
    status = .complete
    stopTimer()
    persistSession()
    if providesFeedback {
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      announce("Workout complete", after: 1.5)
    }
  }

  private func restoreSession() {
    guard let savedSession = sessionStore.load() else { return }

    let restoredPlan = IntervalPlan(configuration: savedSession.configuration)
    let now = Date()
    sessionID = savedSession.id
    plan = restoredPlan
    workoutDuration = restoredPlan.configuration.totalDuration

    switch savedSession.resolvedState(at: now) {
    case .countingDown:
      elapsedBeforeRun = savedSession.elapsedBeforeRun
      runStartedAt = savedSession.runStartedAt
      status = .countingDown
      updateCountIn(at: now)
      startTimer()
    case .running:
      elapsedBeforeRun = savedSession.elapsedBeforeRun
      runStartedAt = savedSession.runStartedAt
      status = .running
      updateDisplay(at: now, providesHaptic: false)
      if status == .running {
        startTimer()
      }
    case .paused:
      elapsedBeforeRun = savedSession.elapsedBeforeRun
      runStartedAt = nil
      status = .paused
      updateDisplay(at: now, providesHaptic: false)
    case .complete:
      elapsedBeforeRun = restoredPlan.configuration.workoutDuration
      runStartedAt = nil
      status = .complete
      updateDisplay(at: now, providesHaptic: false)
      persistSession()
    }
  }

  private func reconcileRestoredNotifications() async {
    guard let restoredPlan = plan, let restoredSessionID = sessionID else {
      await notificationScheduler.cancelStalePending()
      return
    }

    guard status == .countingDown || status == .running else {
      await notificationScheduler.cancelStalePending()
      return
    }

    await notificationScheduler.cancelStalePending(keeping: restoredSessionID)
    guard restorationIsCurrent(sessionID: restoredSessionID) else { return }

    do {
      try await notificationScheduler.ensureSoundPermission()
      guard restorationIsCurrent(sessionID: restoredSessionID) else { return }

      let now = Date()
      let isCountingDown = status == .countingDown
      try await notificationScheduler.schedule(
        plan: restoredPlan,
        sessionID: restoredSessionID,
        elapsed: isCountingDown ? 0 : elapsed(at: now),
        anchoredAt: isCountingDown ? (runStartedAt ?? now) : now
      )
      guard restorationIsCurrent(sessionID: restoredSessionID) else {
        notificationScheduler.cancelPending(
          plan: restoredPlan,
          sessionID: restoredSessionID
        )
        return
      }
    } catch {
      notificationScheduler.cancelPending(plan: restoredPlan, sessionID: restoredSessionID)
      guard restorationIsCurrent(sessionID: restoredSessionID) else { return }
      pauseForCueFailure(at: Date())
      present(error)
    }
  }

  private func restorationIsCurrent(sessionID expectedSessionID: UUID) -> Bool {
    !Task.isCancelled && sessionID == expectedSessionID
      && (status == .countingDown || status == .running)
  }

  private func pauseForCueFailure(at date: Date) {
    elapsedBeforeRun = elapsed(at: date)
    runStartedAt = nil
    status = .paused
    countInRemaining = 0
    stopTimer()
    updateDisplay(at: date, providesHaptic: false)
    persistSession()
  }

  private func persistSession() {
    guard let plan, let sessionID else { return }

    let storedState: ActiveWorkoutSession.State
    switch status {
    case .countingDown: storedState = .countingDown
    case .running: storedState = .running
    case .paused: storedState = .paused
    case .complete: storedState = .complete
    case .idle: return
    }

    sessionStore.save(
      ActiveWorkoutSession(
        id: sessionID,
        configuration: plan.configuration,
        state: storedState,
        elapsedBeforeRun: elapsedBeforeRun,
        runStartedAt: runStartedAt
      )
    )
  }

  private func startTimer() {
    stopTimer()
    let newTimer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.refresh()
      }
    }
    timer = newTimer
    RunLoop.main.add(newTimer, forMode: .common)
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func present(_ error: Error, announces: Bool = true) {
    errorMessage = error.localizedDescription
    shouldOfferNotificationSettings = error is NotificationPermissionError
    if announces {
      announce(error.localizedDescription)
    }
  }

  private func announce(_ message: String, after delay: TimeInterval = 0) {
    guard UIAccessibility.isVoiceOverRunning else { return }
    announcementTask?.cancel()
    announcementTask = Task { @MainActor in
      if delay > 0 {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      }
      guard !Task.isCancelled else { return }
      UIAccessibility.post(notification: .announcement, argument: message)
    }
  }

  private func accessibleDuration(_ duration: TimeInterval) -> String {
    let seconds = max(0, Int(ceil(duration)))
    let minutes = seconds / 60
    let remainingSeconds = seconds % 60

    if minutes == 0 {
      return "\(remainingSeconds) \(remainingSeconds == 1 ? "second" : "seconds")"
    }
    if remainingSeconds == 0 {
      return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }
    return "\(minutes) minutes, \(remainingSeconds) seconds"
  }
}
