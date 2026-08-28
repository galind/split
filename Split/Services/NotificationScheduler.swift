import Foundation
import UserNotifications

enum NotificationPermissionError: LocalizedError {
  case unavailable
  case soundDisabled

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "Notifications are required for cues while your iPhone is locked."
    case .soundDisabled:
      return "Notification sounds must be enabled for locked-screen cues."
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

  func schedule(plan: IntervalPlan, elapsed: TimeInterval, anchoredAt anchorDate: Date) async throws
  {
    cancelPending()

    for (index, cue) in plan.cues(after: elapsed).enumerated() {
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
        content.body = phase == .run ? "Switch to running" : "Switch to walking"
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
        identifier: Self.identifierPrefix + String(index),
        content: content,
        trigger: trigger
      )
      try await center.add(request)
    }
  }

  func cancelPending() {
    center.removeAllPendingNotificationRequests()
  }

  func clearDelivered() {
    center.removeAllDeliveredNotifications()
  }
}
