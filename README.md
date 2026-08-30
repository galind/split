# Split

Split is a deliberately small native iPhone run/walk interval timer.

Choose the number of complete RUN+WALK cycles and Split shows the resulting split time. The cycle count is capped dynamically so the split process never exceeds 60 minutes; an optional warmup in 2:30 increments is added before it.

## Requirements

- Xcode 16 or newer
- iOS 17 or newer

Open `Split.xcodeproj`, select an iPhone simulator or device, and run the `Split` scheme.

## Background cues

The app schedules every remaining phase transition as a local notification with a bundled custom sound. iOS delivers those notifications when the app is suspended or the phone is locked, without Split taking ownership of audio playback from Spotify or another app.

The bell button in the setup header opens a compact notification settings sheet. Notification preferences are stored separately from workout configuration. Each cue can be enabled or disabled and assigned a spoken cue, attention beep, system sound, or no sound. Its play control schedules a real local test notification so the preview uses iPhone alert volume rather than media volume. Foreground haptics can be off, light, medium, or heavy. “More noticeable sounds” selects louder bundled variants; it does not change the device's notification volume.

Notification and sound access is requested when the first test notification or workout starts. If access is denied or notification sounds are disabled, Split does not begin a workout because it cannot provide its core locked-screen cue behavior.

The app does not declare a background audio mode. Foreground timers are used only to refresh the display; session state is derived from elapsed wall-clock time, and scheduled system notifications are responsible for background cues.

iOS ultimately controls notification delivery. Focus modes may delay or suppress alerts, Silent Mode and notification sound settings may silence cues, and delivery timing can be affected by normal system scheduling. Split checks notification and sound permission before every start or resume, but it cannot override those system behaviors.

## Tests

The interval-plan tests can run independently from the iOS UI:

```sh
swift test
```

The cue files and app icon are committed. Their source generators live in `scripts/`.

### Notification sounds

The bundled notification sounds use a short, gently faded beep followed by a brief pause and a
soft female voice:

- `warmup.wav`: “One minute”
- `run.wav`: “Run”
- `walk.wav`: “Walk”
- `complete.wav`: “Workout complete”

The generator also creates louder `*-noticeable.wav` versions plus `attention.wav` and
`attention-noticeable.wav`. All custom sounds remain under iOS's 30-second local-notification limit.

Regenerate all four Linear PCM, mono, 44.1 kHz WAV files with:

```sh
ruby scripts/generate_cue_sounds.rb
```

If speech synthesis is unavailable but the four standard spoken files already exist, regenerate
only the louder and attention variants with:

```sh
ruby scripts/generate_cue_sounds.rb --variants-only
```

The generator uses macOS `say` and `afconvert`. Its centralized configuration adds 80 ms of silence,
a 140 ms 880 Hz beep with 12 ms fades, a 180 ms pause, and 250 ms of trailing silence around each
spoken cue. It selects US English `Samantha` at 175 words per minute; the voice's native pitch and
volume are left untouched for a more natural delivery. It validates the installed voice, audio
format, and duration before replacing any committed file. Every generated cue file is listed in
the Split target's Copy Bundle Resources phase, so scheduled local notifications continue to work
while the app is suspended or terminated. No background audio mode is used.
