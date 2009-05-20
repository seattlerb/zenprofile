#!/usr/local/bin/ruby -w

class Factorial
  def factorial(n)
    f = 1
    n.downto(2) { |x| f *= x }
    return f
  end
end

if ENV['SPY'] then
  require 'spy_on'

  Integer.spy_on :downto
end

if $0 == __FILE__ then
  f = Factorial.new()

  max = ARGV.shift || 1000000
  max = max.to_i

  tstart = Time.now

  (1..max).each { |m| n = f.factorial(5); }

  tend = Time.now

  total = tend - tstart
  avg = total / max
#  printf "Iter = #{max}, T = %.8f sec, %.8f sec / iter\n", total, avg
end
