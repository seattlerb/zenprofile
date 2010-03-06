$: << '../../ZenTest/dev/lib'

require 'zentest_mapping'

##
# require 'test/spy_on'
#
# class Array
#   spy_on :select, :each
# end
#
# class Hash
#   spy_on :key?
#   # spy_on :[]
# end

class Hash
  alias_method :safe_idx, :[]
  alias_method :safe_asgn, :[]=
end

class Module
  include ZenTestMapping

  def call_site(depth=1)
    paths = caller(2).map { |path| path =~ /\(eval\)/ ? path : File.expand_path(path).sub(/#{File.expand_path Dir.pwd}/, '.') }
    our = paths.reject { |path| path =~ /vendor.rails|rubygems/ }
    return ["#{our.first} via "] + paths.first(depth)
  end

  def print_tally(tallies)
    tallies.sort.each do |msg, tally|
      puts
      puts msg
      puts
      total = 0
      tally.values.each do |n| total += n; end
      puts "%5d: %s" % [total, "total"]

      tally.sort_by { |caller, count| -count }.first(5).each do |caller, count|
        puts "%5d: %s" % [count, caller.join("\n       ")]
      end
    end
  end

  def spy msg, old_msg = nil, depth = 1
    puts "Spying on #{self}##{msg}"
    old_msg ||= "old_#{normal_to_test(msg.to_s).sub(/^test_/, '')}"
    alias_method old_msg, msg

    class_eval "
      @@tally_done = false
      @@tally ||= Hash.new { |h,k| h.safe_asgn(k, Hash.new(0)) }
      at_exit { at_exit { @@tally_done = true; print_tally @@tally if @@tally; @@tally = nil } }
      def #{msg}(*args, &block)
        unless @@tally_done then
          site = self.class.call_site(#{depth})
          x = @@tally.safe_idx('#{self}.#{msg}')
          x.safe_asgn(site, x.safe_idx(site) + 1)
        end
        self.#{old_msg}(*args, &block)
      end "
  end

  def spy_cm *args
    this_sucks.spy *args
  end

  def spy_on *msgs
    msgs.each do |msg|
      spy msg
    end
  end

  def spy_on_cm *msgs
    this_sucks.spy_on *msgs
  end

  def this_sucks
    class << self; self; end
  end
end
