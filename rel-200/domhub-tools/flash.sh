#!/bin/bash

# bring in shared routines...
source /usr/local/share/domhub-tools/common.sh

#
# flash.sh, some flash related routines for my driver...
#
# FIXME: a little error handling would be nice!
#
# $1=dor cards
function flash-protect() {
    if (( $# != 1 )); then
       echo "usage: flash protect cardspec"
       return
    fi

    ( for card in `cards-from-cardspec $1`; do \
	echo protect > /proc/dor/${card}/flash-protect & \
      done; wait )
}

# $1=dor cards
function flash-unprotect() {
    if (( $# != 1 )); then
       echo "usage: flash unprotect cardspec"
       return
    fi

    ( for card in `cards-from-cardspec $1`; do \
	echo unprotect > /proc/dor/${card}/flash-protect & \
      done; wait )
}

# burn a page, $1=dor cards, $2=page, $3=file
function flash-burn() {
    if (( $# != 3 )); then
        echo "usage: flash burn cardspec page file"
	return
    fi

    ( for card in `cards-from-cardspec $1`; do \
	dd if=$3 of=/dev/dor/flash/${card}$2 bs=65536 & \
      done; wait )
}

# read a page, $1=dor card, $2=page, $3=file
function flash-read() {
    dd if=/dev/dor/flash/$1$2 of=$3 bs=65536
}

# read a page to stdout, $1=dor card, $2=page
function flash-cat() {
    dd if=/dev/dor/flash/$1$2 bs=65536
}

if (( $# < 1 )); then
    echo "usage: flash cmd ..."
    exit 1
fi

sub=$1
shift
flash-${sub} $*
