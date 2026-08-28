#!/usr/bin/env ruby

require "zlib"

SIZE = 1_024

def rounded_rectangle?(x, y, left, top, right, bottom, radius)
  return false if x < left || x >= right || y < top || y >= bottom
  return true if x >= left + radius && x < right - radius
  return true if y >= top + radius && y < bottom - radius

  corner_x = x < left + radius ? left + radius : right - radius - 1
  corner_y = y < top + radius ? top + radius : bottom - radius - 1
  (x - corner_x)**2 + (y - corner_y)**2 <= radius**2
end

raw = String.new(capacity: SIZE * (SIZE * 3 + 1), encoding: Encoding::BINARY)

SIZE.times do |y|
  raw << "\x00"
  SIZE.times do |x|
    shade = 12 + (10 * y / SIZE)
    color = [shade, shade + 2, shade + 6]

    if rounded_rectangle?(x, y, 268, 244, 486, 650, 109)
      color = [47, 221, 112]
    elsif rounded_rectangle?(x, y, 538, 374, 756, 780, 109)
      color = [49, 205, 232]
    end

    raw << color.pack("C3")
  end
end

def chunk(type, data)
  [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
end

png = "\x89PNG\r\n\x1A\n".b
png << chunk("IHDR", [SIZE, SIZE, 8, 2, 0, 0, 0].pack("NNC5"))
png << chunk("IDAT", Zlib::Deflate.deflate(raw, Zlib::BEST_COMPRESSION))
png << chunk("IEND", "")

abort("Usage: ruby generate_app_icon.rb <output-file>") unless ARGV.length == 1
File.binwrite(ARGV.first, png)
