#!/bin/bash

#
# softboot.sh, softboot dom(s)...
#
source /usr/local/share/domhub-tools/common.sh
exec 2> /dev/null

force=0
quiet=0
while (( $# > 1 )); do
    if [[ "$1" == "-f" ]]; then 
        force=1
    elif [[ $1 == "-q" ]]; then
        quiet=1
    else 
        break
    fi
    shift
done

if (( $# < 1 )); then
    echo "usage: softboot [-f|-q] (all)|(CWD ...)"
    exit 1
fi

doms=`getDomList $*`
odoms="${doms}"

if (( ${force} == 0 )); then
    #
    # find doms not in configboot already...
    #
    doms=`domstate ${doms} | grep -v ' configboot$' | \
       awk '{ if (NF==2) print $1; }'`
fi

for dom in ${doms}; do
    #
    # send reset string...
    #
    card=`echo ${dom} | awk '{ print substr($0, 1, 1); }'`
    wp=`echo ${dom} | awk '{ print substr($0, 2, 1); }'`
    d=`echo ${dom} | awk '{ print substr($0, 3, 1); }'`

    procfile="/proc/driver/domhub/card${card}/pair${wp}/dom${d}"
    if [[ ! -d ${procfile} ]]; then
        shift
        continue
    fi

    echo "reset" > /proc/driver/domhub/card${card}/pair${wp}/dom${d}/softboot &
done

wait

if (( ${quiet} == 0 )); then
    domstate ${odoms} | \
        awk '{ if (NF==2) print $1 " in " $2; else print $0; }'
fi


