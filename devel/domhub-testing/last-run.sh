#!/bin/bash

#
# get the most recent run...
#
find mjb-output -type f -print | egrep '^mjb-output/[0-9]+.dat$' | tail -1

