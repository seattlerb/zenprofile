= zenprofile

* http://rubyforge.org/projects/seattlerb

== DESCRIPTION:

zenprofiler helps answer WHAT is being called the most. spy_on helps
answer WHERE those calls are being made. ZenProfiler provides a faster
version of the standard library ruby profiler. It is otherwise pretty
much the same as before. spy_on provides a clean way to redefine a
bottleneck method so you can account for and aggregate all the calls
to it.

    % ruby -Ilib bin/zenprofile misc/factorial.rb 50000
    Total time = 3.056884
    Total time = 2.390000
    
              total     self              self    total
    % time  seconds  seconds    calls  ms/call  ms/call  name
     50.70     1.64     1.64    50000     0.03     0.05 Integer#downto
     19.63     2.27     0.63   200000     0.00     0.00 Fixnum#*
     14.19     2.73     0.46    50000     0.01     0.05 Factorial#factorial
      9.93     3.05     0.32        1   320.36  3047.10 Range#each
      5.54     3.23     0.18        2    89.40   178.79 ZenProfiler#start_hook

Once you know that Integer#downto takes 50% of the entire run, you
can use spy_on to find it. (See misc/factorial.rb for the actual code):

    % SPY=1 ruby -Ilib misc/factorial.rb 50000
    Spying on Integer#downto
    
    Integer.downto
    
    50000: total
    50000: ./misc/factorial.rb:6:in `factorial' via 
           ./misc/factorial.rb:6:in `factorial'

== FEATURES/PROBLEMS:

* 4x faster than stdlib ruby profiler by using event_hook to bypass set_trace_func
* 1/14th the amount of code of ruby-prof. Much easier to play with.

== SYNOPSIS:

    % zenprofile [ruby-flags] misc/factorial.rb

then:

    Array.spy_on :select, :each

run your code, then you'll see where the calls to Array#select and
#each are coming from.

== REQUIREMENTS:

* event_hook
* RubyInline
* Ruby 1.8

== INSTALL:

* sudo gem install zenprofile

== LICENSE:

(The MIT License)

Copyright (c) 2009 Ryan Davis, seattle.rb

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
