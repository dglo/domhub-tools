#
# results-common.sh, common routines for all results
#
function paired-doms() {
	local doms=`awk '/^versions / { print $3; }' ${DBFILE} | \
		tr '\n' ' ' | sed 's/ $//1'`
	local dom
	local pdoms=""
	for dom in ${doms}; do
		pdom=`echo ${dom} | tr '[AB]' '[BA]'`
		if echo ${doms} | grep ${pdom} >& /dev/null; then
			pdoms="${pdoms} ${dom}"
		fi 
	done
	echo ${pdoms}
}

function unpaired-doms() {
        local doms=`awk '/^versions / { print $3; }' ${DBFILE} | \
                tr '\n' ' ' | sed 's/ $//1'`
        local dom
        local pdoms=""
        for dom in ${doms}; do
                pdom=`echo ${dom} | tr '[AB]' '[BA]'`
                if ! echo ${doms} | grep ${pdom} >& /dev/null; then
                        pdoms="${pdoms} ${dom}"
                fi 
        done
        echo ${pdoms}
}

