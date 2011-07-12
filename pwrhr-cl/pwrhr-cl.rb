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

def rand(list, index, shuffle)
  list.shuffle! if index % list.length == 0 && shuffle
  list[index % list.length]
end

def build_file_list(xml, dir)
  # find all of the paths in source
  if dir.nil?
    list_of_files = \
        %x[grep "Location" "#{xml}"].split("\n").map do |line|
      decode($1) if /<string>file:\/\/localhost(.+)<\/string>/ =~ line
    end.compact
  else
    list_of_files = %x[find "#{dir.chomp("/")}" -type f].split("\n")
  end
  abort "Unable to build file list" if $? != 0
  list_of_files
end

def create_music_thread(num_songs, duration, command, list_of_files)
  return Thread.new do
    terminate = false
    trap("SIGTERM") {
      terminate = true
    }
    skip = false
    trap("HUP") {
      skip = true
    }
    playing = true
    trap("INT") {
      playing = !playing
      write(STATE_LINE,0, "PAUSED") if !playing
      write(STATE_LINE,0, "      ") if playing
      Curses.refresh
    }
    index = 0
    minute = 0
    while minute < num_songs do
      # spin if paused
      were_paused = false
      until playing
        sleep 0.1
        were_paused = true
      end
      begin
        abort "No valid songs" if list_of_files.length < 1
        candidate = rand(list_of_files, index, !were_paused)
        update_screen_for_new_minute(minute, num_songs, candidate)
        open("|-", "r+") do |child|
          if child # this is the parent process
            begin
              start = Time.now
              response_code = nil
              until response_code || terminate || skip || !playing
                delta = Time.now - start
                progress(delta, duration, PROGRESS_LINE)
                progress(minute * duration + delta, num_songs * duration,
                        PROGRESS_LINE+1, true)
                to = 0.01 * duration
                to = 0.1 if to == 0
                begin
                  response_code = Timeout.timeout(to) {
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
           exec("#{command.gsub(
              /<duration>/, "#{duration}").gsub(
              /<file>/, "\"#{candidate}\"")} &> /dev/null")
          end
        end
        if $? != 0 && playing
          list_of_files.delete_at(index)
        elsif playing
          index = (index + 1) % list_of_files.length
        end
      end while $? != 0 && !skip && playing
      minute += 1 if !skip && playing
      skip = false
    end
  end
end

# curses stuff
PROGRESS_LINE = 10
PROGRESS_WIDTH = 50
INPUT_INST_LINE = PROGRESS_LINE + 2
STATE_LINE = INPUT_INST_LINE + 1

def write(line, col, text)
  Curses.setpos(line,col)
  Curses.addstr(text)
end

def update_screen_for_new_minute(minute, num_songs, playing)
  Curses.clear
  write(0,0, "Welcome to pwrhr-cl, serving all of your power hour needs")
  write(1,0, "Song #{minute} of #{num_songs}")
  write(2,0, "Playing #{playing}")
  write(INPUT_INST_LINE,0, "Enter q to quit, s to skip song, p to toggle play/pause")
  Curses.refresh
end

def init_screen
  Curses.init_screen
  Curses.noecho
  Curses.stdscr.keypad(true) # enable arrow keys
  begin
    yield
  ensure
    Curses.close_screen
  end
end

def format_time seconds
  time = []
  int_seconds = Integer(seconds)
  hours = int_seconds / 3600
  minutes = (int_seconds / 60) % 60
  sec = seconds % 60
  time << "#{hours}h" if hours > 0
  time << "#{minutes}m" if minutes > 0
  time << "%.2fs" % sec if sec > 0
  return time.join(" ")
end

def progress(time, total_time, output_line, overall=false)
  bar = ""
  if total_time != 0
    percent = Float(time)/total_time
    PROGRESS_WIDTH.times do |i|
      bar = "#{bar}=" if i <= percent * PROGRESS_WIDTH
      bar = "#{bar} " if i > percent * PROGRESS_WIDTH
    end
    bar = "|#{bar}|"
    bar = "#{bar}[#{format_time time} elapsed / #{format_time total_time}]"
  elsif !overall
    bar = "[#{format_time time} elapsed]"
  end
  write(output_line,0, bar)
  Curses.refresh
end

init_screen do
  song_list = build_file_list(options[:xml], options[:dir])
  ph = create_music_thread(options[:songs], options[:duration],
                           options[:command], song_list)
  loop do
    case Curses.getch
    when ?q, ?Q :
      Process.kill("SIGTERM", 0)
      break
    when Curses::Key::RIGHT, ?s, ?S :
      Process.kill("HUP", 0)
    when ?p, ?P :
      Process.kill("INT", 0)
    end
  end
end
