#!/usr/bin/env ruby

require "fileutils"
require "open3"
require "tmpdir"

# Central configuration for every spoken notification cue.
VOICE = "Samantha"
LANGUAGE = "en-US"
SPEECH_RATE = 175 # words per minute; native pitch and volume are intentionally unmodified
SAMPLE_RATE = 44_100

SOUNDS = {
  "warmup.wav" => "One minute",
  "run.wav" => "Run",
  "walk.wav" => "Walk",
  "complete.wav" => "Workout complete",
}.freeze

project_root = File.expand_path("..", __dir__)
output_directory = File.expand_path(ARGV.fetch(0, "Split/Resources/Sounds"), project_root)

def require_command(name)
  return if system("command", "-v", name, out: File::NULL)

  abort("Missing required macOS command: #{name}")
end

require_command("say")
require_command("afconvert")
require_command("afinfo")

voices, voice_status = Open3.capture2("say", "-v", "?")
abort("Unable to query installed macOS voices") unless voice_status.success?

voice_line = voices.lines.find { |line| line.match?(/^#{Regexp.escape(VOICE)}\s/) }
abort("The configured voice #{VOICE.inspect} is not installed. Check voices with: say -v '?'") unless voice_line

installed_locale = voice_line[/\s(en_[A-Z]{2})\s+#/, 1]&.tr("_", "-")
unless installed_locale == LANGUAGE
  abort("#{VOICE.inspect} uses locale #{installed_locale.inspect}, expected #{LANGUAGE.inspect}")
end

FileUtils.mkdir_p(output_directory)

Dir.mktmpdir("split-spoken-cues") do |temporary_directory|
  SOUNDS.each do |filename, words|
    aiff_path = File.join(temporary_directory, filename.sub(/\.wav\z/, ".aiff"))
    converted_path = File.join(temporary_directory, filename)
    destination_path = File.join(output_directory, filename)
    unless system("say", "-v", VOICE, "-r", SPEECH_RATE.to_s, "-o", aiff_path, words)
      abort("Failed to synthesize #{filename}")
    end

    unless system(
      "afconvert", aiff_path,
      "-o", converted_path,
      "-f", "WAVE",
      "-d", "LEI16@#{SAMPLE_RATE}",
      "-c", "1"
    )
      abort("Failed to convert #{filename} to notification-compatible WAV")
    end

    audio_info, info_status = Open3.capture2("afinfo", converted_path)
    duration = audio_info[/estimated duration:\s+([0-9.]+) sec/, 1]&.to_f
    abort("Unable to inspect generated audio for #{filename}") unless info_status.success? && duration
    abort("#{filename} contains no spoken audio") unless duration.positive?
    abort("#{filename} is too long for a notification sound") if duration >= 30

    FileUtils.mv(converted_path, destination_path)
    puts "Generated #{destination_path} (#{words.inspect}, #{format('%.2f', duration)}s)"
  end
end
