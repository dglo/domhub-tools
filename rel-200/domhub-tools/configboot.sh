#!/bin/bash

#
# configboot.sh, move all doms that are talking into iceboot.
#
source /usr/local/share/domhub-tools/common.sh
exec 2> /dev/null

if (( $# < 1 )); then
    echo "usage: $0 all|(spec ...)"
    echo "  where spec is: card pair dom (e.g. 00A)"
    exit 1
fi

doms=`getDomList $*`

#
# make list of doms for which we need to transition...
#
ncbdoms=`domstate ${doms} | grep -v ' configboot$' | awk '{ print $1; }'`

if (( `echo ${ncbdoms} | wc -c` > 0 )); then
    if ! iceboot -q ${ncbdoms}; then
	echo "`basename $0`: unable to put doms into iceboot"
    fi

    #
    # now we're all in iceboot...
    #
    cbpids=`for dom in ${ncbdoms}; do
       ( printf 'send "boot-serial reboot\r"\nexpect "^# "\n' | \
	   se ${dom} >& /dev/null ) & echo $!
    done`

    wait-till-dead 2000 ${cbpids}
fi

# for compatibility...
if (( ${#quiet} == 0 )); then
    domstate ${doms} | awk '{ print $1 " in " $2; }'
fi
