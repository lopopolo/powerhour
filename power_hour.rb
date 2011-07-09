#!/usr/bin/env ruby

# Command line powerhour Utility.
# This was originially designed for use on a Mac, so the default options
# reflect that.
# The script is portable across platforms provided you use the -D flag
# and can provide a command to play audio files
# example:
#   $ ./power_hour.rb -n 20 -d 2 -D ~/Downloads/music/ -c "afplay <file> -t <duration>"

require "optparse"
require "URI"

options = {}
opt = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]\n\n"
  options[:songs] = 60
  opts.on("-n", "--number-of-songs NUMBER", Integer,  \
      "Number of songs in the power hour (default 60)") do |songs|
    options[:songs] = songs
  end
  options[:xml] = "$HOME/Music/iTunes/iTunes Music Library.xml"
  opts.on("-x", "--xml", \
      "Location of iTunes XML (default #{options[:xml]}") do |xml|
    options[:xml] = xml
  end
  options[:duration] = 60
  opts.on("-d", "--duration SECONDS", Integer, \
      "Duration of each song in seconds (default 60)") do |duration|
    options[:duration] = duration
  end
  options[:dir] = nil
  opts.on("-D", "--directory DIR", \
      "Use DIR of music files instead of the iTunes XML") do |dir|
    options[:dir] = dir
  end
  options[:command] = %x[which afplay].empty? ? nil : "afplay -t <duration> <file>"
  opts.on("-c", "--command \"COMMAND -x <duration> <file>\"", \
      "Use COMMAND to play files. The \"<duration>\" and \"<file>\" placeholders must be specified.") do |command|
    abort "COMMAND requires \"<duration>\" and \"<file>\" placeholders" unless command =~ /<duration>/ && command =~ /<file>/
    options[:command] = command
  end
  opts.on("-h", "--help", "Display this screen") do
    puts opts
    exit
  end
end
opt.parse!

# wrap decode because it's in different locations in
# 1.8 and 1.9
def decode string
  return URI::decode(string) if RUBY_VERSION.include? "1.8"
  URI::Escape::decode(string)
end

def rand(list, index)
  list.shuffle! if index % list.length == 0
  list[index % list.length]
end

abort "Must specify COMMAND" if options[:command].nil?
# find all of the paths in source
if options[:dir].nil?
  list_of_files = \
      %x[grep "Location" "#{options[:xml]}"].split("\n").map do |line|
    decode($1) if /<string>file:\/\/localhost(.+)<\/string>/ =~ line
  end
else
  list_of_files = %x[find "#{options[:dir].chomp("/")}" -type f].split("\n")
end
index = 0
options[:songs].times do |minute|
  begin
    abort "No valid songs" if list_of_files.length < 1
    candidate = rand(list_of_files, index)
    puts "##{minute}: Playing #{candidate}"
    %x[#{options[:command].gsub(
        /<duration>/, "#{options[:duration]}").gsub(
        /<file>/, "\"#{candidate}\"")} 2> /dev/null]
    if $? != 0
      list_of_files.delete_at(index)
    else
      index = (index + 1) % list_of_files.length
    end
  end while $? != 0
end
