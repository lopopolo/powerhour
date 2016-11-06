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


n = 25
music_dir = File.expand_path('~/Music/iTunes/iTunes Media/Music')
Benchmark.ips do |x|
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
#                           0.983  (± 0.0%) i/s -      5.000
# move regexp out of hot path
#                           1.887  (± 0.0%) i/s -     10.000  in   5.298972s
# no more regexp, File.extname comparo
#                           2.038  (± 0.0%) i/s -     11.000  in   5.399178s
# no more filter dot directories
#                           2.082  (± 0.0%) i/s -     11.000  in   5.285365s
# reorder File.file? check
#                           2.095  (± 0.0%) i/s -     11.000  in   5.255089s
#  ext_suffixes as set      2.106  (± 0.0%) i/s -     11.000
#
# Comparison:
#  ext_suffixes as set:        2.1 i/s
# reorder File.file? check:        2.1 i/s - 1.01x  slower
# no more filter dot directories:        2.1 i/s - 1.01x  slower
# no more regexp, File.extname comparo:        2.0 i/s - 1.03x  slower
# move regexp out of hot path:        1.9 i/s - 1.12x  slower
# initial implementation:        1.0 i/s - 2.14x  slower
