#!/usr/bin/env ruby
# frozen_string_literal: true

require 'audite'
require 'curses'
require 'find'
require 'id3tag'
require 'optparse'
require 'set'
require 'shellwords'
require 'thread'

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
        case Curses.getch
        when Curses::Key::RIGHT, 's', 'S'
          queue << EVENT_SKIP
        when 'p', 'P'
          queue << EVENT_TOGGLE_PAUSE
        when 'q', 'Q'
          queue << EVENT_QUIT
        end
      end
    end
  end

  # constants
  EVENT_SKIP = 'SKIP'
  EVENT_TOGGLE_PAUSE = 'TOGGLE_PAUSE'
  EVENT_QUIT = 'QUIT'
  BUSYWAIT = 0.1
  GETCH_TIMEOUT = 0.1
  MUSIC_FILETYPES = %w(mp3).freeze

  SONG_SUCCESS_CODE = 0
  SONG_FAILED_CODE = 1

  # Parse options into a hash that is also populated with default values
  def self.parse_options
    options = { songs: 60, duration: 60, dir: '~/Music/iTunes/iTunes Media/Music' }
    ARGV.options do |opts|
      opts.banner = <<~EOF
        Usage: #{$PROGRAM_NAME} [options]

        pwrhr depends on the afplay utility.

        OPTIONS
      EOF
      opts.on('-n', '--num-songs NUMBER', Integer, 'Number of songs in the power hour') { |val| options[:songs] = val }
      opts.on('-d', '--duration SECONDS', Integer, 'Duration to play each song in seconds') { |val| options[:duration] = val }
      opts.on('-D', '--directory DIR', 'Use DIR of music files') { |val| options[:dir] = val }
      opts.on('-h', '--help', 'Display this screen') do
        puts opts
        puts "\nDEFAULTS"
        options.each_pair do |option, default|
          puts "    #{option}: #{default}"
        end
        exit
      end
      opts.parse!
    end
    options
  end

  # get all of the files in the supplied directory using glob
  def self.build_file_list(dir)
    # find all of the paths in source
    music_files = []
    ext_suffixes = Set.new(MUSIC_FILETYPES.map { |ext| ".#{ext}" }).freeze
    Find.find(dir) do |path|
      if ext_suffixes.include?(File.extname(path)) && File.file?(path)
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

  GameControls = Struct.new(:terminate, :skip, :playing)

  GameProperties = Struct.new(:num_songs, :duration, :minute, :song_start, :game_start, :song_pause_offset) do
    def song_delta
      Time.now - song_start - song_pause_offset
    end

    def game_delta
      @game_pause_offset ||= 0
      Time.now - game_start - @game_pause_offset
    end

    def start_pause
      @paused_at = Time.now
    end

    def end_pause
      offset = Time.now - @paused_at
      self.song_pause_offset += offset
      @game_pause_offset ||= 0
      @game_pause_offset += offset
    end
  end

  SongInfo = Struct.new(:artist, :title, :album)

  # This class encapsulates all of the game logic
  # When to play a song, keeping track of the minute,
  # which files are playable, etc.
  class Game
    attr_accessor :num_songs, :duration
    attr_accessor :playlist, :player
    attr_accessor :gui, :queue

    def initialize(num_songs, duration, all_files, gui, queue)
      @props = GameProperties.new(num_songs, duration, 0, Time.now, Time.now, 0)
      @controls = GameControls.new(false, false, true)
      @playlist = Playlist.new(all_files)
      @gui = gui
      @queue = queue

      @player = Audite.new
      @player.events.on(:position_change) do
        delta = @props.song_delta
        @gui.elapsed_song_time = delta
        @gui.elapsed_session_time = @props.game_delta
        @gui.paint
      end
    end

    def run
      @control_thread ||= Thread.new do
        loop do
          case @queue.pop
          when EVENT_SKIP
            @controls.skip = true
          when EVENT_TOGGLE_PAUSE
            @controls.playing = !@controls.playing
          when EVENT_QUIT
            @controls.terminate = true
            break
          else
            $stderr.puts('Control thread received invalid event ... ignoring.')
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
      @controls.playing
    end

    def paused?
      !playing?
    end

    private

    def afplay_command(candidate)
      ['afplay', '-t', @props.duration.to_s, candidate].shelljoin
    end

    # check the state of the child song-playing process over
    # the course of the minute. This method updates the gui as
    # the minute progresses. It also ensures the child is
    # terminated.
    def monitor_child_process(child_pid)
      start = Time.now
      status = nil
      while (delta = Time.now - start) < @props.duration
        @gui.elapsed_song_time = delta
        @gui.elapsed_session_time = @props.game_delta
        @gui.paint

        if @controls.terminate || @controls.skip || paused?
          Process.kill('SIGKILL', child_pid)
          throw :terminate if @controls.terminate
        end

        if status.nil?
          # no child has finished, so spin
          sleep BUSYWAIT
          # check if child process has finished
          _, status = Process.wait2(child_pid, Process::WNOHANG)
        elsif status.exitstatus.zero?
          # child completed successfully, but we haven't gone a whole minute
          # yet, so spin
          sleep BUSYWAIT
        else
          # child errored out, so break out of the loop
          break
        end
      end
      if status.nil?
        Process.waitpid(child_pid)
        SONG_SUCCESS_CODE
      elsif status.exitstatus.zero?
        SONG_SUCCESS_CODE
      else
        SONG_FAILED_CODE
      end
    end

    # try playing a song for the current minute.
    def try_song(song, player_should_resume)
      File.open(song, 'rb') do |f|
        # @type tags [ID3Tag::Tag]
        tags = ID3Tag.read(f)
        @gui.song_info = SongInfo.new(tags.artist, tags.title, tags.album)
      end
      @gui.elapsed_song_time = 0
      @gui.elapsed_session_time = @props.game_delta
      @gui.current_song = @props.minute + 1
      @gui.paint

      player.load(song) unless player_should_resume
      player.toggle

      while @props.song_delta < @props.duration
        break if paused? || @controls.skip
        throw :terminate if @controls.terminate
        sleep BUSYWAIT
      end

      player.stop_stream

      SONG_SUCCESS_CODE
    end

    # Main game--music playing--loop
    def music_loop
      catch :terminate do
        while @props.minute < @props.num_songs
          # spin if paused
          player_should_resume = paused?
          while paused?
            sleep BUSYWAIT
            throw :terminate if @controls.terminate
          end
          if player_should_resume
            @props.end_pause
          else
            @props.song_start = Time.now
            @props.song_pause_offset = 0
          end

          song = @playlist.fetch
          loop do
            status = try_song(song, player_should_resume)
            break if status == SONG_SUCCESS_CODE
            break if @controls.skip
            break if paused?
          end
          if paused?
            @playlist.reenqueue(song)
            @props.start_pause
          end

          # if we didn't abort because we skipped or paused,
          # the song was successful, so increment the minute
          # we are on
          @props.minute += 1 if !@controls.skip && playing?
          @controls.skip = false
        end
      end
    end
  end

  class Gui
    COLOR_BEER_TOP = 1
    COLOR_BEER_BOTTLE = 2
    COLOR_BEER_LABEL = 3
    COLOR_NORMAL = 4

    BEER = [
      [' [=] ', COLOR_BEER_TOP],
      [' | | ', COLOR_BEER_BOTTLE],
      [' }@{ ', COLOR_BEER_LABEL],
      ['/   \\', COLOR_BEER_BOTTLE],
      [':___;', COLOR_BEER_BOTTLE],
      ['|&&&|', COLOR_BEER_LABEL],
      ['|&&&|', COLOR_BEER_LABEL],
      ['|---|', COLOR_BEER_BOTTLE],
      ["'---'", COLOR_BEER_BOTTLE]
    ].freeze

    attr_accessor :song_info
    attr_accessor :elapsed_session_time
    attr_accessor :elapsed_song_time
    attr_accessor :current_song

    def initialize(song_duration, total_songs)
      @session_duration = song_duration * total_songs
      @song_duration = song_duration
      @total_songs = total_songs
      @current_song = nil
      @song_info = SongInfo.new(nil, nil, nil)
      @elapsed_song_time = 0
      @elapsed_session_time = 0
    end

    # setup the gui
    # pass in a code block that contains the event loop
    def self.init_screen
      Curses.init_screen
      Curses.noecho
      Curses.stdscr.keypad(true) # enable arrow keys
      Curses.curs_set(0)
      Curses.timeout = GETCH_TIMEOUT
      Curses.start_color
      Curses.use_default_colors
      Curses.init_pair(COLOR_BEER_TOP, Curses::COLOR_WHITE, -1)
      Curses.init_pair(COLOR_BEER_BOTTLE, Curses::COLOR_YELLOW, -1)
      Curses.init_pair(COLOR_BEER_LABEL, Curses::COLOR_RED, -1)
      Curses.init_pair(COLOR_NORMAL, -1, -1)
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
      write(1, 0, "Song #{@current_song} of #{@total_songs}") unless @current_song.nil? || @total_songs.nil?
      1
    end

    def paint_now_playing
      write(2, 0, 'Now Playing:')
      unless @song_info.nil?
        write(3, 4, @song_info.title) unless @song_info.title.nil?
        write(4, 4, "#{@song_info.artist} -- #{@song_info.album}") unless @song_info.artist.nil? || @song_info.album.nil?
      end
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
        ascii, color = *ascii
        write_col = (@cols - ascii.length) / 2
        write(line + index, write_col, ascii, color)
      end
    end

    # A raw write method to the curses display.
    # Always refresh the display after a write.
    def write(line, col, text, color = COLOR_NORMAL)
      Curses.setpos(line, col)
      Curses.attron(Curses.color_pair(color)) { Curses.addstr(text) }
    end

    # helper method for formatting time elapsed
    def format_time(seconds)
      Time.at(seconds).utc.strftime('%H:%M:%S').gsub(/^00:/, '')
    end

    # write a progress bar to the screen
    def progress(elapsed, duration, output_line)
      return if elapsed.nil? || duration.nil?
      progress_bar = ''.dup
      percent = 1.0 * elapsed / duration
      suffix = "[#{format_time elapsed} elapsed / #{format_time duration}]"
      progress_bar_width = [@cols - suffix.length - 2, 0].max
      filled_in_width = [(percent * progress_bar_width).ceil, progress_bar_width].min
      progress_bar << '=' * filled_in_width
      progress_bar << ' ' * [(progress_bar_width - filled_in_width), 0].max
      progress_bar = "|#{progress_bar}|#{suffix}"
      write(output_line, 0, progress_bar)
    end
  end
end

Powerhour.run if __FILE__ == $PROGRAM_NAME
