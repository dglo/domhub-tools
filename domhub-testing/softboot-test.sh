#!/bin/bash

#
# domid-test.sh, do domids match -- are they valid -- are
# there any duplications?
#
# output: procfile_dom_id iceboot_dom_id
# 
errs=0
for (( i=0; i<10; i++ )); do
    softboot $1 | grep ' iceboot$' >& /dev/null
    status=$?
    if (( ${status} != 0 )); then
       let errs=$(( ${errs} + 1 ))
    fi
done

echo $1 $i $errs

