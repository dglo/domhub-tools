#!/bin/bash

#
# slow-open-test.sh how long does it take to
# do an open of the comm driver file...
#
# output: [1st open time] [avg open time (100 in a row)]
# 
exec ./open-test $1

