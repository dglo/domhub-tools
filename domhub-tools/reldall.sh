
#!/bin/bash

source /usr/local/share/domhub-tools/common.sh
exec 2> /dev/null
#
# reldall.sh, reload release.hex image to doms
#
if (( $# < 1 )); then
    echo "Usage: `basename $0` [-e cwd -e hub:cwd ...] release.hex[.gz]"
    echo "       -e hub:cwd    Exclude DOM from installation"
    exit 1
fi

# Get hostname, and trim off any sps- or spts- prefixes
host=`hostname -s`
host=${host#sps-}
host=${host#spts-}

# Poor-man's getopt
exclusions=()
while [[ $# > 2 ]]
do
key="$1"
shift
case $key in
    -e)
        arg="$1"
        domArr=(${arg//:/ })
        # Check if it matches the hub name
        if [ ${#domArr[@]} -gt 1 ]; then
            if [ ${domArr[0]} == $host ]; then
                cwd=${domArr[1]}
                cwd=${cwd^^}
                exclusions+=($cwd)
            fi            
        else
            cwd=$arg
            cwd=${cwd^^}
            exclusions+=($cwd)
        fi
        shift
        ;;
    *)
            # unknown option
    ;;
esac
done

if [ ${#exclusions[@]} -gt 0 ]; then
    echo "Excluding DOMs on $host: ${exclusions[@]}"
fi

#
# first gzip archive if it is not one already...
#
if ! gzip -t $1 >& /dev/null; then
    dorm=1
    fname=`mktemp /tmp/reldall-gz-XXXXXXXX`
    if ! gzip -c $1 > $fname ; then
	echo "`basename $0`: unable to gzip $1"
	rm -f ${fname}
	exit 1
    fi
else
    dorm=0
    fname=$1
fi

function atexit() {
    # rm created .gz release.hex file?
    if (( ${dorm} == 1 )); then rm -f ${fname}; fi

    # rm ttf files
    if [[ -f ${ttf} ]]; then
        for dom in `cat ${ttf}`; do
	    rm -f `awk -vFS=':' '{ print $1; }' ${ttf}`
        done
        rm -f ${ttf}
    fi
}

trap atexit EXIT

#
# get list of doms...
#
doms=`iceboot all | awk '$3 ~ /^iceboot$/ { print $1; }'`

if (( ${#doms} == 0 )); then
    echo "`basename $0`: unable to find any doms in iceboot"
    exit 1
fi

release=${fname}

ttf=`mktemp /tmp/reldall-domlist-XXXXXX`
n=0
for dom in ${doms}; do
    # Check if the DOM is in the exclusion list
    exclude=0
    for excludedom in "${exclusions[@]}"; do
        if [ $excludedom == $dom ]; then
            exclude=1
        fi
    done
    if (( ${exclude} == 1 )); then
        continue
    fi
    # Run the flash reload command
    tf=`mktemp /tmp/reldall-${dom}-results-XXXXXXXX`
    reldcwd ${release} ${dom} >& ${tf} &
    echo "${tf}:${dom}:$!"
    let n=$(( $n + 1 ))
done > ${ttf}

echo "$host: started reldcwd on $n doms..."

pidlist=`awk -vFS=':' '{ print $3; }' ${ttf} | tr '\n' ' ' | sed 's/ $//1'`

wait-till-dead 720000 $pidlist

for dom in `cat ${ttf}`; do
    pid=`echo $dom | awk -vFS=':' '{ print $3; }'`
    if ! wait ${pid};  then
        fn=`echo $dom | awk -vFS=':' '{ print $1; }'`
        d=`echo $dom | awk -vFS=':' '{ print $2; }'`
        h=`hostname -s`
        awk -vd=$d -vh=$h '{ print h, d, "FAIL> " $0; }' ${fn}
    fi
done
