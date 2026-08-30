import SwiftUI

struct NotificationBuilderView: View {
  @Binding var preferences: NotificationPreferences
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var showsRestoreConfirmation = false
  @State private var pendingPreview: NotificationCueType?
  @State private var previewErrorMessage: String?
  private let notificationScheduler = NotificationScheduler()

  var body: some View {
    NavigationStack {
      Form {
        noticeabilitySection

        Section {
          ForEach(NotificationCueType.allCases) { type in
            cueRow(type)
          }
        } header: {
          Text("Cues")
        } footer: {
          Text("Tap play to receive a test notification using iPhone alert volume.")
        }

        Section {
          Button("Restore Defaults", role: .destructive) {
            showsRestoreConfirmation = true
          }
          .alert("Restore notification defaults?", isPresented: $showsRestoreConfirmation) {
            Button("Restore Defaults", role: .destructive) {
              preferences = .defaults
            }
            Button("Cancel", role: .cancel) {}
          } message: {
            Text("This resets enabled cues, sounds, noticeability, and haptics.")
          }
        }
      }
      .navigationTitle("Notifications")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .alert("Preview unavailable", isPresented: showsPreviewError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(previewErrorMessage ?? "Unable to schedule the test notification.")
      }
    }
  }

  private var noticeabilitySection: some View {
    Section {
      Toggle("More noticeable sounds", isOn: moreNoticeableBinding)

      Picker("In-app haptics", selection: $preferences.hapticStrength) {
        ForEach(NotificationHapticStrength.allCases) { strength in
          Text(strength.displayName).tag(strength)
        }
      }
    } header: {
      Text("Feedback")
    } footer: {
      Text(
        "Split cannot override iPhone volume, Silent Mode, Focus, or system vibration settings."
      )
    }
  }

  private var moreNoticeableBinding: Binding<Bool> {
    Binding(
      get: { preferences.soundIntensity == .moreNoticeable },
      set: { preferences.soundIntensity = $0 ? .moreNoticeable : .standard }
    )
  }

  private var showsPreviewError: Binding<Bool> {
    Binding(
      get: { previewErrorMessage != nil },
      set: { if !$0 { previewErrorMessage = nil } }
    )
  }

  private func cueRow(_ type: NotificationCueType) -> some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 8) {
          Toggle(type.displayName, isOn: cueBinding(type, \.isEnabled))
          HStack(spacing: 8) {
            soundPicker(type)
            Spacer(minLength: 8)
            previewButton(type)
          }
        }
      } else {
        HStack(spacing: 8) {
          Text(compactName(for: type))
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .layoutPriority(1)
            .accessibilityHidden(true)

          Spacer(minLength: 2)
          soundPicker(type)
          previewButton(type)

          Toggle(type.displayName, isOn: cueBinding(type, \.isEnabled))
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(type.displayName)
        }
      }
    }
    .frame(minHeight: 44)
  }

  private func soundPicker(_ type: NotificationCueType) -> some View {
    Picker("Sound", selection: cueBinding(type, \.sound)) {
      ForEach(NotificationSoundChoice.allCases) { sound in
        Text(compactName(for: sound)).tag(sound)
      }
    }
    .labelsHidden()
    .pickerStyle(.menu)
    .fixedSize()
    .disabled(!preferences[type].isEnabled)
    .accessibilityLabel("\(type.displayName) sound")
  }

  private func previewButton(_ type: NotificationCueType) -> some View {
    Button {
      preview(type)
    } label: {
      Group {
        if pendingPreview == type {
          ProgressView()
            .controlSize(.small)
        } else {
          Image(systemName: "play.fill")
            .font(.caption.weight(.bold))
        }
      }
      .frame(width: 36, height: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .disabled(!preferences[type].isEnabled || pendingPreview != nil)
    .accessibilityLabel("Test \(type.displayName) notification")
    .accessibilityHint("Schedules a test notification in one second.")
  }

  private func preview(_ type: NotificationCueType) {
    pendingPreview = type
    Task {
      defer { pendingPreview = nil }
      do {
        try await notificationScheduler.schedulePreview(
          type: type,
          preferences: preferences
        )
      } catch {
        previewErrorMessage = error.localizedDescription
      }
    }
  }

  private func compactName(for type: NotificationCueType) -> String {
    switch type {
    case .warmupBegins: return "Warmup starts"
    case .warmupMinuteRemaining: return "Warmup · 1 min"
    case .runBegins: return "Run starts"
    case .walkBegins: return "Walk starts"
    case .workoutCompletes: return "Workout done"
    }
  }

  private func compactName(for sound: NotificationSoundChoice) -> String {
    switch sound {
    case .spoken: return "Spoken"
    case .attention: return "Attention"
    case .systemDefault: return "Default"
    case .none: return "None"
    }
  }

  private func cueBinding<Value>(
    _ type: NotificationCueType,
    _ keyPath: WritableKeyPath<NotificationCuePreference, Value>
  ) -> Binding<Value> {
    Binding(
      get: { preferences[type][keyPath: keyPath] },
      set: { value in
        var cue = preferences[type]
        cue[keyPath: keyPath] = value
        preferences[type] = cue
      }
    )
  }
}

#Preview {
  NotificationBuilderView(preferences: .constant(.defaults))
}
