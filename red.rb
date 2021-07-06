#!/usr/bin/env ruby
require 'curses'
require 'coderay'
def setpos l, c
  puts "\033[#{l};#{c}H"
end
class Historized
  attr_reader :actions, :dirty, :what
  def initialize what
    @actions = []
    @what = what
    @dirty = false
  end
  def method_missing(m, *args, &block)  
    @what.send m, *args, &block
  end  
  def delete_at i
    @actions << {name: :delete_at, index: i, line: @what[i]}
    @what.delete_at i
    @dirty = true
  end
  def insert_line line
    @actions << {name: :add_line, index: line + 1, line: ""}
    @what = @what[0..line] + [""] + @what[line+1..@what.size-1]
  end
  def paste_at i
    action = @actions.last
    return if action.nil?
    @actions << {name: :paste_at, index: i, line: action[:line]}
    insert(i, action[:line])
    @dirty = true
  end
  def undo
    action = @actions.pop
    return if action.nil?
    case action[:name]
    when :add_line
      @what.delete_at(action[:index])
    else
      @what.insert(action[:index], action[:line])
    end
  end
end
class Buffer
  attr_accessor :cursor, :path
  def initialize path, dimension
    @dimension = dimension
    @path = path
    @contents = Historized.new File.exists?(path) ? File.read(path).split("\n") : [""]
    @cursor = [0, 0]
  end
  def contents i
    i = i % @contents.size
    [i, @contents[i]]
  end
  def search search
    (@cursor[0]...@contents.what.size).each do |i|
      if @contents.what[i].include? search
        @cursor[0] = i
        setpos(i, @cursor[1])
      end
    end
    ""
  end
  def method_missing(m, *args, &block)  
    @contents.send m, *args
  end  
  def language
    if @path.end_with? ".go"
      :go
    else
      :ruby
    end
  end
  def show 
    i = @cursor[0] - @dimension[0]/2 
    (@dimension[0] - 1).times.each do |dline|
      c = contents i
      i += 1
      line = c[1]
      delta = @dimension[1] - line.size
      line = line + (delta > 0 ? (" " * delta) : "")
      setpos dline, 0
      print CodeRay.scan(line, language).terminal
      #Curses.addstr(line)
    end
  end
  def status
    s = path 
    s += "(#{@cursor.join(",")})"
    s += "(+)" if @contents.dirty
    s
  end
  def pos
    @cursor[0] % @contents.size
  end
  def delete
    @contents.delete_at pos
  end
  def paste
    @contents.paste_at pos
  end
  def show_cursor
    setpos @dimension[0] / 2, @cursor[1]
  end
  def left 
    cursor[1] -= 1 if cursor[1] > 0
  end
  def right
    cursor[1] += 1
  end
  def last
    @cursor[1] = @contents[@cursor[0]].size
  end
  def first
    @cursor[1] = 0
  end
  def word
    index = @contents[@cursor[0]].index(/ \w+/, @cursor[1] + 1)
    @cursor[1] = index if index
  end
  def bword
    index = @contents[@cursor[0]].reverse.index(/ \w+/, @contents[@cursor[0]].size - @cursor[1] + 1)
    @cursor[1] = @contents[@cursor[0]].size - index if index
  end
  def insert c
    old = @contents[@cursor[0]]
    prefix = @cursor[1] >= 1 ? old[0..@cursor[1]-1] : ""
    @contents[@cursor[0]] = prefix + c + old[@cursor[1]..old.size-1] if c.is_a? String
    right
  end
  def remove_previous
    old = @contents[@cursor[0]]
    prefix = @cursor[1] >= 2 ? old[0..@cursor[1]-2] : ""
    @contents[@cursor[0]] = prefix + old[@cursor[1]..old.size-1]
    left
  end
  def remove_next
    old = @contents[@cursor[0]]
    prefix = @cursor[1] >= 1 ? old[0..@cursor[1]-1] : ""
    @contents[@cursor[0]] = prefix + old[@cursor[1]+1..old.size-1]
  end
  def command c
    if c == "w"
      File.write @path, @contents.join("\n") + "\n"
      "written"
    else
      spl = c.match  /%s,(.+),(.+),g/
      if spl
        @contents.map! { |x| x.gsub(spl[1], spl[2]) }
        "done"
      else
        "#{c}: unknown command"
      end
    end
  end
  def new_line
    @contents.insert_line @cursor[0]
    @cursor[0] += 1
    @cursor[1] = 0
  end
  def up
    @cursor[0] -= 1
  end
  def down
    @cursor[0] += 1
  end
  def last_line
    @cursor[0] = @contents.size - 1
  end
  def first_line
    @cursor[0] = 0
  end
end

class Dimensions
  def [] x
    if x == 0
      Curses.lines
    else
      Curses.cols
    end
  end
end

class Editor
  def initialize paths
    @dimension = Dimensions.new
    @buffers = paths.map { |p| Buffer.new(p, @dimension) }
    @command = ""
    @result = ""
    @i = 0
  end
  def color fg, bg, str
    "\e[1;3#{fg};4#{bg}m#{str}\e[0m"
  end
  def mode_color
    {normal: 4, insert: 2, command: 1}[@mode] || 5
  end
  def status
    setpos(@dimension[0] - 1, 0)
    str = @mode.to_s.upcase + " "
    str += @buffers.each_with_index.map { |b, i| i == @i ? " #{b.status} " : b.status }.join("─") + " " 
    str += @command + " " + @result + " " * @dimension[1]
    printf color 0, mode_color, str[0...@dimension[1]]
  end
  def run_command c
    ntab = c.match  /tn (.+)/
    if ntab
      @buffers << Buffer.new(ntab[1], @dimension)
      @i = @buffers.size - 1
      "ok"
    else
      if c == "q"
        @buffers.delete_at @i
        exit if @buffers.size == 0
        @i = 0 if @i >= @buffers.size
        "ok"
      elsif c == "qa"
        exit
      end
    end
  end
  def insert
    @result = ""
    case @c
    when 9 # tab
      2.times { @buffer.insert " " }
    when 10 # enter
      @buffer.new_line
    when 27
      @mode = :normal
    when 127 #backspace
      @buffer.remove_previous
    else 
      @buffer.insert @c
      if @c == ','
        @c = Curses.getch
        if @c == ','
          @buffer.remove_previous
          @mode = :normal
        else
          insert
        end
      end
    end
  end
  def command
    if @c == 10
      if @mode == :command
        @result = run_command @command
        @result = @buffer.command @command if @result.nil?
      else
        @result = @buffer.search @command
      end
      @mode = :normal
      @command = ""
    elsif @c == 127 #backspace
      @command = @command[0..@command.size - 2]
    else
        @command += @c if @c.is_a? String
    end
  end
  def view
        @result = ""
        buffer_actions = {
          Curses::Key::UP => :up, Curses::Key::DOWN => :down, Curses::Key::LEFT => :left, Curses::Key::RIGHT => :right,
          'k' => :up, 'j' => :down, 'h' => :left, 'l' => :right,
          'g' => :first_line, 'G' => :last_line,
          '@c' => :left, 'r' => :right, 's' => :up, 't' => :down, 'u' => :undo, '$' => :last, '^' => :first, 'w' => :word,
          'b' => :bword, 'p' => :paste
        }
        if buffer_actions.keys.include? @c
          @buffer.send buffer_actions[@c]
        else
          case @c
          when ':'
            @mode = :command
            @command = ""
          when 'g'
            @i = (@i + 1) % @buffers.size
          when 'G'
            @i = (@i - 1) % @buffers.size
          when 'x'
            @buffer.remove_next
          when 'd'
            case Curses.getch
            when 'd'
              @buffer.delete
            end
          when 'i'
            @mode = :insert
          when 'o'
            @buffer.new_line
            @mode = :insert
          when 'O'
            @buffer.up
            @buffer.new_line
            @mode = :insert
          when '/'
            @mode = :search
          when '@c'
            @buffer.close
            @buffers.delete_at @i
          end
        end
  end
  def run
    Curses.noecho # do not show typed keys
    #Curses.init_screen
    #Curses.start_color
    Curses.stdscr.keypad(true) # enable arrow keys (required for pageup/down)
    @mode = :normal
    loop do
      @buffer = @buffers[@i]
      @buffer.show
      status
      @buffer.show_cursor
      @c = Curses.getch
      if @mode == :insert
        insert
      elsif @mode == :command
        command
      elsif @mode == :search
        command
      else
        view
      end
    end
  end
end

Editor.new(ARGV).run
