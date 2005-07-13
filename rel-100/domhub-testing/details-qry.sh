#!/bin/bash

#
# details-qry.sh, get details on a test given:
#
#  testname timestamp dom 
#
# we return:
#
#   time test took
#   previous test
#   tests which ran on the other pair during this time
# 
if (( $# != 4 )); then
    echo "usage: `basename $0` dbfile testname timestamp dom"
    exit 1
fi

function atexit () {
    rm -f /tmp/dq.$$.*
}
trap atexit EXIT

#
# get neighbors first...
#
awk -vtime=$3 '{ if ($2>(time-1000) && $2<(time+1000)) print $0; }' $1 > \
    /tmp/dq.$$.out

#
# get start time... 
#
awk -vdom=$4 -vtime=$3 '{ if ( $3 == dom && $2 < time) print $0; }' \
    /tmp/dq.$$.out | tail -1 > /tmp/dq.$$.prev

starttime=`awk '{ print $2; }' /tmp/dq.$$.prev`
prevtest=`awk '{ print $1; }' /tmp/dq.$$.prev`

echo "previous> ${prevtest}"
let ttime=$(( $3 - ${starttime} ))
echo "runtime> ${ttime}"

#
# get tests on the other pair...
#
otherdom=`echo $4 | tr '[AB]' '[BA]'`

awk -vdom=${otherdom} '{ if ( $3 == dom ) print $1, $2; }' /tmp/dq.$$.out > \
     /tmp/dq.$$.others

awk '{ print $2; }' /tmp/dq.$$.others > /tmp/dq.$$.times

sed -n '1!p' /tmp/dq.$$.others | paste -d ' ' - /tmp/dq.$$.times | \
    awk '{ if (NF==3) print $1, $3, $2; }' > /tmp/dq.$$.setimes

cat <<EOF > /tmp/dq.$$.awk
{
   if ( \$3 > stime && \$2 < etime ) {
      if ( \$2 < stime ) st = stime;
      else st = \$2;
    
      if ( \$3 > etime ) et = etime;
      else et = \$3;
      
      print \$1, et - st; 
   }
}
EOF

awk -vstime=${starttime} -vetime=$3 -f /tmp/dq.$$.awk /tmp/dq.$$.setimes | \
    awk '{ print "other dom>", $0 }'

#
# now track down /var/log/messages for this time window...
#
# FIXME: too brute force, this should be smarter...
#
for (( tm=${starttime}; tm<=$3; tm++ )); do
    vlm=`awk -vtm=${tm} \
        'BEGIN { print strftime("%b %e %H:%M:%S", tm); }' /dev/null`
    grep "^${vlm}" /var/log/messages
done | awk '{ match($0, "^.*kernel:"); if (RLENGTH>0) print "log> " substr($0, RLENGTH+2); }'

