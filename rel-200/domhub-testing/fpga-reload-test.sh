#!/bin/bash

#
# fpga-reload-test.sh
#
# output: iterations errors
# 
errs=0
for (( i=0; i<50; i++ )); do
    printf 'send "s\\" iceboot.sbi\\" find if fpga endif\r"\nexpect "^> "\n' | \
        se $1 >& /dev/null
    status=$?
    if (( ${status} != 0 )); then
       let errs=$(( ${errs} + 1 ))
    fi
    
    # reserve about 1/2 bandwidth for others...
    sleep 1
done

echo $1 $i $errs
