#!/usr/bin/env ruby

require 'curses'
require 'find'
require 'id3tag'
require 'optparse'
require 'shellwords'
require 'thread'
require 'timeout'

module Powerhour
  # This is the only exposed method in the Powerhour module
  # This method parses command line options, sets up the game,
  # and accepts user input
  def self.run
    # setup before event loop
    abort 'afplay is required' if %x(which afplay).empty?
    options = parse_options
    options[:dir] = File.expand_path(options[:dir])
    song_list = build_file_list(options[:dir])

    gui = Gui.new(options[:duration], options[:songs])
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
          input = Curses::Key::ENTER # noop for input switch
        end

        case input
        when Curses::Key::RIGHT, 's', 'S'
          queue << EVENT_SKIP
        when 'p', 'P'
          queue << EVENT_TOGGLE_PAUSE
        when 'q', 'Q'
          queue << EVENT_QUIT
        else
          # Ignore all other key input
        end
      end
    end
  end

  # constants
  EVENT_SKIP = 'SKIP'.freeze
  EVENT_TOGGLE_PAUSE = 'TOGGLE_PAUSE'.freeze
  EVENT_QUIT = 'QUIT'.freeze
  BUSYWAIT = 0.1
  GETCH_TIMEOUT = 0.1
  MUSIC_FILETYPES = %w(aac m4a mp3 mp4).freeze

  SONG_SUCCESS_CODE = 0
  SONG_FAILED_CODE = 1

  # Parse options into a hash that is also populated with default values
  def self.parse_options
    options = {}
    opt = OptionParser.new do |opts|
      opts.banner = "Usage: #{$PROGRAM_NAME} [options]\n\npwrhr depends on afplay."
      options[:songs] = 60
      opts.on('-n', '--num-songs NUMBER', Integer,
              "Number of songs in the power hour (default #{options[:songs]})") do |songs|
        options[:songs] = songs
      end
      options[:duration] = 60
      opts.on('-d', '--duration SECONDS', Integer,
              "Duration of each song in seconds (default #{options[:duration]})") do |duration|
        options[:duration] = duration
      end
      options[:dir] = '~/Music/iTunes/iTunes Media/Music'
      opts.on('-D', '--directory DIR',
              "Use DIR of music files (default #{options[:dir]})") do |dir|
        options[:dir] = dir
      end
      opts.on('-h', '--help', 'Display this screen') do
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
    music_files = []
    Find.find(dir) do |path|
      if FileTest.directory?(path)
        next unless File.basename(path)[0] == '.'
        Find.prune
      elsif File.basename(path) =~ /\.(#{MUSIC_FILETYPES.join('|')})$/
        music_files << path
      end
    end
    music_files
  end

  class Playlist
    def initialize(all_files)
      @all_files = all_files
      @playlist = all_files.shuffle
    end

    def fetch
      @playlist = @all_files.shuffle if @playlist.empty?
      @playlist.pop
    end

    def reenqueue(song)
      @playlist.push(song)
    end
  end

  # This class encapsulates all of the game logic
  # When to play a song, keeping track of the minute,
  # which files are playable, etc.
  class Game
    attr_accessor :num_songs, :duration
    attr_accessor :playlist
    attr_accessor :gui, :queue

    def initialize(num_songs, duration, all_files, gui, queue)
      # initialize game paramters
      @num_songs = num_songs
      @duration = duration
      @playlist = Playlist.new(all_files)
      @gui = gui
      @queue = queue
    end

    def run
      # initialize control flow bools
      @terminate = false
      @skip = false
      @playing = true
      @minute = 0

      @control_thread ||= Thread.new do
        loop do
          case @queue.pop
          when EVENT_SKIP
            @skip = true
          when EVENT_TOGGLE_PAUSE
            @playing = !@playing
          when EVENT_QUIT
            @terminate = true
            break
          else
            # ignore all other events
          end
        end
      end
      @music_thread ||= Thread.new do
        music_loop
      end
    end

    # return the status of the game thread
    # returns false when the game is over
    def status
      @music_thread.status
    end

    def playing?
      @playing
    end

    def paused?
      !@playing
    end

    private

    def afplay_command(candidate)
      ['afplay', '-t', @duration.to_s, candidate].shelljoin
    end

    # check the state of the child song-playing process over
    # the course of the minute. This method updates the gui as
    # the minute progresses. It also ensures the child is
    # terminated.
    def monitor_child_process(child_pid)
      start = Time.now
      status = nil
      while (delta = Time.now - start) < @duration
        @gui.elapsed_song_time = delta
        @gui.elapsed_session_time = @minute * @duration + delta
        @gui.paint

        if @terminate || @skip || paused?
          Process.kill('SIGKILL', child_pid)
          throw :terminate if @terminate
        end

        if status.nil?
          # no child has finished, so spin
          sleep BUSYWAIT
          # check if child process has finished
          _, status = Process.wait2(child_pid, Process::WNOHANG)
        elsif status.exitstatus == 0
          # child completed successfully, but we haven't gone a whole minute
          # yet, so spin
          sleep BUSYWAIT
        else
          # child errored out, so break out of the loop
          break
        end
      end
      if status.nil?
        SONG_SUCCESS_CODE
      elsif status.exitstatus == 0
        SONG_SUCCESS_CODE
      else
        SONG_FAILED_CODE
      end
    end

    # try playing a song for the current minute.
    # If we are successful, advance the current song index
    def try_song(song)
      abort 'No valid songs' if song.nil?
      File.open(song, 'rb') do |f|
        # @type tags [ID3Tag::Tag]
        tags = ID3Tag.read(f)
        @gui.song_info = SongInfo.new(tags.artist, tags.title, tags.album)
      end
      @gui.elapsed_song_time = 0
      @gui.current_song = @minute + 1
      @gui.paint

      # fork to execute the music command
      begin
        child_pid = Process.spawn(afplay_command(song))
        monitor_child_process(child_pid)
      rescue
        # there was a failure; assign fail code
        SONG_FAILED_CODE
      end
    end

    # Main game--music playing--loop
    def music_loop
      catch :terminate do
        while @minute < @num_songs
          # spin if paused
          until @playing
            sleep BUSYWAIT
            throw :terminate if @terminate
          end

          song = @playlist.fetch
          loop do
            status = try_song(song)
            break if status == SONG_SUCCESS_CODE
            break if @skip
            break if paused?
          end
          @playlist.reenqueue(song) if paused?

          # if we didn't abort because we skipped or paused,
          # the song was successful, so increment the minute
          # we are on
          @minute += 1 if !@skip && @playing
          @skip = false
        end
      end
    end
  end

  SongInfo = Struct.new(:artist, :title, :album)

  class Gui
    BEER = [
        ' [=] ',
        ' | | ',
        ' }@{ ',
        '/   \\',
        ':___;',
        '|&&&|',
        '|&&&|',
        '|---|',
        "'---'",
    ].freeze

    attr_accessor :song_info
    attr_accessor :elapsed_session_time
    attr_accessor :elapsed_song_time
    attr_accessor :current_song

    def initialize(song_duration, total_songs)
      @session_duration = song_duration * total_songs
      @song_duration = song_duration
      @total_songs = total_songs
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

    def paint
      @cols = Curses.cols
      @rows = Curses.lines
      Curses.clear
      top_height = 0
      bottom_height = 0
      top_height += paint_banner
      top_height += paint_song_counter
      top_height += paint_now_playing
      bottom_height += paint_elapsed_time_bars
      bottom_height += paint_footer
      paint_beer(top_height, bottom_height)
      Curses.refresh
    end

    private

    def paint_banner
      write(0, 0, 'Welcome to pwrhr, serving all of your power hour needs')
      1
    end

    def paint_song_counter
      write(1, 0, "Song #{@current_song} of #{@total_songs}")
      1
    end

    def paint_now_playing
      return 3 if @song_info.nil? || @song_info.title.nil? || @song_info.artist.nil? || @song_info.album.nil?
      write(2, 0, 'Now Playing:')
      write(3, 4, @song_info.title)
      write(4, 4, "#{@song_info.artist} -- #{@song_info.album}")
      3
    end

    def paint_elapsed_time_bars
      progress(@elapsed_song_time, @song_duration, @rows - 3)
      progress(@elapsed_session_time, @session_duration, @rows - 2)
      2
    end

    def paint_footer
      write(@rows - 1, 0, 'Enter q to quit, s to skip song, p to toggle play/pause')
      1
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
      Time.at(seconds).utc.strftime('%Hh %Mm %Ss').gsub(/^00h /, '')
    end

    # write a progress bar to the screen
    def progress(elapsed, duration, output_line)
      return if elapsed.nil? || duration.nil?
      progress_bar = ''
      percent = 1.0 * elapsed / duration
      suffix = "[#{format_time elapsed} elapsed / #{format_time duration}]"
      progress_bar_width = [@cols - suffix.length - 2, 0].max
      progress_bar << '=' * (percent * progress_bar_width).to_i
      progress_bar << ' ' * (progress_bar_width - (percent * progress_bar_width).to_i)
      progress_bar = "|#{progress_bar}|#{suffix}"
      write(output_line, 0, progress_bar)
    end
  end
end

Powerhour.run if __FILE__ == $PROGRAM_NAME
