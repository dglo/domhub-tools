#!/bin/bash

#
# tcal.sh, analyze a time calibration file in
# kalle or john's format...
#

toolspath=/usr/local/share/domhub-tools
#toolspath=.

fn=`echo $* | sed 's/^.* //1'`
if head -1 ${fn} | \
    egrep '^DOM_[0-7][ab]_TCAL_round_trip_[0-9][0-9]*$' > /dev/null; then
    # kalle format
    exec ${toolspath}/tcal-kalle.sh $*
else
    # johnj format
    awk -f ${toolspath}/tcal-cvt.awk $1 > /tmp/tcal.sh.$$
    exec ${toolspath}/tcal-kalle.sh /tmp/tcal.sh.$$
fi




