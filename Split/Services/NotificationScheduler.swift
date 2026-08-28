import Foundation
import UserNotifications

enum NotificationPermissionError: LocalizedError {
  case unavailable
  case soundDisabled

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "Turn on notifications for cues when your iPhone is locked."
    case .soundDisabled:
      return "Turn on notification sounds for locked-screen cues."
    }
  }
}

struct NotificationScheduler {
  private static let identifierPrefix = "split.workout."
  private let center = UNUserNotificationCenter.current()

  func ensureSoundPermission() async throws {
    var settings = await center.notificationSettings()

    if settings.authorizationStatus == .notDetermined {
      _ = try await center.requestAuthorization(options: [.alert, .sound])
      settings = await center.notificationSettings()
    }

    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .ephemeral
    else {
      throw NotificationPermissionError.unavailable
    }

    guard settings.soundSetting == .enabled else {
      throw NotificationPermissionError.soundDisabled
    }
  }

  func schedule(
    plan: IntervalPlan,
    sessionID: UUID,
    elapsed: TimeInterval,
    anchoredAt anchorDate: Date
  ) async throws {
    cancelPending(plan: plan, sessionID: sessionID)

    do {
      for (index, cue) in plan.cues(after: elapsed).enumerated() {
        try Task.checkCancellation()
        let content = UNMutableNotificationContent()
        let cueTime: TimeInterval

        switch cue {
        case .warmupWarning(at: let time):
          cueTime = time
          content.title = "WARMUP"
          content.body = "1 minute remaining"
          content.sound = UNNotificationSound(
            named: UNNotificationSoundName(rawValue: "warmup.wav")
          )
        case .transition(let phase, at: let time):
          cueTime = time
          content.title = phase.rawValue
          switch phase {
          case .warmup:
            content.body = "Start walking"
          case .run:
            content.body = "Switch to running"
          case .walk:
            content.body = "Switch to walking"
          }
          content.sound = UNNotificationSound(
            named: UNNotificationSoundName(rawValue: phase == .run ? "run.wav" : "walk.wav")
          )
        case .complete(at: let time):
          cueTime = time
          content.title = "DONE"
          content.body = "Workout complete"
          content.sound = UNNotificationSound(
            named: UNNotificationSoundName(rawValue: "complete.wav")
          )
        }

        content.categoryIdentifier = "SPLIT_WORKOUT"
        let fireDate = anchorDate.addingTimeInterval(cueTime - elapsed)
        let components = Calendar.current.dateComponents(
          [.year, .month, .day, .hour, .minute, .second, .nanosecond],
          from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
          identifier: identifier(for: sessionID, index: index),
          content: content,
          trigger: trigger
        )
        try await center.add(request)
        try Task.checkCancellation()
      }
    } catch {
      cancelPending(plan: plan, sessionID: sessionID)
      throw error
    }
  }

  func cancelPending(plan: IntervalPlan, sessionID: UUID) {
    let identifiers = plan.cues(after: -1).indices.map {
      identifier(for: sessionID, index: $0)
    }
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
  }

  func cancelStalePending(keeping sessionID: UUID? = nil) async {
    let keptPrefix = sessionID.map(sessionPrefix)
    let identifiers = await center.pendingNotificationRequests()
      .map(\.identifier)
      .filter { identifier in
        identifier.hasPrefix(Self.identifierPrefix)
          && (keptPrefix == nil || !identifier.hasPrefix(keptPrefix!))
      }
    guard !Task.isCancelled else { return }
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
  }

  func clearDelivered(sessionID: UUID) async {
    let prefix = sessionPrefix(sessionID)
    let identifiers = await center.deliveredNotifications()
      .map(\.request.identifier)
      .filter { $0.hasPrefix(prefix) }
    guard !Task.isCancelled else { return }
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  private func sessionPrefix(_ sessionID: UUID) -> String {
    Self.identifierPrefix + sessionID.uuidString + "."
  }

  private func identifier(for sessionID: UUID, index: Int) -> String {
    sessionPrefix(sessionID) + String(index)
  }
}
