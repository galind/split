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
  static let previewCategoryIdentifier = "SPLIT_NOTIFICATION_PREVIEW"
  static let previewBundledSoundKey = "splitPreviewBundledSound"
  static let previewHasNoSoundKey = "splitPreviewHasNoSound"
  private static let identifierPrefix = "split.workout."
  private static let previewIdentifier = "split.notification-preview"
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
    anchoredAt anchorDate: Date,
    preferences: NotificationPreferences
  ) async throws {
    cancelPending(plan: plan, sessionID: sessionID)

    do {
      for (index, cue) in preferences.resolvedCues(for: plan, after: elapsed).enumerated() {
        try Task.checkCancellation()
        let content = content(for: cue, categoryIdentifier: "SPLIT_WORKOUT")
        let fireDate = anchorDate.addingTimeInterval(cue.time - elapsed)
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

  func schedulePreview(
    type: NotificationCueType,
    preferences: NotificationPreferences
  ) async throws {
    try await ensureSoundPermission()

    center.removePendingNotificationRequests(withIdentifiers: [Self.previewIdentifier])
    center.removeDeliveredNotifications(withIdentifiers: [Self.previewIdentifier])

    let cue = preferences.resolvedPreviewCue(for: type)
    let previewContent = content(
      for: cue,
      categoryIdentifier: Self.previewCategoryIdentifier
    )
    switch cue.sound {
    case .bundled(let filename):
      previewContent.userInfo[Self.previewBundledSoundKey] = filename
    case .none:
      previewContent.userInfo[Self.previewHasNoSoundKey] = true
    case .systemDefault:
      break
    }
    let request = UNNotificationRequest(
      identifier: Self.previewIdentifier,
      content: previewContent,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    )
    try await center.add(request)
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

  private func content(
    for cue: ResolvedNotificationCue,
    categoryIdentifier: String
  ) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = cue.title
    content.body = cue.body
    switch cue.sound {
    case .bundled(let filename):
      content.sound = UNNotificationSound(
        named: UNNotificationSoundName(rawValue: filename)
      )
    case .systemDefault:
      content.sound = .default
    case .none:
      content.sound = nil
    }
    content.categoryIdentifier = categoryIdentifier
    return content
  }
}
