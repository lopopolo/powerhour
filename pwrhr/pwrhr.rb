#!/usr/bin/env ruby

require "curses"
require "optparse"
require "thread"
require "timeout"

module Powerhour
  # This is the only exposed method in the Powerhour module
  # This method parses command line options, sets up the game,
  # and accepts user input
  def self.run
    # setup before event loop
    options = parse_options
    abort "afplay is required" if %x[which afplay].empty?
    song_list = build_file_list(options[:dir])

    gui = Gui.new
    gui.base_path = options[:dir]
    gui.session_duration = options[:songs] * options[:duration]
    gui.song_duration = options[:duration]
    gui.total_songs = options[:songs]

    queue = Queue.new

    ph = Game.new(options[:songs], options[:duration], song_list, gui, queue)
    Gui.init_screen do
      ph.run
      # loop while powerhour thread not terminated
      while ph.status
        begin
          input = Timeout.timeout(GETCH_TIMEOUT) { Curses.getch }
        rescue Timeout::Error
          # continue looping
          input = 10 # noop for input switch
        end

        case input
        when Curses::Key::RIGHT, ?s, ?S
          queue << EVENT_SKIP
        when ?p, ?P
          queue << EVENT_TOGGLE_PAUSE
        when ?q, ?Q
          queue << EVENT_QUIT
        end
      end
    end
  end

  private
  # constants
  EVENT_SKIP = "SKIP"
  EVENT_TOGGLE_PAUSE = "TOGGLE_PAUSE"
  EVENT_QUIT = "QUIT"
  GETCH_TIMEOUT = 0.1
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
    dir = File.expand_path(dir) unless dir.nil?
    abort "#{dir} is not a directory" unless File.directory?(dir)

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
    attr_accessor :terminate, :skip, :playing
    attr_accessor :num_songs, :duration
    attr_accessor :all_files, :playlist
    attr_accessor :gui, :queue

    def initialize(num_songs, duration, all_files, gui, queue)
      # initialize game paramters
      @num_songs = num_songs
      @duration = duration
      @all_files = all_files
      @playlist = @all_files.shuffle
      @gui = gui
      @queue = queue
    end

    def run
      @control_thread ||= Thread.new do
        # initialize control flow bools
        @terminate = false
        @skip = false
        @playing = true

        loop do
          case @queue.pop
          when EVENT_SKIP
            @skip = true
          when EVENT_TOGGLE_PAUSE
            @playing = !@playing
          when EVENT_QUIT
            @terminate = true
            break
          end
        end
      end
      @thread ||= create_music_thread
    end

    # return the status of the game thread
    # returns false when the game is over
    def status
      @thread.status
    end

    private

    def afplay_command(candidate)
      %Q[afplay -t #{@duration} "#{candidate}"]
    end

    # check the state of the child song-playing process over
    # the course of the minute. This method updates the gui as
    # the minute progresses. It also ensures the child is
    # terminated.
    def monitor_child_process(child_pid)
      begin
        start = Time.now
        busywait = 0.1
        status = nil
        while (delta = Time.now - start) < @duration
          @gui.elapsed_song_time = delta
          @gui.elapsed_session_time = @minute * @duration + delta
          @gui.paint

          if @terminate || @skip || !@playing
            Process.kill("SIGKILL", child_pid)
            break
          end

          if status.nil?
            # check if child process has finished
            _, status = Process.wait2(child_pid, Process::WNOHANG)
            if status.nil?
              # no child has finished, so spin
              sleep busywait
            end
          elsif status.exitstatus == 0
            # child completed successfully, but we haven't gone a whole minute
            # yet, so spin
            sleep busywait
          else
            # child errored out, so break out of the loop
            break
          end
        end
      ensure
        Process.exit if @terminate
      end
    end

    # try playing a song for the current minute.
    # If we are successful, advance the current song index
    def try_song
      song = @playlist.pop
      abort "No valid songs" if song.nil?
      @gui.playing_song = song
      @gui.elapsed_song_time = 0
      @gui.current_song = @minute + 1
      @gui.paint

      # fork to execute the music command
      begin
        child_pid = Process.spawn(afplay_command(song))
        monitor_child_process(child_pid)
      rescue
        # there was a failure
        # this is ok, $? will be nonzero
      end

      unless @playing
        @playlist.push(song)
      end
      if @playlist.empty?
        @playlist = @all_files.shuffle
      end
    end

    # initialize the thread, which contains the main game loop
    def create_music_thread
      Thread.new do
        @index = @minute = 0
        while @minute < @num_songs do
          # spin if paused
          until @playing
            sleep 0.1
            Process.exit if @terminate
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

  class Gui
    BEER = [
       " [=] ",
       " | | ",
       " }@{ ",
       "/   \\",
       ":___;",
       "|&&&|",
       "|&&&|",
       "|---|",
       "'---'",
    ]

    attr_accessor :base_path, :playing_song
    attr_accessor :session_duration, :elapsed_session_time
    attr_accessor :song_duration, :elapsed_song_time
    attr_accessor :total_songs, :current_song
    attr_accessor :cols, :rows

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

    def paint
      @cols = Curses.cols
      @rows = Curses.lines
      Curses.clear
      paint_banner
      paint_song_counter
      top_height = paint_now_playing + 2
      paint_elapsed_time_bars
      paint_footer
      paint_beer(top_height, 3)
      Curses.refresh
    end

    private
    def paint_banner
      write(0, 0, "Welcome to pwrhr, serving all of your power hour needs")
    end

    def paint_song_counter
      write(1, 0, "Song #{@current_song} of #{@total_songs}")
    end

    def paint_now_playing
      write(2, 0, "Now Playing:")
      song = if @playing_song.nil?
               ""
             else
               @playing_song.gsub(/^(#{@base_path}|#{File.expand_path(@base_path)})/, "")
             end
      song.split(File::SEPARATOR).each_with_index do |component, index|
        write(3 + index, 0, "  #{component}")
      end
      1 + song.split(File::SEPARATOR).length
    end

    def paint_elapsed_time_bars
      progress(@elapsed_song_time, @song_duration, @rows - 3)
      progress(@elapsed_session_time, @session_duration, @rows - 2)
    end

    def paint_footer
      write(@rows - 1, 0, "Enter q to quit, s to skip song, p to toggle play/pause")
    end

    def paint_beer(top_height, bottom_height)
      avail_height = @rows - top_height - bottom_height
      line = (avail_height - BEER.size) / 2 + top_height
      BEER.each_with_index do |ascii, index|
        write_col = (@cols - ascii.length) / 2
        write(line + index, write_col, ascii)
      end
    end

    # A raw write method to the curses display.
    # Always refresh the display after a write.
    def write(line, col, text)
      Curses.setpos(line, col)
      Curses.addstr(text)
    end

    # helper method for formatting time elapsed
    def format_time(seconds)
      Time.at(seconds).utc.strftime("%Hh %Mm %Ss").gsub(/^00h /, "")
    end

    # write a progress bar to the screen
    def progress(elapsed, duration, output_line)
      return if elapsed.nil? || duration.nil?
      progress_bar = ""
      percent = 1.0 * elapsed / duration
      suffix = "[#{format_time elapsed} elapsed / #{format_time duration}]"
      progress_bar_width = @cols - suffix.length - 2
      [progress_bar_width, 0].max.times do |i|
        if i <= percent * progress_bar_width
          progress_bar << "="
        else
          progress_bar << " "
        end
      end
      progress_bar = "|#{progress_bar}|#{suffix}"
      write(output_line, 0, progress_bar)
    end
  end
end

# run the powerhour if this file is run as a script
if __FILE__ == $0
  Powerhour::run
end

