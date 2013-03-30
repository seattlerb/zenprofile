require 'rubygems'
require 'inline'
require 'singleton'
$: << '../../event_hook/dev/lib' # TODO: remove
require 'event_hook'

##
# ZenProfiler provides a faster version of the standard library ruby
# profiler. It is otherwise pretty much the same as before.
#
# Invoke it via:
#
#    % zenprofile misc/factorial.rb
#
# or:
#
#    % ruby -rzenprofile misc/factorial.rb

class ZenProfiler < EventHook
  VERSION = "1.3.2" # :nodoc:

  @@start                  = nil
  @@stack                  = [[0, 0, [nil, :toplevel]], [0, 0, [nil, :dummy]]]
  @@map                    = Hash.new { |h,k| h[k] = [0, 0.0, 0.0, k] }
  @@map["#toplevel"]       = [1, 0.0, 0.0, [nil, "#toplevel"]]
  @@percent_time_threshold = 0.5

  ##
  # Start the profiler hook and run a report at_exit. Prints to +fp+
  # (defaulting to $stdout) and takes +opts+.

  def self.run(fp = $stdout, opts = {})
    at_exit {
      ZenProfiler::print_profile fp, opts
    }
    ZenProfiler::start_hook
  end

  ##
  # Turn on the profiler.

  def self.start_hook
    @@start  ||= Time.now.to_f
    @@start2 ||= Process.times[0]
    super
  end

  ##
  # Return the cut-off for reported %-time.

  def self.percent_time_threshold
    @@percent_time_threshold
  end

  ##
  # Set the cut-off for reported %-time.

  def self.percent_time_threshold=(percent_time_threshold)
    @@percent_time_threshold = percent_time_threshold
  end

  ##
  # Print a report to +f+.

  def self.print_profile(f, opts = {})
    stop_hook

    @@total = Time.now.to_f - @@start
    @@total = 0.01 if @@total == 0
    @@total2 = Process.times[0] - @@start2
    @@map["#toplevel"][1] = @@total
    data = @@map.values.sort_by { |vals| -vals[2] }
    sum = 0

    f.puts "Total time = %f" % @@total
    f.puts "Total time = %f" % @@total2
    f.puts
    f.puts "          total     self              self    total"
    f.puts "% time  seconds  seconds    calls  ms/call  ms/call  name"

    @@total = data.inject(0) { |acc, (_, _, self_ms, _)| acc + self_ms }

    data.each do |calls, total_ms, self_ms, name|
      percent_time = self_ms / @@total * 100.0

      next if percent_time < @@percent_time_threshold

      sum += self_ms
      klass = name.first
      meth  = name.last.to_s

      signature =
        if klass.nil?
          meth
        elsif klass.kind_of?(Module)
          klassname = klass.name rescue klass.to_s.sub(/#<\S+:(\S+)>/, '\\1')
          "#{klassname}##{meth}"
        else
          "#{klass}##{meth}"
        end

      f.printf "%6.2f ",  percent_time
      f.printf "%8.2f ", sum
      f.printf "%8.2f ",  self_ms
      f.printf "%8d ",    calls
      f.printf "%8.2f ",  (self_ms * 1000.0 / calls)
      f.printf "%8.2f ",  (total_ms * 1000.0 / calls)
      f.printf "%s",      signature
      f.puts
    end
  end

  if ENV['PURERUBY'] then

    ##
    # Process an +event+ for +obj+ on +klass+ and +method+.

    def self.process event, obj, method, klass
      case event
      when CALL, CCALL
        now = Process.times[0]
        @@stack.push [now, 0.0]
      when RETURN, CRETURN
        klass = klass.name rescue return
        key = [klass, method]
        if tick = @@stack.pop
          now = Process.times[0]
          data = @@map[key]
          data[0] += 1
          cost = now - tick[0]
          data[1] += cost
          data[2] += cost - tick[1]
          @@stack[-1][1] += cost if @@stack[-1]
        end
      end
    end
  else
    inline(:C) do |builder|
      builder.add_type_converter("rb_event_t", '', '')
      builder.add_type_converter("ID", '', '')
      builder.add_type_converter("NODE *", '', '')

      builder.include '<time.h>'
      builder.include '"node.h"'

      builder.add_static 'profiler_klass',  'rb_path2class("ZenProfiler")'
      builder.add_static 'eventhook_klass', 'rb_path2class("EventHook")'
      builder.add_static 'stack',           'rb_cv_get(profiler_klass, "@@stack")'
      builder.add_static 'map',             'rb_cv_get(profiler_klass, "@@map")'

      builder.add_static 'id_allocate', 'rb_intern("allocate")'

      builder.prefix "
        #define id_call    INT2FIX(RUBY_EVENT_CALL)
        #define id_ccall   INT2FIX(RUBY_EVENT_C_CALL)
        #define id_return  INT2FIX(RUBY_EVENT_RETURN)
        #define id_creturn INT2FIX(RUBY_EVENT_C_RETURN)
      "

      builder.prefix <<-'EOF'
        VALUE time_now() {
          return rb_float_new(((double) clock() / CLOCKS_PER_SEC));
        }
      EOF

      builder.c_singleton <<-'EOF'
      static void
      process(VALUE event, VALUE recv, VALUE method, VALUE klass) {
        static int profiling = 0;

        if (method == id_allocate) return Qnil;
        if (profiling) return Qnil;
        profiling++;

        VALUE now = time_now();

        switch (event) {
        case id_call:
        case id_ccall:
          {
            VALUE time = rb_ary_new2(2);
            rb_ary_store(time, 0, now);
            rb_ary_store(time, 1, rb_float_new(0.0));
            rb_ary_push(stack, time);
          }
          break;
        case id_return:
        case id_creturn:
          {
            if (TYPE(klass) == T_ICLASS) {
              klass = RBASIC(klass)->klass;
            } else if (FL_TEST(klass, FL_SINGLETON)) {
              klass = recv;
            }

            VALUE key = rb_ary_new2(2);
            rb_ary_store(key, 0, klass);
            rb_ary_store(key, 1, method);

            VALUE tick = rb_ary_pop(stack);
            if (!RTEST(tick)) break;

            VALUE data = rb_hash_aref(map, key);

            rb_ary_store(data, 0, rb_ary_entry(data, 0) + 2); // omg I suck

            double cost = NUM2DBL(now) - NUM2DBL(rb_ary_entry(tick, 0));

            rb_ary_store(data, 1, rb_float_new(NUM2DBL(rb_ary_entry(data, 1))
                                               + cost));

            rb_ary_store(data, 2, rb_float_new(NUM2DBL(rb_ary_entry(data, 2))
                                               + cost
                                               - NUM2DBL(rb_ary_entry(tick, 1))));

            VALUE toplevel = rb_ary_entry(stack, -1);
            if (RTEST(toplevel)) {
              VALUE tl_stats = rb_ary_entry(toplevel, 1);
              rb_ary_store(toplevel, 1, rb_float_new(NUM2DBL(tl_stats) + cost));
            }
          }
          break;
        } // switch (event)
        profiling--;
      }
      EOF
    end
  end
end

class << ENV # :nodoc:
  def class # :nodoc:
    Class
  end

  def name # :nodoc:
    "ENV"
  end
end

class << self
  def name # :nodoc:
    "::main"
  end
end
