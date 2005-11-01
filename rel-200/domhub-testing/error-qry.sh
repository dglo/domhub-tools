#!/bin/bash

# error-details-qry, get details in errors...
testnm=""
while /bin/true; do
    if [[ $1 == "-t" ]]; then
        testnm="$2 "
        shift
    else
        break
    fi
    shift 
done


if (( $# != 1 )); then
    echo "usage: `basename $0` dbfile"
    exit 1
fi

grep 'ERROR' $1 | grep "^${testnm}" | awk '{print $1, $2, $3; }' | \
    while read line; do \
        echo ${line}; ./details-qry.sh $1 `echo ${line}`; echo " "; \
    done

