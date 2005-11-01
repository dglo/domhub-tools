#!/bin/bash

#
# echo-mode.sh, put doms into echo mode...
#
source /usr/local/share/domhub-tools/common.sh
exec 2> /dev/null

quiet=0
while /bin/true; do
    if [[ $1 == "-q" ]]; then
        quiet=1
    else
        break
    fi
    shift
done

if (( $# < 1 )); then
    echo "usage: `basename $0` (all)|(CWD ...)"
    exit 1
fi

doms=`getDomList $*`

#
# doms -> iceboot
#
iceboot -q ${doms} >& /dev/null

#
# all doms are now in iceboot...
#
pids=`for dom in ${doms}; do
  ( printf 'send "echo-mode\r"\nexpect "echo-mode"\n' |
      se ${dom} >& /dev/null ) & echo $!
done`

wait-till-dead 5000 ${pids}
