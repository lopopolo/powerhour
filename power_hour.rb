#!/usr/bin/env ruby

require "optparse"
require "URI"

ITUNES_XML = "$HOME/Music/iTunes/iTunes Music Library.xml"

options = {}
opt = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]\n\n"
  options[:songs] = 60
  opts.on("-n", "--number-of-songs NUMBER", Integer,  \
      "Number of songs in the power hour (default 60)") do |songs|
    options[:songs] = songs
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

def get_random_file(list)
  return decode($1) if /<string>file:\/\/localhost(.+)<\/string>/ =~ \
    list[rand(list.length)]
  list[rand(list.length)]
end

# find all of the paths in source
# this assumes there are only audio files in the source
if options[:dir].nil?
  list_of_files = %x[grep "Location" "#{ITUNES_XML}"].split("\n")
else
  list_of_files = %x[find "#{options[:dir].chomp("/")}" -type f].split("\n")
end
options[:songs].times do |minute|
  begin
    candidate = get_random_file(list_of_files)
    puts "##{minute}: Playing #{candidate}"
    %x[afplay "#{candidate}" -t #{options[:duration]}]
  end while $? != 0
end
