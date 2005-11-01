#!/bin/bash

v=`awk '{ print $8; }' $1 | sort -n -r | sed -n '1p'`

if (( $v > 1 )); then
	echo "echo: too many crc errors"
	exit 1
fi

