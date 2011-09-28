require 'win32ole'

class WMP_Control
  def initialize(num_rounds)
    @num_rounds = num_rounds
    @player = WIN32OLE.new('WMPlayer.OCX')
    @media_collection = @player.mediaCollection
    @all_media = @media_collection.getAll()
    build_power_hour_playlist()
    @play = true
  end
  
  def build_power_hour_playlist()
    @power_hour = []
    while @power_hour.length < @num_rounds
      i = rand(@all_media.Count)
      if not @power_hour.include?(@all_media.Item(i)) and @all_media.Item(i).Duration >= 60
        @power_hour << @all_media.Item(i)
      end
    end
  end
  
  def getPowerhourSongs()
    ret = []
    for t in @power_hour
      #puts "", t.ole_get_methods
      ret << t.name
    end
    return ret
  end
  
  def start()
    while @power_hour.length > 0
      if @play
        @songStartTime = Time.now
        @player.OpenPlayer(@power_hour[0].sourceURL)
        @play = false
      end
      if @songStartTime + 60 <= Time.now
        @play = true
        @power_hour.delete_at(0)
      # if not met, wait
      else
        sleep 1
      end
      
    end
    Process.exit
  end
  
end