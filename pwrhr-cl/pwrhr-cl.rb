#!/usr/bin/env ruby

require "curses"
require "optparse"
require "timeout"
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
  opts.on("-x", "--xml FILE", \
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
  opts.on("-c", "--command \"COMMAND --some-switch <duration> <file>\"", \
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
abort "Must specify COMMAND" if options[:command].nil?

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

def build_file_list options
  # find all of the paths in source
  if options[:dir].nil?
    list_of_files = \
        %x[grep "Location" "#{options[:xml]}"].split("\n").map do |line|
      decode($1) if /<string>file:\/\/localhost(.+)<\/string>/ =~ line
    end.compact
  else
    list_of_files = %x[find "#{options[:dir].chomp("/")}" -type f].split("\n")
  end
  abort "Unable to build file list" if $? != 0
  list_of_files
end

def create_music_thread options
  return Thread.new do
    index = 0
    terminate = false
    trap("SIGTERM") {
      terminate = true
    }
    list_of_files = build_file_list options
    options[:songs].times do |minute|
      begin
        abort "No valid songs" if list_of_files.length < 1
        candidate = rand(list_of_files, index)
        update_screen_for_new_minute(minute, options[:songs], candidate)
        open("|-", "r+") do |child|
          if child # this is the parent process
            begin
              start = Time.now
              response_code = nil
              until response_code || terminate
                delta = Time.now - start
                progress(Float(delta)/options[:duration], \
                         delta, options[:duration])
                begin
                  response_code = Timeout.timeout(0.01*options[:duration]) {
                    child.readlines
                  }
                rescue Timeout::Error
                  # do nothing; this is expected, so continue looping
                end
              end
            ensure
              # no need to call child.close because we already
              # wait for the process to end. Otherwise, we are
              # terminating anyway
              Process.kill("TERM", child.pid)
              Process.exit if terminate
            end
          else
           exec("#{options[:command].gsub(
              /<duration>/, "#{options[:duration]}").gsub(
              /<file>/, "\"#{candidate}\"")} 2> /dev/null")
          end
        end
        if $? != 0
          list_of_files.delete_at(index)
        else
          index = (index + 1) % list_of_files.length
        end
      end while $? != 0
    end
  end
end

# curses stuff
PROGRESS_LINE = 10
PROGRESS_WIDTH = 50

def write(line, col, text)
  Curses.setpos(line,col)
  Curses.addstr(text)
end

def update_screen_for_new_minute(minute, num_songs, playing)
  Curses.clear
  write(0,0, "Welcome to pwrhr-cl, serving all of your power hour needs")
  write(1,0, "Song #{minute} of #{num_songs}")
  write(2,0, "Playing #{playing}")
  write(PROGRESS_LINE+1,0, "Enter q to quit")
  Curses.refresh
end

def init_screen
  Curses.init_screen
  Curses.noecho
  begin
    yield
  ensure
    Curses.close_screen
  end
end

def progress(percent, time=nil, total_time=nil)
  bar = ""
  PROGRESS_WIDTH.times do |i|
    bar = "#{bar}=" if i <= percent * PROGRESS_WIDTH
    bar = "#{bar} " if i > percent * PROGRESS_WIDTH
  end
  bar = "|#{bar}|"
  if !time.nil? && !total_time.nil?
    bar = "#{bar}[%.2fs elapsed / #{total_time}s]" % time
  elsif !time.nil?
    bar = "#{bar}[%.2f s elapsed]" % time
  end
  write(PROGRESS_LINE,0, "#{bar}")
  Curses.refresh
end

init_screen do
  ph = create_music_thread options
  loop do
    case Curses.getch 
    when ?q, ?Q :
      Process.kill("SIGTERM", 0)
      break
    end
  end
end
