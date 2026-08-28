import Foundation

enum WorkoutPhase: String, Equatable {
  case warmup = "WARMUP"
  case run = "RUN"
  case walk = "WALK"
}

struct WorkoutSegment: Equatable {
  let phase: WorkoutPhase
  let start: TimeInterval
  let end: TimeInterval
}

struct WorkoutSnapshot: Equatable {
  let phase: WorkoutPhase
  let intervalRemaining: TimeInterval
  let totalRemaining: TimeInterval
  let isComplete: Bool
}

enum WorkoutCue: Equatable {
  case warmupWarning(at: TimeInterval)
  case transition(to: WorkoutPhase, at: TimeInterval)
  case complete(at: TimeInterval)
}

struct IntervalPlan: Equatable {
  let configuration: WorkoutConfiguration
  let segments: [WorkoutSegment]

  init(configuration: WorkoutConfiguration) {
    precondition(configuration.validationErrors.isEmpty)

    self.configuration = configuration

    var generated: [WorkoutSegment] = []
    if configuration.warmupDuration > 0 {
      generated.append(
        WorkoutSegment(phase: .warmup, start: 0, end: configuration.warmupDuration)
      )
    }

    var phase = WorkoutPhase.run
    var start = configuration.warmupDuration
    let splitEnd = configuration.workoutDuration

    while start < splitEnd {
      let phaseDuration =
        phase == .run
        ? configuration.runDuration
        : configuration.walkDuration
      let end = min(start + phaseDuration, splitEnd)
      generated.append(WorkoutSegment(phase: phase, start: start, end: end))
      start = end
      phase = phase == .run ? .walk : .run
    }

    segments = generated
  }

  func snapshot(at elapsed: TimeInterval) -> WorkoutSnapshot {
    let clampedElapsed = max(0, elapsed)

    guard clampedElapsed < configuration.workoutDuration,
      let segment = segments.first(where: { clampedElapsed < $0.end })
    else {
      return WorkoutSnapshot(
        phase: segments.last?.phase ?? .run,
        intervalRemaining: 0,
        totalRemaining: 0,
        isComplete: true
      )
    }

    return WorkoutSnapshot(
      phase: segment.phase,
      intervalRemaining: segment.end - clampedElapsed,
      totalRemaining: configuration.workoutDuration - clampedElapsed,
      isComplete: false
    )
  }

  func cues(after elapsed: TimeInterval) -> [WorkoutCue] {
    var cues: [WorkoutCue] = []

    let warmupWarningTime = configuration.warmupDuration - 60
    if configuration.warmupDuration > 60, warmupWarningTime > elapsed {
      cues.append(.warmupWarning(at: warmupWarningTime))
    }

    let remainingTransitions = zip(segments, segments.dropFirst()).compactMap {
      segment, nextSegment -> WorkoutCue? in
      guard segment.end > elapsed else { return nil }
      return .transition(to: nextSegment.phase, at: segment.end)
    }
    cues.append(contentsOf: remainingTransitions)

    guard configuration.workoutDuration > elapsed else {
      return cues
    }

    return cues + [.complete(at: configuration.workoutDuration)]
  }
}
