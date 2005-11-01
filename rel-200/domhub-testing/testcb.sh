#!/bin/bash

#
# testcb.sh, test configboot -- power cycle is part of
# the test so we lose access to both doms on the pair...
#
PATH=${PATH}:/usr/arm-elf/bin

card=1
pair=1
dom=${card}${pair}A

#
# testcb.sh, test configboot...
#
if (( $# != 1 )); then
    echo "usage: testcb.sh nloops"
    exit 1
fi

cp -fl ../../dom-fpga/stf/ComEPXA4DPM/simpletest.sbi iceboot.sbi

#
# power cycle...
#
off $card $pair && sleep 1 && on $card $pair

for (( i=0; i<$1; i++ )); do
    #
    # create a release.hex file...
    #
    dd if=/dev/urandom of=1.bin bs=1024 count=100 >& /dev/null
    dd if=/dev/urandom of=2.bin bs=1024 count=100 >& /dev/null
    dd if=/dev/urandom of=3.bin bs=1024 count=100 >& /dev/null
    dd if=/dev/urandom of=4.bin bs=1024 count=100 >& /dev/null
    dd if=/dev/urandom of=5.bin bs=1024 count=100 >& /dev/null
    dd if=/dev/urandom of=6.bin bs=1024 count=100 >& /dev/null
    dd if=/dev/urandom of=7.bin bs=1024 count=100 >& /dev/null
    dd if=/dev/urandom of=8.bin bs=1024 count=100 >& /dev/null
    dd if=/dev/urandom of=9.bin bs=1024 count=100 >& /dev/null
    dd if=/dev/urandom of=10.bin bs=1024 count=100 >& /dev/null
    (cd ..; /bin/bash mkrelease.sh epxa10/bin/iceboot.bin.gz \
	testing/iceboot.sbi \
	../iceboot/resources/startup.fs \
	testing/1.bin testing/2.bin testing/3.bin testing/4.bin \
	testing/5.bin testing/6.bin testing/7.bin testing/8.bin \
	testing/9.bin testing/10.bin 2> /dev/null ) > /tmp/mkr.out

    cks=`egrep '^[a-f0-9]*[ ]*flash.dump$' /tmp/mkr.out | \
	sed 's/ .*$//1'`
	
    echo "cks=$cks"

    if (( ${#cks} != 32 )); then 
	echo "testcb.sh: unable to create release.hex"
	exit 1
    fi

    #
    # make sure we made it into iceboot...
    #
    if [[ `(cd ../domhub-tools; ./domstate.sh ${dom}) | awk '{print $2; }'` \
		!= "configboot" ]]; then
	echo "testcb.sh: ${dom} is not in configboot"
	exit 1
    fi

    #
    # every other loop swap a and b...
    #
    if (( $i % 2 == 1 )); then
	#
	# swap a and b
	#
	if ! printf 'send "b"\nexpect "^  Swap flash A and B"\n' | \
		se ${dom}; then
	    echo "testcb.sh: unable to swap a and b flash chips"
	    exit 1
	fi
    fi

    #
    # start flash burn...
    #
    if ! ( cd ../domhub-tools; ./insrel.sh ../release.hex ${dom} ); then
	echo "testcb.sh: unable to install release.hex"
	rm -f ../release.hex
	exit 1
    fi

    rm -f ../release.hex

    #
    # get checksum
    #
    cat <<EOF > /tmp/tc.$$.se
send "s\\" md5sum \\" type \$40000000 \$00800000 md5sum type crlf type\\r"
expect "^md5sum [0-9a-f]+\$"
EOF

    cks2=`se ${dom} < /tmp/tc.$$.se | tr -d '\r' | grep '^md5sum' | \
	awk '{print $2;}'`

    rm -f /tmp/tc.$$.se

    #
    # all good?
    #
    if [[ "$cks" != "$cks2" ]]; then
	echo "failure on loop: $i"
	echo "  cks=${cks}, burned=${cks2}."
	exit 1
    fi

    #
    # power cycle...
    #
    off $card $pair && sleep 1 && on $card $pair

cat <<EOF > /tmp/tc.$$.se
send "s"
expect "^# "
send "r"
expect "^# "
EOF

    if ! se ${dom} < /tmp/tc.$$.se; then
	echo "testcb.sh: unable to boot serial"
	exit 1
    fi

    rm -f /tmp/tc.$$.se
done

off $card $pair

rm -f iceboot.sbi
rm -f [0-9]*.bin






