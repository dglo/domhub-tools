#!/bin/bash

#
# validate.sh, attempt to validate dor/dom firmware and
# software...
#
source /usr/local/share/domhub-tools/common.sh
exec 2> /dev/null

# we need job control on...
set -m
RANDOM=0

#
# cleanup...
#
rm -f /tmp/val.$$.*
longtermpid=0
function atexit() {
    if (( ${longtermpid} != 0 )); then
        kill ${longtermpid}
        longtermpid=0
    fi

    for pidf in `find /tmp -name 'val.$$.*.pid' -print | tr '\n' ' ' `; do
        pid=`cat ${pidf}`
	echo "killing ${pid}..."
        massacre ${pid}
        echo "waiting for ${pid}..."
        wait ${pid} 
    done
    rm -f /tmp/val.$$.*
}
trap "atexit" EXIT

function usage () { 
    echo "usage: `basename $0` release.hex"
    exit 1
}

if (( $# != 1 )); then usage; fi

if [[ ! -f $1 ]]; then
   echo "`basename $0`: unable to find release file $1"
   exit 1
fi

release=$1

#
# first make sure we can burn a release...
#
echo "installing release ${release}" >> validate.log
if ! insall ${release} >& /tmp/val.$$.insall; then
    echo "validate.sh: unable to install release.hex on all doms, log file:"
    cat /tmp/val.$$.insall
    rm -f /tmp/val.$$.insall
    exit 1
fi

rm -f /tmp/val.$$.insall

#
# move doms into iceboot and get version info
#
echo "getting versions" >> validate.log
versions ${doms} > /tmp/val.$$.out
vdoms=`awk '{ print $1; }' /tmp/val.$$.out | tr '\n' ' '`

if (( ${#doms} != ${#vdoms} )); then
   echo "`basename $0`: can not find version info for all doms"
   awk '{ print "    found> " $0; }' /tmp/val.$$.out
   exit 1
fi

#
# FIXME: run long echo/tcal test...
#

#
# run mjb test...
#
echo "mjb test starts..." >> validate.log
if ! ./mjb.sh -s 599 all; then
    echo "`basename $0`: unable to run mjb"
    exit 1
fi

echo "done" >> validate.log

