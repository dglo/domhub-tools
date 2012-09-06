#!/bin/bash

autodac=on
thresh=64
rdelay=10
sdelay=255
dacmax=3
minclev=960
maxclev=970

# sc.sh, set comm parameters...
while /bin/true; do
   if [[ $1 == "-auto" ]]; then
       autodac=$2
   elif [[ $1 == "-sdelay" ]]; then
       sdelay=$2
   elif [[ $1 == "-rdelay" ]]; then
       rdelay=$2
   elif [[ $1 == "-dacmax" ]]; then
       dacmax=$2
   elif [[ $1 == "-thresh" ]]; then
       thresh=$2
   elif [[ $1 == "-minclev" ]]; then
       minclev=$2
   elif [[ $1 == "-maxclev" ]]; then
       maxclev=$2
   else
     break
   fi 
   shift; shift
done

if (( $# != 1 )); then
    echo "usage: `basename $0` [options] card"
    echo "  options:"
    echo "    -auto (on|off)   -> turn on or off auto dac setting"
    echo "    -sdelay (1..255) -> set send delay"
    echo "    -rdelay (1..255) -> set rcv delay"
    echo "    -dacmax (0..3)   -> max dac setting"
    echo "    -thresh (1..255) -> threshold"
    echo "    -minclev (256..1023) -> minimum comm level"
    echo "    -maxclev (256..1023) -> maximum comm level"
    exit 1
fi

if (( $1 < 0 || $1 > 7 )); then
    echo "`basename $0`: invalid card: $1"
    exit 1
fi

card=$1
procd=/proc/driver/domhub/card${card}

#
# deal w/ autodac...
#
reg=`cat ${procd}/fpga | awk '$1 ~ /^CTRL$/ { print substr($2, 3, 8); }' | \
  tr '[a-f]' '[A-F]'`
if [[ $autodac == "off" ]]; then
  let regv=$(( 0x${reg} | 0x8000 ))
elif [[ $autodac == "on" ]]; then
  let regv=$(( 0x${reg} & ~ 0x8000 ))
else
  echo "`basename $0`: invalid autodac setting, must be on|off"
  exit 1
fi
echo "w 0 `printf "%08x" ${regv}`" > ${procd}/fpga-regs

#
# deal w/ frev (31)
#
let regv=$(( ( ${maxclev} << 16 ) | ${minclev} ))
echo "w 31 `printf "%08x" ${regv}`" > ${procd}/fpga-regs

#
# deal w/ dcrev (30)
#
let regv=$(( ( ${sdelay} << 24 ) | ( ${rdelay} << 16 ) | ( ${dacmax} << 12 ) \
  | ${thresh} ))
echo "w 30 `printf "%08x" ${regv}`" > ${procd}/fpga-regs

