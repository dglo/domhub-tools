#!/bin/bash

# ldfb.sh, load the flasherboard firmware on all doms...

#
# power cycle...
#
(pwr off && sleep 1 && pwr on) >& /dev/null

#
# get doms
#
doms=`iceboot all | awk '$3 ~ /^iceboot$/ { print $1; }' | \
    tr '\n' ' ' | sed 's/ $//1'`

echo "found: $doms"

function ldfw() {
    local ret
    local tf=`mktemp /tmp/ldfb-XXXXXX`
    printf 'send "enableFB\r"\nexpect "^> "\n' | se $1 > $tf
    if grep '^Error: flasherboard configuration' $tf > /dev/null; then
	echo "$1 flasherboard not detected"
    else
	printf 'send "s\" fb-cpld.xsvf.gz\" find if gunzip fb-cpld endif\r"\nexpect "^> "\n' | se $1 > $tf
	if grep '^XSVF executed successfully' $tf >& /dev/null; then
	    printf 'send "getFBfw . drop\r"\nexpect "^> "\n' | se $1 | \
		tr -d '\r'> $tf
	    echo "$1 firmware version `egrep '^[0-9][0-9]*$' $tf`"
	else
	    echo "$1 unable to find fb-cpld.xsvf.gz"
	fi
    fi
    printf 'send "disableFB\r"\nexpect "^> "\n' | se $1 > $tf

    rm -f ${tf}
}

#
# separate into A and B doms...
#
adoms=`echo $doms | tr ' ' '\n' | grep '[0-7][0-3]A$' | tr '\n' ' ' | \
    sed 's/ $//1'`
bdoms=`echo $doms | tr ' ' '\n' | grep '[0-7][0-3]B$' | tr '\n' ' ' | \
    sed 's/ $//1'`

for dom in $adoms; do
    ldfw $dom &
done
wait

#
# FIXME: should we power cycle here?
#
for dom in $bdoms; do
    ldfw $dom &
done
wait

pwr off