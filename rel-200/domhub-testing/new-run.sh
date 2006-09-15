#!/bin/bash

#
# newrun.sh, get a new mjb collection
# run filename...
#
if [[ ! -d mjb-output ]]; then
    mkdir mjb-output
fi

if [[ ! -f mjb-output/run.num ]]; then
    echo '0' > mjb-output/run.num
fi

let num=$(( `cat mjb-output/run.num` ))
let next=$(( ${num} + 1 ))
echo ${next} > mjb-output/run.num

printf 'mjb-output/%05d.dat\n' ${next}
