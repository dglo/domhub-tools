#!/bin/bash

#
# insrel.sh, install a release.hex file on a dom...
#
if (( "$#" != 2 )); then
    echo "usage: $0 release.hex CWD"
    exit 1
fi

#
# does the release.hex file exist?
#
if [[ ! -f $1 ]]; then
	echo "$0: $1 does not exist or is not a regular file."
	exit 1
fi

#
# make sure dom is in configboot...
#

if [[ "`domstate $2 | awk '{ print $2; }'`" != "configboot" ]]; then
    echo "`basename $0`: unable to put $2 into configboot..."
    exit 1
fi

function atexit() {
    rm -f /tmp/insrel.$$.*
}
trap atexit EXIT

#
# prepare dom to receive hex file...
#
cat <<EOF > /tmp/insrel.$$.exp
send '"\r"'
expect '"^# "'
send '"p 0 1\r"'
expect '"Ready..."'
send '"^A"'
expect '"^domterm> "'
send "dd if=$1\n"
expect '"^domterm> "'
send '"\n"'
sleep 1
send '"\r"'
expect '"^#"'
send '"r"'
expect '"^> "'
EOF

if ! se $2 < /tmp/insrel.$$.exp; then
    echo "insrel.sh: unable to install image"
    exit 1
fi

