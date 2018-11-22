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

      playlist = Source.new(options.source_path).playlist
      ui = CursesUI.new
      player = Player.new(playlist)
      game = Game.new(config, player).start

      begin
        ui.init
        while game.active?
          ui.maybe_paint(game.state)

          case Curses.getch
          when Curses::Key::RIGHT, 's', 'S'
            player.advance
          when 'p', 'P'
            player.toggle
          when 'q', 'Q'
            player.shutdown
            break
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
      @props.active?
    end
  end

  class CursesUI
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

    def maybe_paint(state)
      return paint(state) if @rows.nil? || @cols.nil?
      return paint(state) if @state.nil?
      return paint(state) unless @rows == Curses.lines && @cols == Curses.cols

      update_metadata(state.metadata) unless state.metadata == @state.metadata
      update_cursor(state.config) unless state.config.cursor == @state.config.cursor
      update_elapsed(state.config) unless state.config.elapsed == @state.config.elapsed
      nil
    ensure
      @state = state
      Curses.refresh
    end

    private

    def paint(state)
      @rows = Curses.lines
      @cols = Curses.cols
      Curses.clear
      # Static chrome
      write_line(0, 'Welcome to pwrhr, serving all of your power hour needs')
      write_line(2, 'Now Playing:')
      write_line(@rows - 1, 'Enter q to quit, s to skip song, p to toggle play/pause')
      beer(5, 3)
      # Dynamic UI
      update_metadata(state.metadata)
      update_cursor(state.config)
      update_elapsed(state.config)
      nil
    ensure
      Curses.refresh
    end

    def update_cursor(config)
      write(1, 0, "Song #{config.cursor + 1} of #{config.iterations}")
    end

    def update_metadata(metadata)
      write_line(3, "    #{metadata.title}")
      write_line(4, "    #{metadata.artist} -- #{metadata.title}")
    end

    def update_elapsed(config)
      write_line(@rows - 3, progress(config.position, config.duration))
      write_line(@rows - 2, progress(config.elapsed, config.game_duration))
    end

    def beer(top_height, bottom_height)
      avail_height = @rows - top_height - bottom_height
      line = (avail_height - BEER.size) / 2 + top_height
      BEER.each_with_index do |(ascii, color), index|
        write_col = (@cols - ascii.length) / 2
        write(line + index, write_col, ascii, color)
      end
    end

    def write(line, col, text, color = COLOR_NORMAL)
      Curses.setpos(line, col)
      Curses.attron(Curses.color_pair(color)) { Curses.addstr(text) }
    end

    def write_line(line, text, color = COLOR_NORMAL)
      clear_line(line)
      write(line, 0, text, color)
    end

    def clear_line(line)
      blanks = ' ' * Curses.cols
      write(line, 0, blanks)
    end

    def format_duration(seconds)
      Time.at(seconds).utc.strftime('%H:%M:%S').delete_prefix('00:')
    end

    def progress(elapsed, duration)
      percent = 1.0 * elapsed / duration
      suffix = "[#{format_duration(elapsed)} elapsed / #{format_duration(duration)}]"
      width = [Curses.cols - suffix.length - 2, 0].max
      progress_width = [(percent * width).ceil, width].min
      progress = '=' * progress_width
      remaining = ' ' * [width - progress_width, 0].max
      "|#{progress}#{remaining}|#{suffix}"
    end
  end
end

Powerhour::Runner.main if $PROGRAM_NAME == __FILE__
