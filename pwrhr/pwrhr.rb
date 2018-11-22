#!/usr/bin/env ruby
# frozen_string_literal: true

require 'audite'
require 'curses'
require 'find'
require 'id3tag'
require 'optparse'
require 'pathname'
require 'set'

module Powerhour
  class Runner
    Options = Struct.new(:count, :duration, :source, keyword_init: true) do
      def source_path
        Pathname.new(source).expand_path
      end
    end

    def self.main
      options = parse_options(ARGV)
      playlist = Source.new(options.source_path).playlist
      gui = Gui.new(options.duration, options.count)
      queue = Queue.new

      game = Game.new(options.count, options.duration, playlist, gui, queue)
      game.run
      Gui.init_screen do
        # loop while power hour thread not terminated
        while game.active?
          event =
            case Curses.getch
            when Curses::Key::RIGHT, 's', 'S'
              EVENT_SKIP
            when 'p', 'P'
              EVENT_TOGGLE_PAUSE
            when 'q', 'Q'
              EVENT_QUIT
            else
              EVENT_NOOP
            end
          queue << event if event != EVENT_NOOP
        end
      end
    end

    def self.parse_options(args)
      options = Options.new(count: 60, duration: 60, source: '~/Music/iTunes/iTunes Media/Music')
      opt_parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
        opts.separator('')
        opts.separator('OPTIONS')

        opts.on('-c', '--count NUMBER', Integer,
                'Number of songs in the power hour') do |val|
          options.count = val
        end
        opts.on('-d', '--duration SECONDS', Integer,
                'Duration to play each song in seconds') do |val|
          options.duration = val
        end
        opts.on('-s', '--source DIR', 'Scan DIR for music files') do |val|
          options.source = val
        end
        opts.on('-h', '--help', 'Display this screen') do
          puts opts
          puts "\nDEFAULTS"
          options.each_pair do |option, default|
            puts "    #{option}: #{default}"
          end
          exit
        end
      end
      opt_parser.parse!(args)
      options
    end
  end

  # constants
  EVENT_SKIP = 'SKIP'
  EVENT_TOGGLE_PAUSE = 'TOGGLE_PAUSE'
  EVENT_QUIT = 'QUIT'
  EVENT_NOOP = 'NOOP'
  GETCH_TIMEOUT = 0.1

  class Source
    EXT = Set.new(%w[.mp3]).freeze

    def initialize(path)
      @path = path
    end

    def playlist
      sources = []
      Find.find(@path) do |path|
        path = Pathname.new(path)
        next unless EXT.include?(path.extname.downcase)
        next unless path.file?

        sources << path
      end
      Playlist.new(sources)
    end
  end

  class Playlist
    def initialize(sources)
      @sources = sources
      @playlist = sources.shuffle
    end

    def pop
      @playlist = @sources.shuffle if @playlist.empty?
      @playlist.pop
    end

    def push(song)
      @playlist.push(song)
    end
  end

  class Player
    ADVANCE = 'advance-command'
    SHUTDOWN = 'shutdown-command'
    SKIP = 'skip-command'

    attr_reader :queue

    def initialize(playlist, gui)
      @playlist = playlist
      @gui = gui
      @active = false
      @queue = Queue.new

      @player = Audite.new
      @player.events.on(:toggle) do |state|
        @active = state
      end

      @command_thread = Thread.new do
        while (command = @queue.pop)
          case command
          when Proc then command.call(@player)
          when ADVANCE then advance
          when SKIP then advance
          when SHUTDOWN
            shutdown
            break
          end
        end
      end
    end

    def advance
      song = @playlist.pop
      File.open(song, 'rb') do |f|
        tags = ID3Tag.read(f)
        @gui.song_info = SongInfo.new(tags.artist, tags.title, tags.album)
      end

      @player.load(song.to_path)
    end

    def shutdown
      @player.toggle if playing?
    end

    def playing?
      @active
    end

    def paused?
      !playing?
    end
  end

  GameProperties = Struct.new(:iterations, :cursor, :duration, keyword_init: true) do
    def elapsed(position)
      cursor * duration + position
    end

    def active?
      cursor < iterations
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

    def initialize(num_songs, duration, playlist, gui, queue)
      @props = GameProperties.new(iterations: num_songs, cursor: 0, duration: duration)
      @gui = gui
      @queue = queue

      @player = Player.new(playlist, @gui)

      @player.queue.push(lambda do |a|
        a.events.on(:position_change) do |position|
          @gui.elapsed_song_time = position
          @gui.elapsed_session_time = @props.elapsed(position)
          @gui.paint
        end

        a.events.on(:position_change) do |position|
          player.queue.push(Player::ADVANCE) if position > @props.duration
        end
      end)
    end

    def run
      @control_thread ||= Thread.new do
        loop do
          case @queue.pop
          when EVENT_SKIP
            @player.queue.push(Player::SKIP)
          when EVENT_TOGGLE_PAUSE
            @player.queue.push(->(a) { a.toggle })
          when EVENT_QUIT
            @player.queue.push(Player::SHUTDOWN)
            @shutdown = true
            break
          when EVENT_NOOP
            # noop
            nil
          else
            $stderr.warn('Control thread received invalid event ... ignoring.')
          end
        end
      end
      @player.queue.push(Player::ADVANCE)
      @player.queue.push(->(a) { a.toggle })
      nil
    end

    def active?
      return false if @shutdown

      @props.active?
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
      Time.at(seconds).utc.strftime('%H:%M:%S').delete_prefix('00:')
    end

    # write a progress bar to the screen
    def progress(elapsed, duration, output_line)
      return if elapsed.nil? || duration.nil?

      progress_bar = +''
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

Powerhour::Runner.main if $PROGRAM_NAME == __FILE__
