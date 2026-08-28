import Foundation

enum WorkoutConfigurationError: LocalizedError, Equatable {
  case invalidTotalDuration
  case invalidWarmupDuration
  case invalidRunDuration
  case invalidWalkDuration
  case runExceedsTotal
  case walkExceedsTotal

  var errorDescription: String? {
    switch self {
    case .invalidTotalDuration:
      return "Total split duration must be between 1 and 60 minutes."
    case .invalidWarmupDuration:
      return "Warmup must be between 0:00 and 60:00 in 2:30 increments."
    case .invalidRunDuration:
      return "RUN must be between 1:00 and 30:00 in 15-second increments."
    case .invalidWalkDuration:
      return "WALK must be between 1:00 and 30:00 in 15-second increments."
    case .runExceedsTotal:
      return "RUN cannot be longer than the total split duration."
    case .walkExceedsTotal:
      return "WALK cannot be longer than the total split duration."
    }
  }
}

struct WorkoutConfiguration: Codable, Equatable {
  let totalDuration: TimeInterval
  let warmupDuration: TimeInterval
  let runDuration: TimeInterval
  let walkDuration: TimeInterval

  init(totalMinutes: Int, warmupSeconds: Int = 0, runSeconds: Int, walkSeconds: Int) {
    totalDuration = TimeInterval(totalMinutes * 60)
    warmupDuration = TimeInterval(warmupSeconds)
    runDuration = TimeInterval(runSeconds)
    walkDuration = TimeInterval(walkSeconds)
  }

  init(cycles: Int, warmupSeconds: Int = 0, runSeconds: Int, walkSeconds: Int) {
    totalDuration = TimeInterval(cycles * (runSeconds + walkSeconds))
    warmupDuration = TimeInterval(warmupSeconds)
    runDuration = TimeInterval(runSeconds)
    walkDuration = TimeInterval(walkSeconds)
  }

  init(totalMinutes: Int, warmupSeconds: Int = 0, runMinutes: Int, walkMinutes: Int) {
    self.init(
      totalMinutes: totalMinutes,
      warmupSeconds: warmupSeconds,
      runSeconds: runMinutes * 60,
      walkSeconds: walkMinutes * 60
    )
  }

  var workoutDuration: TimeInterval {
    warmupDuration + totalDuration
  }

  var validationErrors: [WorkoutConfigurationError] {
    var errors: [WorkoutConfigurationError] = []

    if totalDuration <= 0 || totalDuration > 60 * 60 {
      errors.append(.invalidTotalDuration)
    }
    if warmupDuration < 0 || warmupDuration > 60 * 60
      || warmupDuration.remainder(dividingBy: 150) != 0
    {
      errors.append(.invalidWarmupDuration)
    }
    if runDuration < 60 || runDuration > 30 * 60 || runDuration.remainder(dividingBy: 15) != 0 {
      errors.append(.invalidRunDuration)
    }
    if walkDuration < 60 || walkDuration > 30 * 60 || walkDuration.remainder(dividingBy: 15) != 0 {
      errors.append(.invalidWalkDuration)
    }
    if runDuration > totalDuration {
      errors.append(.runExceedsTotal)
    }
    if walkDuration > totalDuration {
      errors.append(.walkExceedsTotal)
    }

    return errors
  }

  func validate() throws {
    if let error = validationErrors.first {
      throw error
    }
  }
}
