require 'benchmark'
require 'benchmark/ips'
require 'find'
require 'set'

MUSIC_FILETYPES = %w(aac m4a mp3 mp4).freeze

def build_file_list(dir)
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

def build_file_list2(dir)
  # find all of the paths in source
  music_files = []
  ext_match = /\.(#{MUSIC_FILETYPES.join('|')})$/
  Find.find(dir) do |path|
    if FileTest.directory?(path)
      next unless File.basename(path)[0] == '.'
      Find.prune
    elsif File.basename(path) =~ ext_match
      music_files << path
    end
  end
  music_files
end

def build_file_list3(dir)
  # find all of the paths in source
  music_files = []
  ext_suffixes = MUSIC_FILETYPES.map { |ext| ".#{ext}" }.freeze
  Find.find(dir) do |path|
    if FileTest.directory?(path)
      next unless File.basename(path)[0] == '.'
      Find.prune
    elsif ext_suffixes.include?(File.extname(path))
      music_files << path
    end
  end
  music_files
end

def build_file_list4(dir)
  # find all of the paths in source
  music_files = []
  ext_suffixes = MUSIC_FILETYPES.map { |ext| ".#{ext}" }.freeze
  Find.find(dir) do |path|
    if File.file?(path) && ext_suffixes.include?(File.extname(path))
      music_files << path
    end
  end
  music_files
end

def build_file_list5(dir)
  # find all of the paths in source
  music_files = []
  ext_suffixes = MUSIC_FILETYPES.map { |ext| ".#{ext}" }.freeze
  Find.find(dir) do |path|
    if ext_suffixes.include?(File.extname(path)) && File.file?(path)
      music_files << path
    end
  end
  music_files
end

def build_file_list6(dir)
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


music_dir = File.expand_path('~/Music/iTunes/iTunes Media/Music')
Benchmark.ips do |x|
  x.time = 25

  x.report('initial implementation') { build_file_list(music_dir) }
  x.report('move regexp out of hot path') { build_file_list2(music_dir) }
  x.report('no more regexp, File.extname comparo') { build_file_list3(music_dir) }
  x.report('no more filter dot directories') { build_file_list4(music_dir) }
  x.report('reorder File.file? check') { build_file_list5(music_dir) }
  x.report('ext_suffixes as set') { build_file_list6(music_dir) }

  x.compare!
end

# Calculating -------------------------------------
# initial implementation
#                           0.975  (± 0.0%) i/s -     25.000
# move regexp out of hot path
#                           1.891  (± 0.0%) i/s -     48.000
# no more regexp, File.extname comparo
#                           1.985  (± 0.0%) i/s -     50.000
# no more filter dot directories
#                           2.084  (± 0.0%) i/s -     53.000
# reorder File.file? check
#                           2.101  (± 0.0%) i/s -     53.000
#  ext_suffixes as set      2.123  (± 0.0%) i/s -     54.000
#
# Comparison:
#  ext_suffixes as set:        2.1 i/s
# reorder File.file? check:        2.1 i/s - 1.01x  slower
# no more filter dot directories:        2.1 i/s - 1.02x  slower
# no more regexp, File.extname comparo:        2.0 i/s - 1.07x  slower
# move regexp out of hot path:        1.9 i/s - 1.12x  slower
# initial implementation:        1.0 i/s - 2.18x  slower
