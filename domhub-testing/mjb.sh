#!/bin/bash

#
# mjb.sh, mexican jumping bean tests.  run a bunch of
# small tests on random doms.
#
# great name (mjb) is due to john jacobsen...
#
source /usr/local/share/domhub-tools/common.sh
exec 2> /dev/null

# we need job control on...
set -m
RANDOM=0

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

    for pidf in `find /tmp -name 'mjb.$$.*.pid' -print | tr '\n' ' ' `; do
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

#
# start watchdog...
#
( sleep ${seconds}; ) >& /dev/null & longtermpid=$!

#
# process data file which has just finished...
#
function process () {
    dom=$1
    local pid=`cat /tmp/mjb.$$.${dom}.pid`
    local testnm=`cat /tmp/mjb.$$.${dom}.test`
    wait ${pid}
    local ts=$?
    local line="${testnm} `date '+%s'`"

    if (( ${ts} == 100 )); then
        # duplicate test ignore...
        echo "hi" > /dev/null
    elif (( ${ts} == 101 )); then
        # timeout
        echo "${line} ${dom} ERROR: TIMEOUT"
    elif (( ${ts} == 102 )); then
        # test not found
        echo "${line} ${dom} ERROR: TEST NOT FOUND"
    elif (( ${ts} == 103 )); then
        # usage error
        echo "${line} ${dom} ERROR: USAGE"
    elif (( ${ts} > 0 )); then
        echo "${line} ${dom} ERROR: failed (${ts}):" \
`cat /tmp/mjb.$$.${dom}.out`
    else
        echo ${line} `cat /tmp/mjb.$$.${dom}.out`
    fi
}

#
# pick a random test -- tests.txt has the list to pick from...
#
function getTestName () {
    ntests=`wc -l tests.txt | awk '{print $1; }'`
    let testnum=$(( ( RANDOM % ${ntests} ) + 1 ))
    sed -n "${testnum}p" tests.txt | awk '{ print $1; }' | tr -d '\n'
}

#
# callback when a test is finished...
#
# here we do all the work for short term tests...
#
# tabulate results, reschedule...
#
function schedule () {
    local doms=$*

    for dom in ${doms}; do
	if [[ -f /tmp/mjb.$$.${dom}.done ]]; then
  	    rm -f /tmp/mjb.$$.${dom}.done

	    if [[ -f /tmp/mjb.$$.${dom}.pid ]]; then
                process ${dom}
            fi
            # clean up...
            rm -f /tmp/mjb.$$.${dom}.*

            # schedule next test...
	    testnm=`getTestName`

            # FIXME: two doms on the pair...
	    echo ${testnm} > /tmp/mjb.$$.${dom}.test
            ./run-test.sh ${testnm} ${dom} /tmp/mjb.$$.${dom}.done > \
                /tmp/mjb.$$.${dom}.out &
            echo $! > /tmp/mjb.$$.${dom}.pid
        fi
     done
}

#
# start tests...
#
trap "schedule ${doms}" CHLD
for dom in ${doms}; do touch /tmp/mjb.$$.${dom}.done; done
schedule ${doms}

#
# wait for long term tests to finish...
#
wait ${longtermpid}
longtermpid=0
trap - CHLD

for dom in ${doms}; do 
    if [[ -f /tmp/mjb.$$.${dom}.pid ]]; then
        wait `cat /tmp/mjb.$$.${dom}.pid`
        process ${dom}
        rm -f /tmp/mjb.$$.${dom}.*
    fi
done

