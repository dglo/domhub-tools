#!/bin/bash

# source common tools
source /usr/local/share/domhub-tools/common.sh

# cold-ramp.sh, run cold ramp stf-tests
startmjb=1320
#startmjb=300
starttemp=65

loopmjb=120
temps="65 -50 -40 -30 -20 -10 -20 -30 -40 -50"

endtemp=25

#
# run all tests...
#
# $1 is the target temperature...
#
function runAllTests() {
    local temp=$1

    echo "running stf-client..."
    ( cd ~dom/prod-REV5; ./stf-client std-tests false 1 ${temp} )
    
    echo "running tcal-stf..."
    off all && on all
    ( cd ~dom/prod-REV5; ./tcal-stf.sh all ${temp} )

   echo "running mjb..."
   ( cd /usr/local/share/domhub-testing; ./mjb.sh -m $2 all ) > /tmp/mjb-cold-ramp.out

    echo "checking results..."
    ( cd /usr/local/share/domhub-testing; ./results-qry.sh /tmp/mjb-cold-ramp.out all)

#    echo "running ldall..."
#    ( ldall ~dom/prod-REV5/release.hex )
}

#
#  run all the tests, but check to make sure that:
#
# 1) the time limit is reached (if tests end prematurely...)
# 2) the time limit is not exceeded (if tests get stuck...)
#
# $1 is the time (in minutes) to run the tests...
#
function runAllTestsCheck() {
    local sleepsecs=`echo $1 60 * p | dc`
    # mjb minutes=total minutes - stf minutes - tcal-stf minutes - overhead
    local mjbminutes=`echo "$1 30 - 10 - 10 - 10 - p" | dc`

    runAllTests $mjbminutes &
    local testpid=$!

    sleep ${sleepsecs} &
    local wdpid=$!

    # make sure we wait at least timeout period...
    wait ${wdpid}

    # kill testpid if it is still running...
    massacre ${testpid}
}

function getTemperature() {
   local temp=`echo "? C1" | ./w942`

   # round it...
   local ttt=`echo "${temp} 10 * p" | dc | sed 's/\..*$//1'`
   local last2d=`echo ${ttt} | awk '{ print substr($0, length($0)-1, 2); }'`
   local val=0
   if (( `echo ${last2d} | sed 's/^[0-9]//1'` >= 5 )); then
      val=10
   fi
   echo "${ttt} ${val} + p" | dc | sed 's/[0-9]$//1'
}

#
# set temperature -- wait for it to be reached...
#
function setTemperature() {
    local temp=$1

    echo "setting temperature to: $temp"
    if ! echo "= SP1 ${temp}" | ./w942; then
        echo "`basename $0`: unable to set temperature"
        return 1
    fi
    
    # wait for set temperature...
    echo "waiting for temperature to reach $temp"
    while /bin/true; do
        local current=`getTemperature`

        printf "current temperature: ${current}      \r"
        if (( current == ${temp} )); then
            break
        fi
        sleep 1
    done
    printf "\n"

    # wait 5 minutes...
    awk 'BEGIN { print "waiting 5 minutes, ready at " strftime("%r", systime() + 300) " ..."; }'
    sleep 300
}
 
#
# start burn-in
#
if ! setTemperature ${starttemp}; then
    echo "`basename $0`: unable to set temperature to ${starttemp}"
    exit 1
fi

# run all tests...
runAllTests ${starttemp} ${startmjb}

for temp in ${temps}; do
    # set temperature...
    if ! setTemperature ${temp}; then
	echo "`basename $0`: unable to set temperature"
	exit 1
    fi

    runAllTests ${temp} ${loopmjb}

    # turn off doms
    echo "turning off doms..."
    off all
done

# back up to room temperature...
setTemperature ${endtemp}

