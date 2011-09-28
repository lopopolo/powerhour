require 'win32ole'

=begin
player = WIN32OLE.new('iTunes.Application')
    media_collection = player.LibraryPlaylist
    puts '', media_collection.Tracks.Item(100).ole_get_methods
=end

class ITunes_Control
  def initialize(num_rounds)
    @num_rounds = num_rounds
    @player = WIN32OLE.new('iTunes.Application')
    @media_collection = @player.LibraryPlaylist
    build_power_hour_playlist()
    @play = true
  end
  
  def build_power_hour_playlist()
    @power_hour = []
    tracks = []
    while @power_hour.length < @num_rounds
      i = rand(@media_collection.Tracks.Count)
      if not @power_hour.include?(@media_collection.Tracks.ItemByPlayOrder(i)) and @media_collection.Tracks.ItemByPlayOrder(i).Duration >= 60
        @power_hour << @media_collection.Tracks.ItemByPlayOrder(i)
      end
    end
  end
  
  def getPowerhourSongs()
    ret = []
    for t in @power_hour
      #puts "", t.ole_get_methods
      ret << t.Artist + ' - ' + t.Name
    end
    return ret
  end
  
  def start()
    playlist = @player.CreatePlaylist('Power Hour')
    for song in @power_hour do
      playlist.AddTrack(song)
    end
    @play = false
    playlist.PlayFirstTrack
    @songStartTime = Time.now
    while @power_hour.length > 0
      if @play
        @songStartTime = Time.now
        @player.NextTrack
        @play = false
      end
      # check next song condition
      if @songStartTime + 60 <= Time.now
        @play = true
        @power_hour.delete_at(0)
      # if not met, wait
      else
        sleep 1
      end
      
      
    end
    @player.Quit
    Process.exit
  end
  
end