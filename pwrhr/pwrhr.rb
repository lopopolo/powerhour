#!/usr/bin/env ruby

require "curses"
require "optparse"
require "timeout"

module Powerhour
  # This is the only exposed method in the Powerhour module
  # Thia method parses command line options, sets up the game,
  # and accepts user input
  def self.run
    # setup before event loop
    options = parse_options
    abort "afplay is required" if %x[which afplay].empty?
    song_list = build_file_list(options[:dir])

    ph = Game.new(options[:songs], options[:duration], song_list)
    Gui.init_screen do
      # loop while powerhour thread not terminated
      while ph.status
        begin
          input = Timeout.timeout(GETCH_TIMEOUT) { Curses.getch }
        rescue Timeout::Error
          # continue looping
          input = 10 # noop for input switch
        end

        case input
        when ?q, ?Q
          Process.kill("-SIGTERM", 0) # kill music thread
          break
        when Curses::Key::RIGHT, ?s, ?S
          Process.kill("SIGUSR1", 0) # send skip signal to music thread
        when ?p, ?P
          Process.kill("SIGUSR2", 0) # send pause signal to music thread
        end
      end
    end
  end

  private
  # constants
  GETCH_TIMEOUT = 1
  MUSIC_FILETYPES = %w[aac m4a mp3 mp4]

  # Parse options into a hash that is also populated with default values
  def self.parse_options
    options = {}
    opt = OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options]\n\npwrhr depends on afplay."
      options[:songs] = 60
      opts.on("-n", "--num-songs NUMBER", Integer,
              "Number of songs in the power hour (default #{options[:songs]})") do |songs|
        options[:songs] = songs
      end
      options[:duration] = 60
      opts.on("-d", "--duration SECONDS", Integer,
              "Duration of each song in seconds (default #{options[:duration]})") do |duration|
        options[:duration] = duration
      end
      options[:dir] = "~/Music/iTunes/iTunes Media/Music"
      opts.on("-D", "--directory DIR",
              "Use DIR of music files (default #{options[:dir]})") do |dir|
        options[:dir] = dir
      end
      opts.on("-h", "--help", "Display this screen") do
        puts opts
        exit
      end
    end
    opt.parse!
    options
  end

  # get all of the files in the supplied directory using glob
  def self.build_file_list(dir)
    # find all of the paths in source
    dir = File.expand_path(dir) if !dir.nil?
    abort "#{dir} is not a directory" if !File.directory?(dir)

    music_files = []
    Dir.glob("#{dir.chomp("/")}/**/*.{#{MUSIC_FILETYPES.join(",")}}") do |path|
      music_files << path
    end
    music_files
  end

  # This class encapsulates all of the game logic
  # When to play a song, keeping track of the minute,
  # which files are playable, etc.
  class Game
    attr_accessor :terminate, :skip, :playing, :game_was_paused
    attr_accessor :num_songs, :duration
    attr_accessor :all_files, :playlist

    def initialize(num_songs, duration, all_files, run_game=true)
      # initialize game paramters
      @num_songs = num_songs
      @duration = duration
      @all_files = all_files
      @playlist = @all_files.shuffle
      run if run_game
    end

    def run
      @thread = create_music_thread
    end

    # return the status of the game thread
    # returns false when the game is over
    def status
      @thread.status
    end

    private

    # Because ruby threads don't share memory, use signals
    # to pass messages to the game thread.
    # There are signals for terminating, skipping a song,
    # and toggling play/pause.
    def init_signal_handlers
      # initialize control flow bools
      @terminate = false
      @skip = false
      @playing = true
      # receive terminate signal
      trap("SIGTERM") { @terminate = true }
      # receive skip signal
      trap("SIGUSR1") { @skip = true }
      # receive the pause signal
      trap("SIGUSR2") {
        @playing = !@playing
        @playing ? Gui.write_state(" " * 6)  : Gui.write_state("PAUSED" + " " * 16)
      }
    end

    # execute the song playing command with the given song
    def execute_command(candidate)
      afplay_command = "afplay -t #{@duration} \"#{candidate}\" &> /dev/null"
      exec(afplay_command)
    end

    # check the state of the child song-playing process over
    # the course of the minute. This method updates the gui as
    # the minute progresses. It also ensures the child is
    # terminated.
    def monitor_child_process(child)
      begin
        start = Time.now
        child_is_eof = false
        until (delta = Time.now - start) >= @duration || @terminate || @skip || !@playing
          Gui.write_minute_progress(delta, @duration)
          Gui.write_overall_progress(@minute * @duration + delta, @num_songs * @duration)
          to = 0.01 * duration
          to = 0.1 if to == 0
          # check if child process has finished
          if !child_is_eof
            begin
              child_is_eof = Timeout.timeout(to) {
                Process.wait(child.pid)
              }
            rescue Timeout::Error
              # do nothing; this is expected, so continue looping
            end
          # child completed successfully, but we haven't gone a whole minute
          # yet, so spin
          elsif $? == 0
            # spin if the song ended before duration elapsed
            Gui.write_state("Song was shorter than duration. Waiting ...")
            sleep to
          else # child errored out
            break # so break out of the loop
          end
        end
      ensure
        child.close
        Process.exit if @terminate
      end
    end

    # try playing a song for the current minute.
    # If we are successful, advance the current song index
    def try_song
      song = @playlist.pop
      abort "No valid songs" if song.nil?
      Gui.update_screen_for_new_minute(@minute + 1, @num_songs, song)

      # fork to execute the music command
      open("|-", "r+") do |child|
        begin
          if child # this is the parent process
            monitor_child_process(child)
          else # in child
            execute_command(song)
          end
        rescue
          # there was a failure
          # this is ok, $? will be nonzero
        end
      end

      if !@playing
        @playlist.push(song)
      end
      if @playlist.empty?
        @playlist = @all_files.shuffle
      end
    end

    # initialize the thread, which contains the main game loop
    def create_music_thread
      return Thread.new do
        init_signal_handlers

        @index = @minute = 0
        while @minute < @num_songs do
          # spin if paused
          @game_was_paused = false
          until playing
            sleep 0.1
            @game_was_paused = true
          end

          # this is a nasty do while loop
          # because we want to try a song
          # and stop as soon as one is successful
          begin
            try_song
          end while $? != 0 && !@skip && @playing

          # if we didn't abort because we skipped or paused,
          # the song was successful, so increment the minute
          # we are on
          @minute += 1 if !@skip && @playing
          @skip = false
        end
      end
    end
  end

  # A singleton class that encapsulates all of the curses stuff
  # Because there is only ever one terminal, we can never have
  # multiple GUIs.
  class Gui
    # curses stuff
    PROGRESS_LINE = 10
    PROGRESS_WIDTH = 50
    INPUT_INST_LINE = PROGRESS_LINE + 2
    STATE_LINE = INPUT_INST_LINE + 1

    # A raw write method to the curses display.
    # Always refresh the display after a write.
    def self.write(line, col, text)
      Curses.setpos(line,col)
      Curses.addstr(text)
      Curses.refresh
    end

    # helper method for writing powerhour state
    def self.write_state(text)
      write(STATE_LINE, 0, text)
    end

    # helper method for writing overall powerhour progress
    def self.write_overall_progress(time, total_time)
      progress(time, total_time, PROGRESS_LINE + 1, true)
    end

    # helper method for writing song progress
    def self.write_minute_progress(time, total_time)
      progress(time, total_time, PROGRESS_LINE, false)
    end

    # repaint the screen for a new song
    def self.update_screen_for_new_minute(minute, num_songs, playing)
      Curses.clear
      write(0,0, "Welcome to pwrhr-cl, serving all of your power hour needs")
      write(1,0, "Song #{minute} of #{num_songs}")
      write(2,0, "Playing #{playing}")
      write(INPUT_INST_LINE, 0, "Enter q to quit, s to skip song, p to toggle play/pause")
      Curses.refresh
    end

    # setup the gui
    # pass in a code block that contains the event loop
    def self.init_screen
      Curses.init_screen
      Curses.noecho
      Curses.stdscr.keypad(true) # enable arrow keys
      Curses.curs_set(0)
      begin
        yield
      ensure
        Curses.close_screen
        Curses.curs_set(1)
      end
    end

    # helper method for formatting time elapsed
    def self.format_time seconds
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

    # write a progress bar to the screen
    def self.progress(time, total_time, output_line, overall=false)
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
  end
end

# run the powerhour if this file is run as a script
if __FILE__ == $0
  Powerhour::run
end

