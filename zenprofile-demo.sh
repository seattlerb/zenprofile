#!/bin/bash

N=$1

if [ -z $N ]; then N=5000; fi
if [ -z $2 ]; then SKIP=no; else SKIP=yes; fi

rm -rf ~/.ruby_inline
sync; sync; sync

echo N=$N

if [ $SKIP = no ]; then
    echo
    echo ruby vanilla:
    time ruby misc/factorial.rb $N

    echo
    echo ruby profiler:
    time ruby -rprofile misc/factorial.rb $N 2>&1 | head -6
fi

echo
echo zenspider profiler:
export GEM_SKIP=RubyInline
time ./bin/zenprofile misc/factorial.rb $N 2>&1 | head -9

# shugo's version
# time ruby -I.:lib -runprof misc/factorial.rb $N 2>&1 | head
