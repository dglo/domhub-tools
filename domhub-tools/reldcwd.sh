#!/bin/bash

#
# reldcwd.sh, reload release.hex.gz image to dom
#
if (( $# != 2 )); then
    echo "usage: `basename $0` release.hex.gz CWD"
    exit 1
fi

if ! domstate $2 | grep 'iceboot$' > /dev/null; then
    echo "`basename $0`: $2 is not in iceboot"
    exit 1
fi

if ! gzip -t $1 >& /dev/null; then
    echo "`basename $0`: $1 is not a valid gzip archive"
    exit 1
fi

fname=$1
filelen=`stat ${fname} | awk '$1 ~ /^Size:$/ { print $2; }'`
expfile=`mktemp /tmp/reldcwd-sh-XXXXXX`
trap "rm -f ${expfile}" EXIT

cat <<EOF > ${expfile}
send "\$ffffffff \$01000000 \$00800000 4 / iset\r"
expect "^> "
send "${filelen} read-bin\r"
expect "read-bin"
send "^A"
expect "^domterm> "
send "dd if=${fname}\n"
expect "^domterm> "
send "status\n"
expect "^0\r\ndomterm> "
send "\r"
expect "^> "
send "gunzip \$01000000 \$01000000 hex-to-bin\r"
expect "^> "
send "\$01000000 \$00400000 install-image\r"
expect "^install: all flash data will be erased: are you sure [y/n]?"
send "y\r"
expect "^> "
send ".\r"
expect "^0"
EOF

if ! cat ${expfile} | se $2; then
    echo "`basename $0`: unable to upload"
    exit 1
fi
