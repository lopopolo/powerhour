require 'wx'
include Wx

$program = nil
$num_rounds = 0

class SetupFrame < Frame
  def initialize()
    super(nil, -1, 'Music Power Hour: Setup')
    @my_panel = Panel.new(self)
    @my_label = StaticText.new(@my_panel, -1, 'Configuration', 
      DEFAULT_POSITION, DEFAULT_SIZE, ALIGN_CENTER)
    @player_select_label = StaticText.new(@my_panel, -1, 'Select Media Player: ',
      DEFAULT_POSITION, DEFAULT_SIZE, ALIGN_LEFT)
    @player_select = Choice.new(@my_panel, -1, 
      DEFAULT_POSITION, DEFAULT_SIZE, ['iTunes', 'Windows Media Player'], 0,
      DEFAULT_VALIDATOR, 'Select Media Player')
    @round_select_label = StaticText.new(@my_panel, -1, 'Select Number of Rounds: ',
      DEFAULT_POSITION, DEFAULT_SIZE, ALIGN_LEFT)
     @round_select = Choice.new(@my_panel, -1, 
      DEFAULT_POSITION, DEFAULT_SIZE, ['60', '100', '50', '40', '30', '20', '10', '1'], 0,
      DEFAULT_VALIDATOR, 'Select Media Player')
    @start_btn = Button.new(@my_panel, -1, 'Start Your Power Hour')
    evt_button(@start_btn.get_id()) { |event| start_button_click(event)}
    
    # sizing  
    @my_panel_sizer = BoxSizer.new(VERTICAL)
    @my_panel.set_sizer(@my_panel_sizer)
    
    @my_panel_sizer.add(@my_label, 0, EXPAND|ALL, 2)
    @my_panel_sizer.add(@player_select_label, 0, EXPAND|ALL, 2)
    @my_panel_sizer.add(@player_select, 0, EXPAND|ALL, 2)
    @my_panel_sizer.add(@round_select_label, 0, EXPAND|ALL, 2)
    @my_panel_sizer.add(@round_select, 0, EXPAND|ALL, 2)
    @my_panel_sizer.add(@start_btn, 0, EXPAND|ALL, 2)
    
    show()
  end
  
  
  def start_button_click(event)
    if (@player_select.get_selection() == 0 or @player_select.get_selection() == 1) and (@round_select.get_selection() >= 0 and @round_select.get_selection() <= 7)
      if @player_select.get_selection() == 0
        $program = ITunes
      else
        $program = WMP
      end
      
      if @round_select.get_selection() == 0
        $num_rounds = 60
      elsif @round_select.get_selection() == 1
        $num_rounds = 100
      elsif @round_select.get_selection() == 7
        $num_rounds = 1
      else
        $num_rounds = (7 - @round_select.get_selection()) * 10
      end
      THE_APP.exit_main_loop()
    end
  end
end

class ControlFrame < Frame
   def initialize()
    super(nil, -1, 'Music Power Hour')
    @my_panel = Panel.new(self)
    @my_label = StaticText.new(@my_panel, -1, 'Configuration', 
      DEFAULT_POSITION, DEFAULT_SIZE, ALIGN_CENTER)
    @round_num = StaticText.new(@my_panel, -1, 'Select Media Player: ',
      DEFAULT_POSITION, Size.new(50,50), ALIGN_LEFT)
    @gauge_label = StaticText.new(@my_panel, -1, 'Round Timer',
      DEFAULT_POSITION, DEFAULT_SIZE, ALIGN_LEFT)
    @time_gauge = Gauge.new(@my_panel, -1, 60,
      DEFAULT_POSITION, DEFAULT_SIZE, GA_HORIZONTAL,
      DEFAULT_VALIDATOR, 'progress')
    @start_btn = Button.new(@my_panel, -1, 'Start Your Power Hour')
    #evt_button(@start_btn.get_id()) { |event| start_button_click(event)}
    
    # sizing  
    @my_panel_sizer = BoxSizer.new(VERTICAL)
    @my_panel.set_sizer(@my_panel_sizer)
    
    @my_panel_sizer.add(@my_label, 0, EXPAND|ALL, 2)
    @my_panel_sizer.add(@round_num, 0, EXPAND|ALL, 2)
    @my_panel_sizer.add(@gauge_label, 0, EXPAND|ALL, 2)
    @my_panel_sizer.add(@time_gauge, 0, EXPAND|ALL, 2)
    @my_panel_sizer.add(@start_btn, 0, EXPAND|ALL, 2)
    
    show()
  end
end

class WMP
  def initialize()
    require File.join(RUBYSCRIPT2EXE.appdir, 'wmp_power_hour.rb')
    #require 'wmp_power_hour.rb'
    @player = WMP_Control.new($num_rounds)
    
    @player.start()
  end
end

class ITunes
  def initialize()
    require File.join(RUBYSCRIPT2EXE.appdir, 'iTunes_power_hour.rb')
    #require 'iTunes_power_hour.rb'
    @player = ITunes_Control.new($num_rounds)
    
    @player.start()
  end
end


class ConfigApp < App
  def on_init
    SetupFrame.new
  end
end

class ControlApp < App
  def on_init
    ControlFrame.new
  end
end


ConfigApp.new.main_loop()
#ControlApp.new.main_loop()
$program.new