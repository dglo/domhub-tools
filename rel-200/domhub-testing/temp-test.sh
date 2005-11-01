#!/bin/bash

#
# temp-test.sh
#
# output: temperature in degrees C
# 
echo $1 `printf 'send "readTemp prtTemp\r"\nexpect "^> "\n' | \
    se $1 | grep '^temperature: ' | awk '{ print $2; }'`

