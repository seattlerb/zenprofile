
class MemoryProfiler

  # profile is a CLEAN, totally minimal memory profiler:
  #
  # * 1 thread
  # * 2 hashes (curr, prev)
  # * classes as keys
  # * fixnums as values.
  # 
  # No extra memory required if I can help it. Keep it as simple as
  # possible. The code at the link above is WAY to complex for such a
  # simple task.  It does use a sort_by, so that produces a bit extra
  # junk... but that shouldn't be more than an extra array and hash
  # per iteration.
  # 
  # Just fire it up as MemoryProfiler.profile or use it with a block
  # of code:
  # 
  #   MemoryProfiler.profile do
  #     # ...
  #   end

  def self.profile(delay = 2, limit=10, output=$stderr)
    Thread.abort_on_exception = true
    totals = Hash.new(0)
    t = Thread.new do
      prev = Hash.new(0)
      curr = Hash.new(0)
      loop do
        curr.clear
        ObjectSpace.each_object do |o|
          curr[o.class] += 1
        end

        curr.each do |k,v|
          curr[k] -= prev[k]
        end

        puts
        curr.sort_by { |k,v| -v }.first(limit).each do |k,v|
          output.printf "%+5d: %s\n", v, k.name unless v == 0
        end

        prev.clear
        prev.update curr
        curr.each do |k,n| totals[k] += n end
        sleep delay
      end
    end
    if block_given? then
      yield
      t.exit
    end
    totals
  end

  @@locations = {}
  @@allocations = Hash.new { |h,k| h[k] = Hash.new(0) }

  def self.log(o)
    loc = caller[1]
    unless @@locations.has_key? loc then
      @@locations[loc] = @@locations.size
    end
    loc = @@locations[loc]
    @@allocations[o.class][loc] += 1
  end

  def self.spy_on *klasses
    klasses.each do |klass|
      hook klass, :initialize
      if klass == String then
        hook klass, :%
        hook klass, :strip
      end
    end
  end

  def self.hook klass, meth
    klass.module_eval do
      old = meth.to_s.sub(/%/, 'pct').sub(/^/, 'old_')
      alias_method old, meth
      eval "def #{meth}(*args, &block)
        MemoryProfiler.log(self)
        #{old}(*args, &block)
      end"
    end
  end

  def self.report
    keys = @@locations.invert

    puts
    puts "############################################################"
    puts "Spy Report:"

    @@allocations.each do |klass, locations|
      puts
      puts klass
      puts
      locations.sort_by { |k,v| -v }.first(10).each do |location, count|
        printf "%6d: %s\n", count, keys[location]
      end
    end
    p @@locations, @@allocations, keys if $DEBUG
  end
end
