import Foundation
import XCTest

@testable import SplitCore

final class ActiveWorkoutSessionTests: XCTestCase {
  private let configuration = WorkoutConfiguration(
    cycles: 2,
    warmupSeconds: 150,
    runSeconds: 60,
    walkSeconds: 75
  )

  func testRunningSessionReconstructsElapsedTimeFromAnchor() {
    let anchor = Date(timeIntervalSinceReferenceDate: 1_000)
    let session = ActiveWorkoutSession(
      configuration: configuration,
      state: .running,
      elapsedBeforeRun: 25,
      runStartedAt: anchor
    )

    XCTAssertEqual(session.elapsed(at: anchor.addingTimeInterval(40)), 65)
    XCTAssertEqual(session.resolvedState(at: anchor.addingTimeInterval(40)), .running)
  }

  func testCountInStaysAtZeroElapsedBeforeFutureAnchor() {
    let anchor = Date(timeIntervalSinceReferenceDate: 1_000)
    let session = ActiveWorkoutSession(
      configuration: configuration,
      state: .countingDown,
      elapsedBeforeRun: 0,
      runStartedAt: anchor
    )

    XCTAssertEqual(session.elapsed(at: anchor.addingTimeInterval(-3)), 0)
    XCTAssertEqual(session.resolvedState(at: anchor.addingTimeInterval(-3)), .countingDown)
  }

  func testCountInBecomesRunningAtItsAnchor() {
    let anchor = Date(timeIntervalSinceReferenceDate: 1_000)
    let session = ActiveWorkoutSession(
      configuration: configuration,
      state: .countingDown,
      elapsedBeforeRun: 0,
      runStartedAt: anchor
    )

    XCTAssertEqual(session.resolvedState(at: anchor), .running)
    XCTAssertEqual(session.elapsed(at: anchor.addingTimeInterval(8)), 8)
  }

  func testRunningSessionDoesNotSubtractTimeWhenClockMovesBackwards() {
    let anchor = Date(timeIntervalSinceReferenceDate: 1_000)
    let session = ActiveWorkoutSession(
      configuration: configuration,
      state: .running,
      elapsedBeforeRun: 25,
      runStartedAt: anchor
    )

    XCTAssertEqual(session.elapsed(at: anchor.addingTimeInterval(-60)), 25)
  }

  func testPausedSessionKeepsElapsedTimeAcrossRelaunch() {
    let session = ActiveWorkoutSession(
      configuration: configuration,
      state: .paused,
      elapsedBeforeRun: 91,
      runStartedAt: nil
    )

    XCTAssertEqual(session.elapsed(at: .distantFuture), 91)
    XCTAssertEqual(session.resolvedState(at: .distantFuture), .paused)
  }

  func testExpiredRunningSessionRestoresAsComplete() {
    let anchor = Date(timeIntervalSinceReferenceDate: 1_000)
    let session = ActiveWorkoutSession(
      configuration: configuration,
      state: .running,
      elapsedBeforeRun: 0,
      runStartedAt: anchor
    )

    let afterWorkout = anchor.addingTimeInterval(configuration.workoutDuration + 1)
    XCTAssertEqual(session.resolvedState(at: afterWorkout), .complete)
  }

  func testStoreRoundTripsConfigurationIdentityAndTimingState() throws {
    let (defaults, store) = makeStore()
    defer { defaults.removeObject(forKey: ActiveWorkoutSessionStore.defaultKey) }
    let id = UUID()
    let anchor = Date(timeIntervalSinceReferenceDate: 1_000)
    let session = ActiveWorkoutSession(
      id: id,
      configuration: configuration,
      state: .running,
      elapsedBeforeRun: 37,
      runStartedAt: anchor
    )

    store.save(session)

    XCTAssertEqual(store.load(), session)
    XCTAssertEqual(store.load()?.id, id)
  }

  func testStoreRejectsAndClearsCorruptState() {
    let (defaults, store) = makeStore()
    defer { defaults.removeObject(forKey: ActiveWorkoutSessionStore.defaultKey) }
    defaults.set(Data("not-json".utf8), forKey: ActiveWorkoutSessionStore.defaultKey)

    XCTAssertNil(store.load())
    XCTAssertNil(defaults.object(forKey: ActiveWorkoutSessionStore.defaultKey))
  }

  func testStructurallyInconsistentSessionIsInvalid() {
    let pausedWithRunningAnchor = ActiveWorkoutSession(
      configuration: configuration,
      state: .paused,
      elapsedBeforeRun: 10,
      runStartedAt: Date()
    )
    let runningWithoutAnchor = ActiveWorkoutSession(
      configuration: configuration,
      state: .running,
      elapsedBeforeRun: 10,
      runStartedAt: nil
    )
    let countInWithoutAnchor = ActiveWorkoutSession(
      configuration: configuration,
      state: .countingDown,
      elapsedBeforeRun: 0,
      runStartedAt: nil
    )

    XCTAssertFalse(pausedWithRunningAnchor.isValid)
    XCTAssertFalse(runningWithoutAnchor.isValid)
    XCTAssertFalse(countInWithoutAnchor.isValid)
  }

  private func makeStore() -> (UserDefaults, ActiveWorkoutSessionStore) {
    let name = "ActiveWorkoutSessionTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (defaults, ActiveWorkoutSessionStore(defaults: defaults))
  }
}
