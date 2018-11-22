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
      config = GameProperties.new(
        iterations: options.count,
        cursor: 0,
        duration: options.duration,
        position: 0
      )

      ui = UI::TextInteractive.new
      game = Game.new(
        config,
        Player.new(Source.new(options.source_path).playlist)
      ).start

      begin
        ui.init
        while game.active?
          ui.maybe_paint(game.state)
          ui.poll do |command|
            case command
            when UI::Command::SKIP then game.skip
            when UI::Command::TOGGLE then player.toggle
            when UI::Command::QUIT then game.quit
            end
          end
        end
      ensure
        ui.close
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

    attr_reader :metadata

    def initialize(playlist)
      @playlist = playlist
      @active = false

      @player = Audite.new
      @player.events.on(:toggle) do |state|
        @active = state
      end
    end

    def advance
      song = @playlist.pop
      File.open(song, 'rb') do |f|
        tags = ID3Tag.read(f)
        @metadata = SongMetadata.new(tags.artist, tags.title, tags.album)
      end

      @player.load(song.to_path)
    end

    def toggle
      @player.toggle
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

    def on(event, &blk)
      @player.events.on(event, &blk)
    end
  end

  GameProperties = Struct.new(:iterations, :cursor, :duration, :position, keyword_init: true) do
    def elapsed
      cursor * duration + position
    end

    def game_duration
      iterations * duration
    end

    def active?
      cursor < iterations
    end
  end

  SongMetadata = Struct.new(:artist, :title, :album)
  UIState = Struct.new(:metadata, :config, keyword_init: true)

  class Game
    def initialize(props, player)
      @props = props
      @player = player

      @player.on(:position_change) do |position|
        @props.position = position
      end

      @player.on(:position_change) do |position|
        if position > @props.duration
          @props.cursor += 1
          @props.position = 0
          @player.advance
        end
      end
    end

    def start
      @player.advance
      @player.toggle
      self
    end

    def state
      UIState.new(metadata: @player.metadata.clone, config: @props.clone)
    end

    def active?
      return false unless @shutdown.nil?

      @props.active?
    end

    def skip
      @player.advance
    end

    def toggle
      @player.toggle
    end

    def quit
      @player.shutdown
      @shutdown = true
    end
  end

  module UI
    module Command
      SKIP = 'skip'
      TOGGLE = 'toggle'
      QUIT = 'quit'
    end

    class ProgressBar
      attr_writer :length, :progress

      def initialize(total:, length:)
        @total = total
        @length = length
        @progress = 0
      end

      def completed_frac
        @progress.to_f / @total
      end

      def reset
        @progress = 0
      end

      def to_s
        duration = duration(@progress)
        bar_length = @length - 2 - duration.length
        complete = '=' * (bar_length * completed_frac).floor
        incomplete = ' ' * (bar_length - complete.length)
        "|#{complete}#{incomplete}|#{duration}"
      end

      def duration(seconds)
        Time.at(seconds).utc.strftime('%H:%M:%S').delete_prefix('00:')
      end
    end

    class TextInteractive
      GETCH_TIMEOUT = 0.1

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

      def init
        Curses.init_screen
        Curses.noecho
        Curses.cbreak
        Curses.stdscr.keypad(true) # enable arrow keys
        Curses.curs_set(0)
        Curses.timeout = GETCH_TIMEOUT
        Curses.start_color
        Curses.use_default_colors
        Curses.init_pair(COLOR_BEER_TOP, Curses::COLOR_WHITE, -1)
        Curses.init_pair(COLOR_BEER_BOTTLE, Curses::COLOR_YELLOW, -1)
        Curses.init_pair(COLOR_BEER_LABEL, Curses::COLOR_RED, -1)
        Curses.init_pair(COLOR_NORMAL, -1, -1)
      end

      def close
        Curses.close_screen
        Curses.curs_set(1)
      end

      def poll
        command =
          case Curses.getch
          when Curses::Key::RIGHT, 's', 'S' then Command::SKIP
          when 'p', 'P' then Command::TOGGLE
          when 'q', 'Q' then Command::QUIT
          end
        yield command unless command.nil?
      end

      def maybe_paint(state)
        return paint(state) if @rows.nil? || @cols.nil?
        return paint(state) if @state.nil?
        return paint(state) unless @rows == Curses.lines && @cols == Curses.cols

        clear unless state.metadata == @state.metadata
        update_metadata(state.metadata) unless state.metadata == @state.metadata
        update_cursor(state.config) unless state.config.cursor == @state.config.cursor
        update_progress(state.config) unless state.config.elapsed == @state.config.elapsed
        nil
      ensure
        @state = state
        Curses.refresh
      end

      private

      def clear
        @song_bar.reset
      end

      def paint(state)
        @rows = Curses.lines
        @cols = Curses.cols
        Curses.clear

        @beer&.close
        @metadata&.close
        @cursor&.close
        @progress&.close

        # Static chrome
        Curses.stdscr << 'Welcome to pwrhr, serving all of your power hour needs'
        Curses.setpos(@rows - 1, 0)
        Curses.stdscr << 'Enter q to quit, s to skip song, p to toggle play/pause'
        beer
        # Dynamic UI
        @metadata = Curses.stdscr.derwin(3, @cols, 3, 0)
        update_metadata(state.metadata)
        @cursor = Curses.stdscr.derwin(1, @cols, 1, 0)
        update_cursor(state.config)
        @progress = Curses.stdscr.derwin(2, @cols, @rows - 3, 0)
        update_progress(state.config)
        nil
      ensure
        Curses.refresh
      end

      def with(window)
        window.clear
        yield window
      ensure
        window.refresh
      end

      def update_cursor(config)
        with(@cursor) { |window| window << "Song #{config.cursor + 1} of #{config.iterations}" }
      end

      def update_metadata(metadata)
        with(@metadata) do |window|
          window << 'Now Playing:'
          window << "\n    #{metadata.title}"
          window << "\n    #{metadata.artist} -- #{metadata.album}"
        end
      end

      def update_progress(config)
        @song_bar = ProgressBar.new(total: config.duration, length: @cols) if @song_bar.nil?
        @game_bar = ProgressBar.new(total: config.game_duration, length: @cols) if @game_bar.nil?
        @song_bar.progress = config.position
        @game_bar.progress = config.elapsed
        with(@progress) { |window| window << "#{@song_bar}#{@game_bar}" }
      end

      def beer
        cx = @cols / 2
        cy = @rows / 2
        width = BEER.map { |row| row.first.length }.max
        height = BEER.length

        @beer = Curses.stdscr.derwin(height, width, cy - height / 2, cx - width / 2)
        BEER.each do |ascii, color|
          @beer.attron(Curses.color_pair(color)) { @beer << ascii }
        end
      ensure
        @beer.refresh
      end
    end
  end
end

Powerhour::Runner.main if $PROGRAM_NAME == __FILE__
