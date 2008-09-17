require 'rubygems'
require 'inline'
require 'singleton'

class ZenProfiler
  VERSION = '1.0.2'

  include Singleton

  @@start = @@stack = @@map = nil

  @@percent_time_threshold = 0.5

  def self.go
    at_exit {
      ZenProfiler::print_profile(STDOUT)
    }
    ZenProfiler::start_profile
  end

  def self.percent_time_threshold
    @@percent_time_threshold
  end

  def self.percent_time_threshold=(percent_time_threshold)
    @@percent_time_threshold = percent_time_threshold
  end

  def self.restart
    @@start = self.instance.time_now
    @@start2 = Process.times[0]
    @@stack = [[0, 0, [nil, :toplevel]], [0, 0, [nil, :dummy]]]
    @@map = {"#toplevel" => [1, 0.0, 0.0, [nil, "#toplevel"]]}
  end

  def self.start_profile
    self.restart unless @@start
    self.instance.add_event_hook
  end

  def self.stop_profile
    self.instance.remove_event_hook
  end

  def self.print_profile(f)
    stop_profile
    @@total = self.instance.time_now - @@start
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
          "#{klass.class}##{meth}"
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

  ############################################################
  # Inlined Methods:

  inline(:C) do |builder|

    builder.add_type_converter("rb_event_t", '', '')
    builder.add_type_converter("ID", '', '')
    builder.add_type_converter("NODE *", '', '')

    builder.include '<time.h>'
    builder.include '"node.h"'

    builder.prefix "
static VALUE profiler_klass = Qnil;
static VALUE stack = Qnil;
static VALUE map = Qnil;
"

    builder.c_raw <<-'EOF'
    VALUE time_now() {
      return rb_float_new(((double) clock() / CLOCKS_PER_SEC));
    }
    EOF

    builder.c_raw <<-'EOF'
    static void
    prof_event_hook(rb_event_t event, NODE *node,
                    VALUE recv, ID mid, VALUE klass) {

      static int profiling = 0;
      VALUE now;

      if (mid == ID_ALLOCATOR) return;
      if (profiling) return;
      profiling++;

      now = time_now();

      if (NIL_P(profiler_klass))
        profiler_klass = rb_path2class("ZenProfiler");
      if (NIL_P(stack))
        stack = rb_cv_get(profiler_klass, "@@stack");
      if (NIL_P(map))
        map   = rb_cv_get(profiler_klass, "@@map");

      switch (event) {
      case RUBY_EVENT_CALL:
      case RUBY_EVENT_C_CALL:
        {
          VALUE signature, time;
          signature = rb_ary_new2(2);

          if (TYPE(klass) == T_ICLASS) {
            klass = RBASIC(klass)->klass;
          } else if (FL_TEST(klass, FL_SINGLETON)) {
            klass = recv;
          }

          rb_ary_store(signature, 0, klass);
          rb_ary_store(signature, 1, ID2SYM(mid));
          time = rb_ary_new2(3);
          rb_ary_store(time, 0, now);
          rb_ary_store(time, 1, rb_float_new(0.0));
          rb_ary_store(time, 2, signature);
          rb_ary_push(stack, time);
        }
        break;
      case RUBY_EVENT_RETURN:
      case RUBY_EVENT_C_RETURN:
        {
        VALUE tick;
        VALUE signature;
        VALUE data = Qnil;
        VALUE toplevel;
        double cost;

        tick = rb_ary_pop(stack);
        if (!RTEST(tick)) break;
        signature = rb_ary_entry(tick, -1);

        st_lookup(RHASH(map)->tbl, signature, &data);
        if (NIL_P(data)) {
          data = rb_ary_new2(4);
          rb_ary_store(data, 0, INT2FIX(0));
          rb_ary_store(data, 1, rb_float_new(0.0));
          rb_ary_store(data, 2, rb_float_new(0.0));
          rb_ary_store(data, 3, signature);
          rb_hash_aset(map, signature, data);
        }

        rb_ary_store(data, 0, ULONG2NUM(NUM2ULONG(rb_ary_entry(data, 0)) + 1));

        cost = (NUM2DBL(now) - NUM2DBL(rb_ary_entry(tick, 0)));

        rb_ary_store(data, 1, rb_float_new(NUM2DBL(rb_ary_entry(data, 1))
                                           + cost));

        // data[2] += cost - tick[1]
        rb_ary_store(data, 2, rb_float_new(NUM2DBL(rb_ary_entry(data, 2))
                                           + cost
                                           - NUM2DBL(rb_ary_entry(tick, 1))));
 
        toplevel = rb_ary_entry(stack, -1);
        if (RTEST(toplevel)) {
          VALUE tl_stats = rb_ary_entry(toplevel, 1);
          rb_ary_store(toplevel, 1, rb_float_new(NUM2DBL(tl_stats) + cost));
        }
        }
        break;
      }
      profiling--;
    }
    EOF

    builder.c <<-'EOF'
      void add_event_hook() {
        rb_add_event_hook(prof_event_hook,
                          RUBY_EVENT_CALL | RUBY_EVENT_RETURN |
                          RUBY_EVENT_C_CALL | RUBY_EVENT_C_RETURN);
      }
    EOF

    builder.c <<-'EOF'
      void remove_event_hook() {
        rb_remove_event_hook(prof_event_hook);
      }
    EOF
  end
end

