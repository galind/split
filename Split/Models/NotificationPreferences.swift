import Foundation

enum NotificationCueType: String, Codable, CaseIterable, Equatable, Identifiable {
  case warmupBegins
  case warmupMinuteRemaining
  case runBegins
  case walkBegins
  case workoutCompletes

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .warmupBegins: return "Warmup begins"
    case .warmupMinuteRemaining: return "One minute of warmup remains"
    case .runBegins: return "Run begins"
    case .walkBegins: return "Walk begins"
    case .workoutCompletes: return "Workout completes"
    }
  }

  var defaultPreference: NotificationCuePreference {
    switch self {
    case .warmupBegins:
      return NotificationCuePreference(title: "WARMUP", body: "Start walking")
    case .warmupMinuteRemaining:
      return NotificationCuePreference(title: "WARMUP", body: "1 minute remaining")
    case .runBegins:
      return NotificationCuePreference(title: "RUN", body: "Switch to running")
    case .walkBegins:
      return NotificationCuePreference(title: "WALK", body: "Switch to walking")
    case .workoutCompletes:
      return NotificationCuePreference(title: "DONE", body: "Workout complete")
    }
  }

  fileprivate var spokenSoundBaseName: String {
    switch self {
    case .warmupBegins: return "walk"
    case .warmupMinuteRemaining: return "warmup"
    case .runBegins: return "run"
    case .walkBegins: return "walk"
    case .workoutCompletes: return "complete"
    }
  }
}

enum NotificationSoundChoice: String, Codable, CaseIterable, Equatable, Identifiable {
  case spoken
  case attention
  case systemDefault
  case none

  var id: String { rawValue }
}

enum NotificationSoundIntensity: String, Codable, Equatable {
  case standard
  case moreNoticeable
}

enum NotificationHapticStrength: Int, Codable, CaseIterable, Equatable, Identifiable {
  case off
  case light
  case medium
  case heavy

  var id: Int { rawValue }

  var displayName: String {
    switch self {
    case .off: return "Off"
    case .light: return "Light"
    case .medium: return "Medium"
    case .heavy: return "Heavy"
    }
  }

}

struct NotificationCuePreference: Codable, Equatable {
  static let titleCharacterLimit = 50
  static let bodyCharacterLimit = 160

  var isEnabled: Bool
  var title: String
  var body: String
  var sound: NotificationSoundChoice

  init(
    isEnabled: Bool = true,
    title: String,
    body: String,
    sound: NotificationSoundChoice = .spoken
  ) {
    self.isEnabled = isEnabled
    self.title = title
    self.body = body
    self.sound = sound
  }

  fileprivate func normalized(using fallback: NotificationCuePreference) -> Self {
    var result = self
    result.title = String(result.title.prefix(Self.titleCharacterLimit))
    result.body = String(result.body.prefix(Self.bodyCharacterLimit))
    if result.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      result.title = fallback.title
    }
    if result.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      result.body = fallback.body
    }
    return result
  }
}

struct NotificationTokenContext: Equatable {
  let phase: String
  let remaining: String
  let cycle: String

}

struct NotificationPreferences: Codable, Equatable {
  var warmupBegins: NotificationCuePreference
  var warmupMinuteRemaining: NotificationCuePreference
  var runBegins: NotificationCuePreference
  var walkBegins: NotificationCuePreference
  var workoutCompletes: NotificationCuePreference
  var hapticStrength: NotificationHapticStrength
  var soundIntensity: NotificationSoundIntensity

  init(
    warmupBegins: NotificationCuePreference = NotificationCueType.warmupBegins.defaultPreference,
    warmupMinuteRemaining: NotificationCuePreference =
      NotificationCueType.warmupMinuteRemaining.defaultPreference,
    runBegins: NotificationCuePreference = NotificationCueType.runBegins.defaultPreference,
    walkBegins: NotificationCuePreference = NotificationCueType.walkBegins.defaultPreference,
    workoutCompletes: NotificationCuePreference =
      NotificationCueType.workoutCompletes.defaultPreference,
    hapticStrength: NotificationHapticStrength = .medium,
    soundIntensity: NotificationSoundIntensity = .standard
  ) {
    self.warmupBegins = warmupBegins
    self.warmupMinuteRemaining = warmupMinuteRemaining
    self.runBegins = runBegins
    self.walkBegins = walkBegins
    self.workoutCompletes = workoutCompletes
    self.hapticStrength = hapticStrength
    self.soundIntensity = soundIntensity
  }

  static let defaults = NotificationPreferences()

  subscript(type: NotificationCueType) -> NotificationCuePreference {
    get {
      switch type {
      case .warmupBegins: return warmupBegins
      case .warmupMinuteRemaining: return warmupMinuteRemaining
      case .runBegins: return runBegins
      case .walkBegins: return walkBegins
      case .workoutCompletes: return workoutCompletes
      }
    }
    set {
      switch type {
      case .warmupBegins: warmupBegins = newValue
      case .warmupMinuteRemaining: warmupMinuteRemaining = newValue
      case .runBegins: runBegins = newValue
      case .walkBegins: walkBegins = newValue
      case .workoutCompletes: workoutCompletes = newValue
      }
    }
  }

  func normalized() -> Self {
    var result = self
    for type in NotificationCueType.allCases {
      result[type] = result[type].normalized(using: type.defaultPreference)
    }
    return result
  }

  func effectiveHapticStrength(for _: NotificationCueType) -> NotificationHapticStrength {
    hapticStrength
  }

  func render(_ template: String, context: NotificationTokenContext) -> String {
    template
      .replacingOccurrences(of: "{phase}", with: context.phase)
      .replacingOccurrences(of: "{remaining}", with: context.remaining)
      .replacingOccurrences(of: "{cycle}", with: context.cycle)
  }

  func deliverySound(for type: NotificationCueType) -> NotificationDeliverySound {
    switch self[type].sound {
    case .spoken:
      return .bundled(soundFilename(baseName: type.spokenSoundBaseName))
    case .attention:
      return .bundled(soundFilename(baseName: "attention"))
    case .systemDefault:
      return .systemDefault
    case .none:
      return .none
    }
  }

  func resolvedCues(
    for plan: IntervalPlan,
    after elapsed: TimeInterval
  ) -> [ResolvedNotificationCue] {
    let normalized = normalized()
    return plan.cues(after: elapsed).compactMap { cue in
      let type = Self.type(for: cue)
      let preference = normalized[type]
      guard preference.isEnabled else { return nil }
      let context = Self.context(for: cue, type: type, plan: plan)
      return ResolvedNotificationCue(
        type: type,
        time: Self.time(for: cue),
        title: normalized.render(preference.title, context: context),
        body: normalized.render(preference.body, context: context),
        sound: normalized.deliverySound(for: type)
      )
    }
  }

  func resolvedPreviewCue(for type: NotificationCueType) -> ResolvedNotificationCue {
    let normalized = normalized()
    let preference = normalized[type]
    let context = Self.previewContext(for: type)
    return ResolvedNotificationCue(
      type: type,
      time: 0,
      title: normalized.render(preference.title, context: context),
      body: normalized.render(preference.body, context: context),
      sound: normalized.deliverySound(for: type)
    )
  }

  private func soundFilename(baseName: String) -> String {
    switch soundIntensity {
    case .standard: return "\(baseName).wav"
    case .moreNoticeable: return "\(baseName)-noticeable.wav"
    }
  }

  private static func type(for cue: WorkoutCue) -> NotificationCueType {
    switch cue {
    case .warmupWarning: return .warmupMinuteRemaining
    case .transition(let phase, _):
      switch phase {
      case .warmup: return .warmupBegins
      case .run: return .runBegins
      case .walk: return .walkBegins
      }
    case .complete: return .workoutCompletes
    }
  }

  private static func previewContext(for type: NotificationCueType) -> NotificationTokenContext {
    switch type {
    case .warmupBegins:
      return NotificationTokenContext(phase: "Warmup", remaining: "5 minutes", cycle: "0 of 10")
    case .warmupMinuteRemaining:
      return NotificationTokenContext(phase: "Warmup", remaining: "1 minute", cycle: "0 of 10")
    case .runBegins:
      return NotificationTokenContext(phase: "Run", remaining: "1 minute", cycle: "3 of 10")
    case .walkBegins:
      return NotificationTokenContext(phase: "Walk", remaining: "1 minute", cycle: "3 of 10")
    case .workoutCompletes:
      return NotificationTokenContext(phase: "Done", remaining: "0 seconds", cycle: "10 of 10")
    }
  }

  private static func time(for cue: WorkoutCue) -> TimeInterval {
    switch cue {
    case .warmupWarning(let time), .transition(_, let time), .complete(let time): return time
    }
  }

  private static func context(
    for cue: WorkoutCue,
    type: NotificationCueType,
    plan: IntervalPlan
  ) -> NotificationTokenContext {
    let time = Self.time(for: cue)
    let snapshot = plan.snapshot(at: time)
    let cycleCount = max(1, snapshot.cycleCount)
    let cycleNumber: Int
    let remaining: TimeInterval

    switch type {
    case .warmupBegins:
      cycleNumber = 0
      remaining = plan.configuration.warmupDuration
    case .warmupMinuteRemaining:
      cycleNumber = 0
      remaining = 60
    case .runBegins, .walkBegins:
      cycleNumber = max(1, snapshot.cycleNumber)
      remaining = snapshot.intervalRemaining
    case .workoutCompletes:
      cycleNumber = cycleCount
      remaining = 0
    }

    return NotificationTokenContext(
      phase: phaseName(for: type),
      remaining: durationDescription(remaining),
      cycle: "\(cycleNumber) of \(cycleCount)"
    )
  }

  private static func phaseName(for type: NotificationCueType) -> String {
    switch type {
    case .warmupBegins, .warmupMinuteRemaining: return "Warmup"
    case .runBegins: return "Run"
    case .walkBegins: return "Walk"
    case .workoutCompletes: return "Done"
    }
  }

  private static func durationDescription(_ duration: TimeInterval) -> String {
    let seconds = max(0, Int(ceil(duration)))
    let minutes = seconds / 60
    let remainingSeconds = seconds % 60
    if minutes == 0 { return "\(remainingSeconds) \(remainingSeconds == 1 ? "second" : "seconds")" }
    if remainingSeconds == 0 { return "\(minutes) \(minutes == 1 ? "minute" : "minutes")" }
    return "\(minutes) minutes, \(remainingSeconds) seconds"
  }
}

enum NotificationDeliverySound: Equatable {
  case bundled(String)
  case systemDefault
  case none
}

struct ResolvedNotificationCue: Equatable {
  let type: NotificationCueType
  let time: TimeInterval
  let title: String
  let body: String
  let sound: NotificationDeliverySound
}

struct NotificationPreferencesStore {
  static let defaultKey = "split.notificationPreferences"

  private let defaults: UserDefaults
  private let key: String
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(defaults: UserDefaults = .standard, key: String = Self.defaultKey) {
    self.defaults = defaults
    self.key = key
  }

  func load() -> NotificationPreferences {
    guard let data = defaults.data(forKey: key),
      let preferences = try? decoder.decode(NotificationPreferences.self, from: data)
    else {
      return .defaults
    }
    return preferences.normalized()
  }

  func save(_ preferences: NotificationPreferences) {
    guard let data = try? encoder.encode(preferences.normalized()) else { return }
    defaults.set(data, forKey: key)
  }
}
