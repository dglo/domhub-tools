#!/bin/bash

#
# mjb.sh, mexican jumping bean tests.  run a bunch of
# small tests on random doms.
#
# great name (mjb) is due to john jacobsen...
#
source /usr/local/share/domhub-tools/common.sh
#exec 2> /dev/null

# we need job control on...
#set -m

#
# cleanup...
#
rm -f /tmp/mjb.$$.*
longtermpid=0
function atexit() {
    if (( ${longtermpid} != 0 )); then
        kill ${longtermpid}
        longtermpid=0
    fi

    for pidf in `find /tmp -name 'mjb.$$.*.pid' -maxdepth 1 -print | \
	tr '\n' ' ' `; do
        pid=`cat ${pidf}`
	echo "killing ${pid}..."
        massacre ${pid}
        echo "waiting for ${pid}..."
        wait ${pid} 
    done
    rm -f /tmp/mjb.$$.*
}
trap "atexit" EXIT

function usage () { 
    local nm=`basename $0`
    echo "usage:" \
        "${nm} [-s seconds|-m minutes|-h hours|--no-throughput] (all|CWD...)"
    exit 1
}

#
# seconds is how long we run the tests...
#
nothroughput=0
let seconds=$(( 8 * 60 * 60 ))
while /bin/true; do
    if echo $1 | grep '^-' >> /dev/null; then
        if [[ $1 == "-s" && $2 != "" ]]; then
            shift
            seconds=$1
        elif [[ $1 == "-m" && $2 != "" ]]; then
            shift
            let seconds=$(( $1 * 60 ))
        elif [[ $1 == "-h" && $2 != "" ]]; then
            shift
            let seconds=$(( $1 * 60 * 60 ))
        elif [[ $1 == "--no-throughput" ]]; then
            nothroughput=1
        elif [[ $1 == "-h" ]]; then
            usage
            exit 0
        else
            usage
            exit 0
        fi 
   	shift 
    else
        break
    fi
done

if (( $# < 1 )); then usage; fi

doms=`getDomList $*`

if (( ${#doms} == 0 )); then
    echo "`basename $0`: no doms found"
    exit 1
fi

#
# move doms into iceboot and get version info
#
versions ${doms} > /tmp/mjb.$$.out
vdoms=`awk '{ print $1; }' /tmp/mjb.$$.out | tr '\n' ' '`

#
# make sure all doms are there...
#
tdoms=${doms}
for d in ${vdoms}; do
    tdoms=`echo ${tdoms} | sed "s/${d}//1" | sed 's/  / /1' | \
       sed 's/^ //1' | sed 's/ $//1'`
done

if (( ${#tdoms} != 0 )); then
   echo "`basename $0`: can not find version info for all doms"
   echo "  did not find: ${tdoms}"
   awk '{ print "    found> " $0; }' /tmp/mjb.$$.out
   exit 1
fi

#
# print version info...
#
gawk '{ print "versions " systime() " " $0; }' /tmp/mjb.$$.out

#
# start throughput tests...
#
if (( $nothroughput == 0 )); then
    echo-mode -q ${doms}
    ./throughput.sh ${doms} | \
        gawk '{ print "throughput-all " systime() " " $0; }'

    adoms=`echo ${doms} | tr ' ' '\n' | grep '..A' | tr '\n' ' ' | \
        sed 's/ $//1'`
    if (( ${#adoms} > 0 )); then
        ./throughput.sh ${adoms} | \
            gawk '{ print "throughput-A " systime() " " $0; }'
    fi

    bdoms=`echo ${doms} | tr ' ' '\n' | grep '..B' | tr '\n' ' ' | \
        sed 's/ $//1'`
    if (( ${#bdoms} > 0 )); then
        ./throughput.sh ${bdoms} | \
            gawk '{ print "throughput-B " systime() " " $0; }'
    fi
fi

exec ./mjb-sched ${seconds} ${doms}
