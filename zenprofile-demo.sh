#!/bin/bash

N=$1

if [ -z $N ]; then N=100_000; fi
if [ -z $2 ]; then SKIP=no; else SKIP=yes; fi

rm -rf ~/.ruby_inline
sync; sync; sync

echo N=$N

if [ $SKIP = no ]; then
    echo
    echo ruby vanilla :
    X=1 time ruby misc/factorial.rb $N

    echo
    echo ruby profiler:
    X=1 time ruby -rprofile misc/factorial.rb $N 2>&1 | egrep -v "^ *0.00"
fi

echo
echo zen profiler :
export GEM_SKIP=RubyInline
X=1 time ./bin/zenprofile misc/factorial.rb $N 2>&1 | egrep -v "^ *0.00"

echo
echo zen profiler pure ruby:
export GEM_SKIP=RubyInline
PURERUBY=1 time ./bin/zenprofile misc/factorial.rb $N 2>&1 | egrep -v "^ *0.00"

# shugo's version
# time ruby -I.:lib -runprof misc/factorial.rb $N 2>&1 | head
