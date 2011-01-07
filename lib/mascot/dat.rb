module Mascot
  # A parser for Mascot flat file results. 
  # 
  # <b> NOTE:</b> This parser creates another file 
  # that indexes the byte position offsets of the various mime sections of 
  # a DAT file. For some reason, DAT files indexes are the line numbers 
  # within the file, making random access more difficult than it 
  # needs to be. 
  # 
  # <b>If you do not want this index file created, you need to pass in 
  #   <code> false</code> to the <code>cache_index</code> argument
  class Dat < File
    require "uri"
    attr_accessor :idx
    attr_accessor :boundary

    def initialize fn, cache_index=true
      super(fn)
      @idx = {}
      @boundary = nil
      @cache_index = cache_index
      parse_index
    end
    
    # Read in the query spectrum from the DAT file
    # 
    # @param n  The query spectrum numerical index
    # @return   Hash of the spectrum. The hash has    
    def query(n)
      # search index for this 
      bytepos = @idx["query#{n}".to_sym]
      pos= bytepos
      att_rx = /(\w+)\=(.+)/
      q = {}
      each do |l|
        l.chomp
        case l
        when att_rx
          k,v = $1,$2          
          case k
          when "title"
            q[k.to_sym] = URI.decode(v)
            # when "Ions1"
            #   q[k.to_sym] = v.split(",").collect {|e| e.split(":").collect {|ee| ee.to_f}}
          else
            q[k.to_sym] = v
          end
        when @boundary
          break
        else 
          next
        end
      end
      return q
    end
    alias_method :spectrum, :query
    
    # Go to a section of the Mascot DAT file
    def goto(key)
      if @idx.has_key?(key.to_sym)
        self.pos = @idx[key.to_sym]
      else
        raise Excpetion.new "Invalid index key \"#{key}\""
      end
    end
    
    # define methods for positioning cursor at the DAT file MIME sections
    [:summary, :parameters, :peptides, :proteins,
      :header, :enzyme, :taxonomy, :unimod, :quantitation,
      :masses, :mixture, :index].each do |m|
      define_method m do
        self.goto(m)
      end
    end

    # read a section of the DAT file into memory.
    # THIS IS NOT RECOMMENDED UNLESS YOU KNOW WHAT YOU ARE DOING
    def read_section(key)
      self.goto(key)
      section = ''
      self.each do |l|
        break if l =~ @boundary
        section << l.chomp
      end
      section
    end

    private
    def parse_index
      idxfn = path + ".idx"
      if File.exists?( idxfn)
        idxf = File.open(idxfn)
        @idx = Marshall::load(idxf.read)
        @boundary = @idx[:boundary]
        idxf.close
      else
        create_index()
      end
    end

    def create_index
      # grep the boundary positions of the file
      positions = []
      self.rewind()
      # MIME header line, to parse out boundary
      self.readline
      self.readline =~/boundary=(\w+)$/
      boundary_string = "--#{$1}"
      boundary_length = boundary_string.length
      @boundary = Regexp.new("--#{$1}")
      @idx[:boundary] = @boundary
      
      self.grep(@boundary) do |l|
        self.readline =~ /name="(.+)"/
        @idx[$1.to_sym] = self.pos - boundary_length
      end      
      if @cache_index
        idxfile = File.open(path + ".idx", 'w')
        # mime header line
        # output & set @boundary
        idx.puts("boundary=#{boundary_string}")
        # open the file and get the positions to read the indexed name
        idxfile.write(Marshall.dump(@idx))
        idxfile.close()
      end
      self.rewind
    end

  end
end
