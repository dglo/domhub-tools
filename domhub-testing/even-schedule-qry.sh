#!/bin/bash

#
# even-schedule-qry.sh, do the doms appear to
# get evenly scheduled?
#
function atexit () {
    rm /tmp/esq.$$.out
}
trap atexit EXIT

if (( $# != 1 )); then
  echo "usage: `basename $0` dbfile"
  exit 1
fi

awk '{ print $3; }' $1 > /tmp/esq.$$.out

doms=`sort /tmp/esq.$$.out | uniq | tr '\n' ' '`
echo "doms=${doms}"
for d in ${doms}; do
    echo ${d} `grep "^${d}$" /tmp/esq.$$.out | wc -l | awk '{ print $1; }'`
done

