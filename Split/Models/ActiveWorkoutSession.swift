import Foundation

struct ActiveWorkoutSession: Codable, Equatable {
  static let currentSchemaVersion = 1

  enum State: String, Codable, Equatable {
    case countingDown
    case running
    case paused
    case complete
  }

  let schemaVersion: Int
  let id: UUID
  let configuration: WorkoutConfiguration
  let state: State
  let elapsedBeforeRun: TimeInterval
  let runStartedAt: Date?

  init(
    id: UUID = UUID(),
    configuration: WorkoutConfiguration,
    state: State,
    elapsedBeforeRun: TimeInterval,
    runStartedAt: Date?
  ) {
    schemaVersion = Self.currentSchemaVersion
    self.id = id
    self.configuration = configuration
    self.state = state
    self.elapsedBeforeRun = elapsedBeforeRun
    self.runStartedAt = runStartedAt
  }

  var isValid: Bool {
    guard schemaVersion == Self.currentSchemaVersion,
      configuration.validationErrors.isEmpty,
      elapsedBeforeRun.isFinite,
      elapsedBeforeRun >= 0
    else { return false }

    switch state {
    case .countingDown, .running:
      return runStartedAt != nil
    case .paused, .complete:
      return runStartedAt == nil
    }
  }

  func elapsed(at date: Date) -> TimeInterval {
    guard (state == .countingDown || state == .running), let runStartedAt else {
      return elapsedBeforeRun
    }
    return elapsedBeforeRun + max(0, date.timeIntervalSince(runStartedAt))
  }

  func resolvedState(at date: Date) -> State {
    if state == .complete || elapsed(at: date) >= configuration.workoutDuration {
      return .complete
    }
    if state == .countingDown, let runStartedAt, date >= runStartedAt {
      return .running
    }
    return state
  }
}

struct ActiveWorkoutSessionStore {
  static let defaultKey = "split.activeWorkoutSession"

  private let defaults: UserDefaults
  private let key: String
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(defaults: UserDefaults = .standard, key: String = Self.defaultKey) {
    self.defaults = defaults
    self.key = key
  }

  func load() -> ActiveWorkoutSession? {
    guard let data = defaults.data(forKey: key) else { return nil }

    guard let session = try? decoder.decode(ActiveWorkoutSession.self, from: data),
      session.isValid
    else {
      defaults.removeObject(forKey: key)
      return nil
    }
    return session
  }

  func save(_ session: ActiveWorkoutSession) {
    guard session.isValid, let data = try? encoder.encode(session) else { return }
    defaults.set(data, forKey: key)
  }

  func clear() {
    defaults.removeObject(forKey: key)
  }
}
