import Foundation
import XCTest

@testable import SplitCore

final class NotificationPreferencesTests: XCTestCase {
  private let plan = IntervalPlan(
    configuration: WorkoutConfiguration(
      cycles: 2,
      warmupSeconds: 150,
      runSeconds: 60,
      walkSeconds: 75
    )
  )

  func testDefaultPreferencesPreserveExistingCueContentAndSounds() {
    let preferences = NotificationPreferences.defaults
    let cues = preferences.resolvedCues(for: plan, after: 0)

    XCTAssertEqual(preferences.hapticStrength, .medium)
    XCTAssertEqual(preferences.soundIntensity, .standard)
    XCTAssertTrue(NotificationCueType.allCases.allSatisfy { preferences[$0].isEnabled })
    XCTAssertEqual(
      cues.first,
      ResolvedNotificationCue(
        type: .warmupBegins,
        time: 0,
        title: "WARMUP",
        body: "Start walking",
        sound: .bundled("walk.wav")
      )
    )
    XCTAssertTrue(
      cues.contains(
        ResolvedNotificationCue(
          type: .warmupMinuteRemaining,
          time: 90,
          title: "WARMUP",
          body: "1 minute remaining",
          sound: .bundled("warmup.wav")
        )
      )
    )
    XCTAssertTrue(
      cues.contains(
        ResolvedNotificationCue(
          type: .runBegins,
          time: 150,
          title: "RUN",
          body: "Switch to running",
          sound: .bundled("run.wav")
        )
      )
    )
    XCTAssertTrue(
      cues.contains(
        ResolvedNotificationCue(
          type: .walkBegins,
          time: 210,
          title: "WALK",
          body: "Switch to walking",
          sound: .bundled("walk.wav")
        )
      )
    )
    XCTAssertEqual(cues.last?.title, "DONE")
    XCTAssertEqual(cues.last?.body, "Workout complete")
    XCTAssertEqual(cues.last?.sound, .bundled("complete.wav"))
  }

  func testPreferencesPersistAndRestore() {
    let suiteName = "NotificationPreferencesTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = NotificationPreferencesStore(defaults: defaults)
    var preferences = NotificationPreferences.defaults
    preferences.runBegins.isEnabled = false
    preferences.walkBegins.title = "RECOVER"
    preferences.hapticStrength = .heavy
    preferences.soundIntensity = .moreNoticeable

    store.save(preferences)

    XCTAssertEqual(store.load(), preferences)
  }

  func testDisabledCuesAreNotResolvedForScheduling() {
    var preferences = NotificationPreferences.defaults
    preferences.runBegins.isEnabled = false
    preferences.warmupMinuteRemaining.isEnabled = false

    let cues = preferences.resolvedCues(for: plan, after: 0)

    XCTAssertFalse(cues.contains { $0.type == .runBegins })
    XCTAssertFalse(cues.contains { $0.type == .warmupMinuteRemaining })
    XCTAssertTrue(cues.contains { $0.type == .walkBegins })
    XCTAssertTrue(cues.contains { $0.type == .workoutCompletes })
  }

  func testCustomTitleAndBodyAreUsed() {
    var preferences = NotificationPreferences.defaults
    preferences.runBegins.title = "GO NOW"
    preferences.runBegins.body = "Settle into your pace"

    let cue = preferences.resolvedCues(for: plan, after: 91)
      .first { $0.type == .runBegins }

    XCTAssertEqual(cue?.title, "GO NOW")
    XCTAssertEqual(cue?.body, "Settle into your pace")
  }

  func testTokensAreReplacedBeforeScheduling() {
    var preferences = NotificationPreferences.defaults
    preferences.runBegins.title = "{phase} · round {cycle}"
    preferences.runBegins.body = "{remaining} remaining in this interval"

    let cue = preferences.resolvedCues(for: plan, after: 91)
      .first { $0.type == .runBegins }

    XCTAssertEqual(cue?.title, "Run · round 1 of 2")
    XCTAssertEqual(cue?.body, "1 minute remaining in this interval")
    XCTAssertFalse(cue?.title.contains("{") ?? true)
    XCTAssertFalse(cue?.body.contains("{") ?? true)
  }

  func testPreviewUsesConfiguredContentTokensAndSound() {
    var preferences = NotificationPreferences.defaults
    preferences.runBegins.title = "{phase} preview"
    preferences.runBegins.body = "Cycle {cycle}, {remaining} remaining"
    preferences.runBegins.sound = .attention

    let cue = preferences.resolvedPreviewCue(for: .runBegins)

    XCTAssertEqual(cue.title, "Run preview")
    XCTAssertEqual(cue.body, "Cycle 3 of 10, 1 minute remaining")
    XCTAssertEqual(cue.sound, .bundled("attention.wav"))
  }

  func testSoundSelectionMapsToNotificationCompatibleDelivery() {
    var preferences = NotificationPreferences.defaults

    preferences.runBegins.sound = .attention
    XCTAssertEqual(preferences.deliverySound(for: .runBegins), .bundled("attention.wav"))

    preferences.soundIntensity = .moreNoticeable
    XCTAssertEqual(
      preferences.deliverySound(for: .runBegins),
      .bundled("attention-noticeable.wav")
    )

    preferences.runBegins.sound = .spoken
    XCTAssertEqual(
      preferences.deliverySound(for: .runBegins),
      .bundled("run-noticeable.wav")
    )

    preferences.runBegins.sound = .systemDefault
    XCTAssertEqual(preferences.deliverySound(for: .runBegins), .systemDefault)

    preferences.runBegins.sound = .none
    XCTAssertEqual(preferences.deliverySound(for: .runBegins), .none)
  }

  func testHapticPreferenceMapping() {
    var preferences = NotificationPreferences.defaults
    preferences.hapticStrength = .light

    XCTAssertEqual(preferences.effectiveHapticStrength(for: .warmupBegins), .light)
    XCTAssertEqual(preferences.effectiveHapticStrength(for: .runBegins), .light)

    preferences.hapticStrength = .off
    XCTAssertEqual(preferences.effectiveHapticStrength(for: .runBegins), .off)
  }
}
