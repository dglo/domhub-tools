#!/bin/bash

#
# quiet-results.sh, easy one, are they all zero?
#
awk '{ print $4; }' $1 | grep -v '^0$' >& /dev/null

if (( $? == 0 )); then
    echo "all values should be zero and we got:"
    awk '{ print $4}' $1 | sort | uniq | grep -v '^0$'
    exit 1
else
    exit 0
fi

