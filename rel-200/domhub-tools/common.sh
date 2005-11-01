#
# common.sh, common routines used by domhub-tools
# scripts.  this is installed in /usr/local/share/domhub-tools
#
function getDomList() {
    if [[ "$1" == "all" ]]; then
        if [[ -d /proc/driver/domhub ]]; then
            find /proc/driver/domhub -name is-communicating \
                -exec cat {} \; | grep -v NOT | awk '{ print $2 $4 $6; }' | \
                tr '\n' ' ' | tr '[ab]' '[AB]'
	else
	    cat /proc/dor/*/dom-status | \
		awk '$2 ~ /^communicating$/ { print $1; }' | tr '\n' ' ' | \
		sed 's/ $//1'
        fi
    else
        echo $* | tr '[ab]' '[AB]'
    fi
}

function splitCWD () { echo $1 | sed 's/[0-7]/& /g';  }
function getCard() { echo `splitCWD $1 | awk '{ print $1; }'`; }
function getPair () { echo `splitCWD $1 | awk '{ print $2; }'`; }
function getDOM () {
    echo `splitCWD $1 | awk '{ print $3; }' | tr '[ab]' '[AB]'`
}
function getDev () {
   if [[ -d /proc/driver/domhub ]]; then
      echo "/dev/dhc`getCard $1`w`getPair $1`d`getDOM $1`"
   else
      echo "/dev/dor/`getCard $1``getPair $1``getDOM $1`"
   fi
}

#
# list ancestors of process given...
#
function proginy () {
   local anc=`ps -e -o pid,ppid | awk "\\$2 ~ /^$1\\$/ { print \\$1; }"`
   for a in ${anc}; do
      local anc="${anc} `proginy $a`"
   done
   echo ${anc}
}

function massacre () {
    while (( $# > 0 )); do
        /bin/kill $1 `proginy $1`
        shift
    done
}

function all-dead() {
    for pid in $*; do
	if [[ -d /proc/${pid} ]]; then return 1; fi
    done
    return 0
}

#
# wait until pids in pidlist are dead, or kill them if they don't
# finish by timeout given (in ms)
#
# $1=timeout in ms, the rest are pids...
#
function wait-till-dead() {
    local ticks=$(( $1 / 100 ))
    shift
    local pidlist=$*

    if (( ${#pidlist} == 0 )); then
        return 0
    fi

    # wait for pids to finish, or timeout...
    for ((i=0; i<${ticks}; i++)); do
	sleep 0.1
	if all-dead ${pidlist}; then break; fi
    done

    if ! all-dead ${pidlist}; then
	massacre ${pidlist}
    fi
}

#
# expand cards from 01234567 | all
#
# FIXME: deal w/ no dor cards...
#
function cards-from-cardspec() {
    if [[ "$1" == "all" ]]; then
	lessecho /proc/dor/[0-7] | sed 's/^[^0-9]*//1' | tr '\n' ' ' | \
	    sed 's/ $//1'
    else
	echo $1 | sed 's/[0-7]/& /g' | sed 's/ $//1'
    fi
}
