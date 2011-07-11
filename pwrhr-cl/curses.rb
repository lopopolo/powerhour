require "curses"

PROGRESS_LINE = 10
PROGRESS_WIDTH = 50

def clear
  Curses.clear
end

def write(line, col, text)
  Curses.setpos(line,col)
  Curses.addstr(text)
  Curses.curs_set(0)
  Curses.refresh
end

def init_screen
  Curses.init_screen
  #Curses.noecho
  Curses.curs_set(0)
  begin
    yield
  ensure
    Curses.close_screen
  end
end

def progress(percent, time=nil, total_time=nil)
  bar = ""
  PROGRESS_WIDTH.times do |i|
    bar = "#{bar}=" if i <= percent * PROGRESS_WIDTH
    bar = "#{bar} " if i > percent * PROGRESS_WIDTH
  end
  bar = "|#{bar}|"
  if !time.nil? && !total_time.nil?
    bar = "#{bar}%3.2f s elapsed / #{total_time}s" % time
  elsif !time.nil?
    bar = "#{bar}%3.2f s elapsed" % time
  end
  write(PROGRESS_LINE,0, "#{bar}")
end
