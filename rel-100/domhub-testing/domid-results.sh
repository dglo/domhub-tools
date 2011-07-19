#!/bin/bash

#
# domid-results.sh, get results of domid test from db
#
verbose=1

if (( $# != 1 )); then
    echo "usage: `basename $0` dbfile"
    exit 1
fi

#
# make sure domids match...
#
if ! awk '{ if ( $4 == "" || $4 != $5 ) { print $0; exit 1; } }' $1; then
    exit 1
fi

exit 0
