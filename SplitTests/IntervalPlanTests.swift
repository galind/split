import XCTest

@testable import SplitCore

final class IntervalPlanTests: XCTestCase {
  func testDefaultPlanAlternatesEveryMinute() {
    let plan = IntervalPlan(
      configuration: WorkoutConfiguration(totalMinutes: 30, runMinutes: 1, walkMinutes: 1)
    )

    XCTAssertEqual(plan.segments.count, 30)
    XCTAssertEqual(plan.snapshot(at: 0).phase, .run)
    XCTAssertEqual(plan.snapshot(at: 59).intervalRemaining, 1)
    XCTAssertEqual(plan.snapshot(at: 60).phase, .walk)
    XCTAssertEqual(plan.snapshot(at: 120).phase, .run)
  }

  func testWarmupOccursBeforeSplitProcess() {
    let plan = IntervalPlan(
      configuration: WorkoutConfiguration(
        totalMinutes: 5,
        warmupSeconds: 150,
        runMinutes: 1,
        walkMinutes: 1
      )
    )

    XCTAssertEqual(plan.snapshot(at: 0).phase, .warmup)
    XCTAssertEqual(plan.snapshot(at: 149).intervalRemaining, 1)
    XCTAssertEqual(plan.snapshot(at: 150).phase, .run)
    XCTAssertEqual(plan.snapshot(at: 210).phase, .walk)
    XCTAssertEqual(
      Array(plan.cues(after: 0).prefix(2)),
      [.warmupWarning(at: 90), .transition(to: .run, at: 150)]
    )
  }

  func testWarmupIsExcludedFromConfiguredSplitDuration() {
    let configuration = WorkoutConfiguration(
      totalMinutes: 5,
      warmupSeconds: 150,
      runMinutes: 1,
      walkMinutes: 1
    )
    let plan = IntervalPlan(configuration: configuration)

    XCTAssertEqual(configuration.totalDuration, 300)
    XCTAssertEqual(configuration.workoutDuration, 450)
    XCTAssertEqual(plan.snapshot(at: 150).totalRemaining, 300)
    XCTAssertEqual(plan.segments.last?.end, 450)
  }

  func testFifteenSecondRunAndWalkDurations() {
    let plan = IntervalPlan(
      configuration: WorkoutConfiguration(
        totalMinutes: 5,
        runSeconds: 75,
        walkSeconds: 105
      )
    )

    XCTAssertEqual(plan.segments[0], WorkoutSegment(phase: .run, start: 0, end: 75))
    XCTAssertEqual(plan.segments[1], WorkoutSegment(phase: .walk, start: 75, end: 180))
    XCTAssertEqual(plan.segments[2], WorkoutSegment(phase: .run, start: 180, end: 255))
  }

  func testRejectsRunOrWalkLongerThanSplitDuration() {
    let longRun = WorkoutConfiguration(totalMinutes: 1, runSeconds: 75, walkSeconds: 60)
    let longWalk = WorkoutConfiguration(totalMinutes: 1, runSeconds: 60, walkSeconds: 75)

    XCTAssertEqual(longRun.validationErrors, [.runExceedsTotal])
    XCTAssertEqual(longWalk.validationErrors, [.walkExceedsTotal])
    XCTAssertThrowsError(try longRun.validate())
    XCTAssertThrowsError(try longWalk.validate())
  }

  func testCycleBasedConfigurationDerivesCompleteSplitDuration() {
    let configuration = WorkoutConfiguration(
      cycles: 4,
      runSeconds: 75,
      walkSeconds: 60
    )
    let plan = IntervalPlan(configuration: configuration)

    XCTAssertEqual(configuration.totalDuration, 540)
    XCTAssertNoThrow(try configuration.validate())
    XCTAssertEqual(plan.segments.count, 8)
    XCTAssertEqual(plan.segments.last?.end, 540)
  }

  func testFinalIntervalIsClippedToTotalDuration() {
    let plan = IntervalPlan(
      configuration: WorkoutConfiguration(totalMinutes: 5, runMinutes: 2, walkMinutes: 2)
    )

    XCTAssertEqual(
      plan.segments,
      [
        WorkoutSegment(phase: .run, start: 0, end: 120),
        WorkoutSegment(phase: .walk, start: 120, end: 240),
        WorkoutSegment(phase: .run, start: 240, end: 300),
      ]
    )
  }

  func testCuesAfterPauseOnlyContainFutureEvents() {
    let plan = IntervalPlan(
      configuration: WorkoutConfiguration(totalMinutes: 5, runMinutes: 1, walkMinutes: 1)
    )

    XCTAssertEqual(
      plan.cues(after: 75),
      [
        .transition(to: .run, at: 120),
        .transition(to: .walk, at: 180),
        .transition(to: .run, at: 240),
        .complete(at: 300),
      ]
    )
  }

  func testCuesAfterPausePastWarmupRebuildFromPausedPosition() {
    let plan = IntervalPlan(
      configuration: WorkoutConfiguration(
        totalMinutes: 5,
        warmupSeconds: 150,
        runMinutes: 1,
        walkMinutes: 1
      )
    )

    XCTAssertEqual(
      plan.cues(after: 180),
      [
        .transition(to: .walk, at: 210),
        .transition(to: .run, at: 270),
        .transition(to: .walk, at: 330),
        .transition(to: .run, at: 390),
        .complete(at: 450),
      ]
    )
  }

  func testWarmupWarningIsOnlyScheduledWhileItIsStillUpcoming() {
    let plan = IntervalPlan(
      configuration: WorkoutConfiguration(
        totalMinutes: 5,
        warmupSeconds: 150,
        runMinutes: 1,
        walkMinutes: 1
      )
    )

    XCTAssertTrue(plan.cues(after: 89).contains(.warmupWarning(at: 90)))
    XCTAssertFalse(plan.cues(after: 90).contains(.warmupWarning(at: 90)))
  }

  func testSnapshotCompletesAtTotalDuration() {
    let plan = IntervalPlan(
      configuration: WorkoutConfiguration(totalMinutes: 1, runMinutes: 1, walkMinutes: 1)
    )

    let snapshot = plan.snapshot(at: 60)
    XCTAssertTrue(snapshot.isComplete)
    XCTAssertEqual(snapshot.intervalRemaining, 0)
    XCTAssertEqual(snapshot.totalRemaining, 0)
  }

  func testCompletionIncludesWarmupAndFullSplitDuration() {
    let plan = IntervalPlan(
      configuration: WorkoutConfiguration(
        totalMinutes: 1,
        warmupSeconds: 150,
        runMinutes: 1,
        walkMinutes: 1
      )
    )

    XCTAssertFalse(plan.snapshot(at: 209).isComplete)
    XCTAssertTrue(plan.snapshot(at: 210).isComplete)
    XCTAssertEqual(plan.cues(after: 0).last, .complete(at: 210))
  }

  func testWarmupRequiresTwoMinuteThirtySecondIncrements() {
    let invalid = WorkoutConfiguration(
      totalMinutes: 5,
      warmupSeconds: 60,
      runMinutes: 1,
      walkMinutes: 1
    )
    let valid = WorkoutConfiguration(
      totalMinutes: 5,
      warmupSeconds: 150,
      runMinutes: 1,
      walkMinutes: 1
    )

    XCTAssertEqual(invalid.validationErrors, [.invalidWarmupDuration])
    XCTAssertTrue(valid.validationErrors.isEmpty)
  }
}
