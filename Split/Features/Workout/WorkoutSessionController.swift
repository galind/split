import Combine
import Foundation
import UIKit

@MainActor
final class WorkoutSessionController: ObservableObject {
  enum Status: Equatable {
    case idle
    case running
    case paused
    case complete
  }

  @Published private(set) var status: Status = .idle
  @Published private(set) var phase: WorkoutPhase = .run
  @Published private(set) var intervalRemaining: TimeInterval = 0
  @Published private(set) var totalRemaining: TimeInterval = 0
  @Published private(set) var isBusy = false
  @Published var errorMessage: String?

  private let notificationScheduler = NotificationScheduler()
  private var plan: IntervalPlan?
  private var elapsedBeforeRun: TimeInterval = 0
  private var runStartedAt: Date?
  private var timer: Timer?

  func start(configuration: WorkoutConfiguration) async {
    guard status == .idle, !isBusy else { return }
    isBusy = true
    defer { isBusy = false }
    errorMessage = nil

    do {
      try configuration.validate()
      try await notificationScheduler.ensureSoundPermission()
      let newPlan = IntervalPlan(configuration: configuration)
      let startDate = Date()
      try await notificationScheduler.schedule(
        plan: newPlan,
        elapsed: 0,
        anchoredAt: startDate
      )

      plan = newPlan
      elapsedBeforeRun = 0
      runStartedAt = startDate
      status = .running
      updateDisplay(at: startDate, providesHaptic: false)
      startTimer()
    } catch {
      notificationScheduler.cancelPending()
      errorMessage = error.localizedDescription
    }
  }

  func pause() {
    guard status == .running else { return }
    let now = Date()
    elapsedBeforeRun = elapsed(at: now)
    runStartedAt = nil
    status = .paused
    stopTimer()
    updateDisplay(at: now, providesHaptic: false)

    notificationScheduler.cancelPending()
  }

  func resume() async {
    guard status == .paused, !isBusy, let plan else { return }
    isBusy = true
    defer { isBusy = false }
    errorMessage = nil

    do {
      try await notificationScheduler.ensureSoundPermission()
      let resumeDate = Date()
      try await notificationScheduler.schedule(
        plan: plan,
        elapsed: elapsedBeforeRun,
        anchoredAt: resumeDate
      )
      runStartedAt = resumeDate
      status = .running
      updateDisplay(at: resumeDate, providesHaptic: false)
      startTimer()
    } catch {
      notificationScheduler.cancelPending()
      errorMessage = error.localizedDescription
    }
  }

  func stop() {
    stopTimer()
    plan = nil
    elapsedBeforeRun = 0
    runStartedAt = nil
    status = .idle
    errorMessage = nil
    intervalRemaining = 0
    totalRemaining = 0

    notificationScheduler.cancelPending()
    notificationScheduler.clearDelivered()
  }

  func refresh() {
    guard status == .running else { return }
    updateDisplay(at: Date(), providesHaptic: true)
  }

  func openNotificationSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
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
    intervalRemaining = snapshot.intervalRemaining
    totalRemaining = snapshot.totalRemaining

    if snapshot.isComplete {
      finish()
    } else if providesHaptic, previousPhase != snapshot.phase {
      let generator = UINotificationFeedbackGenerator()
      generator.notificationOccurred(snapshot.phase == .run ? .success : .warning)
    }
  }

  private func finish() {
    elapsedBeforeRun = plan?.configuration.workoutDuration ?? elapsedBeforeRun
    runStartedAt = nil
    intervalRemaining = 0
    totalRemaining = 0
    status = .complete
    stopTimer()
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
}
