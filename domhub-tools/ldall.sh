#!/bin/bash

#
# ldall.sh, load all the doms with software after
# configboot and the cpld have been loaded...
# 
# FIXME: add -v options...
#
release=/home/dom/prod-REV5/release.hex
#release=/home/arthur/release.hex

#
# ignore stderr
#
source /usr/local/share/domhub-tools/common.sh
exec 2> /dev/null

if (( $# == 1 )); then
    release=$1
fi

if [[ ! -f ${release} ]]; then
    echo "`basename $0`: can not find ${release}, we will need that..."
    exit 1
fi

( off all && on all ) >& /dev/null

cdoms=`find /proc/driver/domhub/card* -name is-communicating -exec cat {} \; | \
   grep -v NOT | awk '{ print $2 $4 $6;}' | tr '\n' ' '`
echo "communicating doms: ${cdoms}"

function atexit() {
    rm -f /tmp/ldall.$$.*
}
trap atexit EXIT

#
# check for configboot...
#
rm -f /tmp/ldall.$$.pids && touch /tmp/ldall.$$.pids
for d in ${cdoms}; do
	se ${d} < /usr/local/share/domhub-tools/cb-version.exp > \
		/tmp/ldall.$$.${d}.out &
	printf '%d:%s\n' $! $d >> /tmp/ldall.$$.pids
done

pidlist=`awk -v FS=':' '{ print $1; }' /tmp/ldall.$$.pids | tr '\n' ' '`
( sleep 10; massacre ${pidlist} >& /dev/null) & watchdogpid=$!

pids=`cat /tmp/ldall.$$.pids`
rm -f /tmp/ldall.$$.pids

#
# collect info...
#
rm -f /tmp/ldall.$$.doms && touch /tmp/ldall.$$.doms
for p in ${pids}; do
	pid=`echo $p | awk -v FS=':' '{ print $1;}'`
	d=`echo $p | awk -v FS=':' '{ print $2;}'`
	if ! wait ${pid}; then
		echo "${d}: can not detect configboot, removed..."
	else
		if ! vstr=`grep '^configboot v2.7' /tmp/ldall.$$.${d}.out | \
				head -1`; then
			echo "${d}: no version string found, removed..."
		fi
		echo "${d}: ${vstr}" 
	
		#
		# mark this one as good...
		#
		echo "${d}" >> /tmp/ldall.$$.doms
	fi
	rm /tmp/ldall.$$.${d}.out
done

#
# done with watchdog...
#
kill -TERM ${watchdogpid} >& /dev/null
wait ${watchdogpid}

#
# install hex images...
#
doms=`cat /tmp/ldall.$$.doms`
rm -f /tmp/ldall.$$.doms
rm -f /tmp/ldall.$$.pids && touch /tmp/ldall.$$.pids
for d in ${doms}; do
	insrel ${release} ${d} >& /tmp/ldall.$$.${d}.out &
	printf '%d:%s\n' $! $d >> /tmp/ldall.$$.pids
done

pidlist=`awk -v FS=':' '{ print $1; }' /tmp/ldall.$$.pids | tr '\n' ' '`
( sleep 720; massacre ${pidlist} >& /dev/null ) & watchdogpid=$!

pids=`cat /tmp/ldall.$$.pids`
rm -f /tmp/ldall.$$.pids
rm -f /tmp/ldall.$$.doms && touch /tmp/ldall.$$.doms
for p in ${pids}; do
        pid=`echo $p | awk -v FS=':' '{ print $1;}'`
        d=`echo $p | awk -v FS=':' '{ print $2;}'`
	if ! wait ${pid}; then
		echo "${d}: can not install flash image, removed..."
                awk '{ print "FAIL> " $0; }' /tmp/ldall.$$.${d}.out
	elif ! vstr=`grep '^ Iceboot' /tmp/ldall.$$.${d}.out | sed 's/^ //1' `; then
		echo "${d}: can not find Iceboot release string, removed..."
	else
		echo "${d}: ${vstr}"
		echo ${d} >> /tmp/ldall.$$.doms
	fi
done

kill -TERM ${watchdogpid} >& /dev/null
wait ${watchdogpid}

#
# verify flash image...
#
doms=`cat /tmp/ldall.$$.doms`
rm -f /tmp/ldall.$$.doms
rm -f /tmp/ldall.$$.pids && touch /tmp/ldall.$$.pids
for d in ${doms}; do
	se $d < /usr/local/share/domhub-tools/ib-versions.exp > \
		/tmp/ldall.$$.${d}.out &
	printf '%d:%s\n' $! $d >> /tmp/ldall.$$.pids
done

pidlist=`awk -v FS=':' '{ print $1; }' /tmp/ldall.$$.pids | tr '\n' ' '`
( sleep 10; massacre ${pidlist} >& /dev/null ) & watchdogpid=$!

pids=`cat /tmp/ldall.$$.pids`
rm -f /tmp/ldall.$$.pids
for p in ${pids}; do
        pid=`echo $p | awk -v FS=':' '{ print $1;}'`
        d=`echo $p | awk -v FS=':' '{ print $2;}'`
	if  ! wait ${pid}; then
		echo "${d}: can not get iceboot versions"
	else
		#
		# get md5 sum
		#
		awk -v dom=${d} '$1 ~ /^md5sum$/ { print dom ": " $0; }' \
			/tmp/ldall.$$.${d}.out

		#
		# pld versions/build number
		#
		awk -v dom=${d} '$1 ~ /^version$/ \
			{ print dom ": pld version " $2 " " $3; }' \
			/tmp/ldall.$$.${d}.out
		grep '^build number' /tmp/ldall.$$.${d}.out | head -1 | \
			awk -v dom=${d} '{ print dom ": pld build # " $3; }'

		#
		# fpga build number
		#
		grep '^build number' /tmp/ldall.$$.${d}.out | sed -n '2p' | \
			awk -v dom=${d} '{ print dom ": fpga build # " $3; }'

		#
		# domid
		#
		awk -v dom=${d} '$1 ~ /^domid$/ { print dom ": " $0; }' \
			/tmp/ldall.$$.${d}.out
	fi
	rm -f /tmp/ldall.$$.${d}.out
done

/bin/kill -TERM ${watchdogpid} >& /dev/null
wait ${watchdogpid}

off all

