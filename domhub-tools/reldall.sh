#!/bin/bash

source /usr/local/share/domhub-tools/common.sh
exec 2> /dev/null
#
# reldall.sh, reload release.hex image to doms
#
if (( $# != 1 )); then
    echo "usage: `basename $0` release.hex[.gz]"
    exit 1
fi

#
# first gzip archive if it is not one already...
#
if ! gzip -t $1 >& /dev/null; then
    dorm=1
    fname=`mktemp /tmp/reldall-gz-XXXXXXXX`
    if ! gzip -c $1 > $fname ; then
	echo "`basename $0`: unable to gzip $1"
	rm -f ${fname}
	exit 1
    fi
else
    dorm=0
    fname=$1
fi

function atexit() {
    # rm created .gz release.hex file?
    if (( ${dorm} == 1 )); then rm -f ${fname}; fi

    # rm ttf files
    if [[ -f ${ttf} ]]; then
        for dom in `cat ${ttf}`; do
	    rm -f `awk -vFS=':' '{ print $1; }' ${ttf}`
        done
        rm -f ${ttf}
    fi
}

trap atexit EXIT

#
# get list of doms...
#
doms=`iceboot all | awk '$3 ~ /^iceboot$/ { print $1; }'`

if (( ${#doms} == 0 )); then
    echo "`basename $0`: unable to find any doms in iceboot"
    exit 1
fi

release=${fname}

ttf=`mktemp /tmp/reldall-domlist-XXXXXX`
n=0
for dom in ${doms}; do
    tf=`mktemp /tmp/reldall-${dom}-results-XXXXXXXX`
    reldcwd ${release} ${dom} >& ${tf} &
    echo "${tf}:${dom}:$!"
    let n=$(( $n + 1 ))
done > ${ttf}

echo "started reldcwd on $n doms..."

pidlist=`awk -vFS=':' '{ print $3; }' ${ttf} | tr '\n' ' ' | sed 's/ $//1'`

wait-till-dead 720000 $pidlist

for dom in `cat ${ttf}`; do
    pid=`echo $dom | awk -vFS=':' '{ print $3; }'`
    if ! wait ${pid};  then
        fn=`echo $dom | awk -vFS=':' '{ print $1; }'`
        d=`echo $dom | awk -vFS=':' '{ print $2; }'`
        h=`hostname -s`
        awk -vd=$d -vh=$h '{ print h, d, "FAIL> " $0; }' ${fn}
    fi
done
