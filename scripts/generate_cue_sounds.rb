#!/usr/bin/env ruby

require "fileutils"
require "open3"
require "tmpdir"

# Central configuration for every spoken notification cue.
VOICE = "Samantha"
LANGUAGE = "en-US"
SPEECH_RATE = 175 # words per minute; native pitch and volume are intentionally unmodified
SAMPLE_RATE = 44_100
LEAD_IN_MS = 80
BEEP_DURATION_MS = 140
BEEP_FREQUENCY_HZ = 880
BEEP_LEVEL = 0.24
BEEP_FADE_MS = 12
POST_BEEP_GAP_MS = 180
TRAILING_SILENCE_MS = 250
NOTICEABLE_GAIN = 1.65
ATTENTION_GAP_MS = 110

SOUNDS = {
  "warmup.wav" => "One minute",
  "run.wav" => "Run",
  "walk.wav" => "Walk",
  "complete.wav" => "Workout complete",
}.freeze

project_root = File.expand_path("..", __dir__)
variants_only = ARGV.delete("--variants-only")
output_directory = File.expand_path(ARGV.fetch(0, "Split/Resources/Sounds"), project_root)

def require_command(name)
  return if system("command", "-v", name, out: File::NULL)

  abort("Missing required macOS command: #{name}")
end

def sample_count(milliseconds)
  (SAMPLE_RATE * milliseconds / 1_000.0).round
end

def silence(milliseconds)
  Array.new(sample_count(milliseconds), 0)
end

def beep
  length = sample_count(BEEP_DURATION_MS)
  fade_length = sample_count(BEEP_FADE_MS)

  Array.new(length) do |index|
    fade_in = [index.to_f / fade_length, 1.0].min
    fade_out = [(length - 1 - index).to_f / fade_length, 1.0].min
    envelope = [fade_in, fade_out].min
    phase = 2 * Math::PI * BEEP_FREQUENCY_HZ * index / SAMPLE_RATE
    (Math.sin(phase) * BEEP_LEVEL * envelope * 32_767).round
  end
end

def amplified(samples, gain)
  samples.map do |sample|
    [[(sample * gain).round, 32_767].min, -32_768].max
  end
end

def read_pcm_samples(path)
  wav = File.binread(path)
  abort("Invalid WAV container: #{path}") unless wav.start_with?("RIFF") && wav.byteslice(8, 4) == "WAVE"

  chunks = {}
  offset = 12
  while offset + 8 <= wav.bytesize
    chunk_name = wav.byteslice(offset, 4)
    chunk_size = wav.byteslice(offset + 4, 4).unpack1("V")
    chunks[chunk_name] = wav.byteslice(offset + 8, chunk_size)
    offset += 8 + chunk_size + (chunk_size.odd? ? 1 : 0)
  end

  format = chunks["fmt "]&.unpack("vvVVvv")
  expected_format = [1, 1, SAMPLE_RATE, SAMPLE_RATE * 2, 2, 16]
  abort("Unexpected PCM format in #{path}: #{format.inspect}") unless format == expected_format
  abort("Missing audio samples in #{path}") unless chunks["data"]

  chunks.fetch("data").unpack("s<*")
end

def write_pcm_wav(path, samples)
  pcm = samples.pack("s<*")
  format = [1, 1, SAMPLE_RATE, SAMPLE_RATE * 2, 2, 16].pack("vvVVvv")
  wave = "WAVE" + "fmt " + [format.bytesize].pack("V") + format +
    "data" + [pcm.bytesize].pack("V") + pcm
  File.binwrite(path, "RIFF" + [wave.bytesize].pack("V") + wave)
end

if variants_only
  SOUNDS.each_key do |filename|
    source_path = File.join(output_directory, filename)
    noticeable_path = File.join(output_directory, filename.sub(/\.wav\z/, "-noticeable.wav"))
    write_pcm_wav(noticeable_path, amplified(read_pcm_samples(source_path), NOTICEABLE_GAIN))
    puts "Generated #{noticeable_path} from the existing cue"
  end

  attention_samples = silence(LEAD_IN_MS) + beep + silence(TRAILING_SILENCE_MS)
  attention_path = File.join(output_directory, "attention.wav")
  write_pcm_wav(attention_path, attention_samples)
  puts "Generated #{attention_path}"

  noticeable_attention_samples = silence(LEAD_IN_MS) + amplified(beep, NOTICEABLE_GAIN) +
    silence(ATTENTION_GAP_MS) + amplified(beep, NOTICEABLE_GAIN) + silence(TRAILING_SILENCE_MS)
  noticeable_attention_path = File.join(output_directory, "attention-noticeable.wav")
  write_pcm_wav(noticeable_attention_path, noticeable_attention_samples)
  puts "Generated #{noticeable_attention_path}"
  exit
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
  generated_sounds = []

  SOUNDS.each do |filename, words|
    aiff_path = File.join(temporary_directory, filename.sub(/\.wav\z/, ".aiff"))
    speech_path = File.join(temporary_directory, "speech-#{filename}")
    generated_path = File.join(temporary_directory, filename)
    destination_path = File.join(output_directory, filename)
    unless system("say", "-v", VOICE, "-r", SPEECH_RATE.to_s, "-o", aiff_path, words)
      abort("Failed to synthesize #{filename}")
    end

    unless system(
      "afconvert", aiff_path,
      "-o", speech_path,
      "-f", "WAVE",
      "-d", "LEI16@#{SAMPLE_RATE}",
      "-c", "1"
    )
      abort("Failed to convert #{filename} to notification-compatible WAV")
    end

    speech_samples = read_pcm_samples(speech_path)
    abort("Speech synthesis produced no audio for #{filename}") if speech_samples.empty?

    samples = silence(LEAD_IN_MS) + beep + silence(POST_BEEP_GAP_MS) +
      speech_samples + silence(TRAILING_SILENCE_MS)
    write_pcm_wav(generated_path, samples)

    audio_info, info_status = Open3.capture2("afinfo", generated_path)
    duration = audio_info[/estimated duration:\s+([0-9.]+) sec/, 1]&.to_f
    abort("Unable to inspect generated audio for #{filename}") unless info_status.success? && duration
    abort("#{filename} contains no spoken audio") unless duration.positive?
    abort("#{filename} is too long for a notification sound") if duration >= 30

    noticeable_filename = filename.sub(/\.wav\z/, "-noticeable.wav")
    noticeable_path = File.join(temporary_directory, noticeable_filename)
    noticeable_destination = File.join(output_directory, noticeable_filename)
    write_pcm_wav(noticeable_path, amplified(samples, NOTICEABLE_GAIN))

    generated_sounds << [generated_path, destination_path, "beep + #{words.inspect}", duration]
    generated_sounds << [
      noticeable_path,
      noticeable_destination,
      "more noticeable beep + #{words.inspect}",
      duration,
    ]
  end

  attention_samples = silence(LEAD_IN_MS) + beep + silence(TRAILING_SILENCE_MS)
  attention_path = File.join(temporary_directory, "attention.wav")
  attention_destination = File.join(output_directory, "attention.wav")
  write_pcm_wav(attention_path, attention_samples)
  generated_sounds << [
    attention_path,
    attention_destination,
    "attention beep",
    attention_samples.length.to_f / SAMPLE_RATE,
  ]

  noticeable_attention_samples = silence(LEAD_IN_MS) + amplified(beep, NOTICEABLE_GAIN) +
    silence(ATTENTION_GAP_MS) + amplified(beep, NOTICEABLE_GAIN) + silence(TRAILING_SILENCE_MS)
  noticeable_attention_path = File.join(temporary_directory, "attention-noticeable.wav")
  noticeable_attention_destination = File.join(output_directory, "attention-noticeable.wav")
  write_pcm_wav(noticeable_attention_path, noticeable_attention_samples)
  generated_sounds << [
    noticeable_attention_path,
    noticeable_attention_destination,
    "more noticeable double attention beep",
    noticeable_attention_samples.length.to_f / SAMPLE_RATE,
  ]

  generated_sounds.each do |generated_path, destination_path, description, duration|
    FileUtils.mv(generated_path, destination_path)
    puts "Generated #{destination_path} (#{description}, #{format('%.2f', duration)}s)"
  end
end
