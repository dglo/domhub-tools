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
   echo "/dev/dhc`getCard $1`w`getPair $1`d`getDOM $1`"
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

