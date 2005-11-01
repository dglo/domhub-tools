#
# dor waveform
#
BEGIN {
    winstart = 22;
    winend = 39;
}

$1 ~ /do[mr]_00/     { baseline = $2; }
$1 ~ /do[mr]_0[1-2]/ { baseline += $2; }
$1 ~ /do[mr]_03/     { centroid = 0; centroidsum = 0; baseline/=3.0; }

$1 ~ /do[mr]_[0-9][0-9]/ {
    n=strtonum(substr($1, 5));
    v = $2 - baseline;

    if (n>=winstart && n<=winend && v>0) {
	centroid += n * v;
	centroidsum += v;
    }
}

$1 ~ /dor_47/ { dorf = 1.0*centroid/centroidsum; }
$1 ~ /dom_47/ { 
    domf = 1.0*centroid / centroidsum;
    print dorf, domf, dor_tx, dor_rx, dom_tx, dom_rx;
}

$1 ~ /dor_tx_time/ { dor_tx = $2; }
$1 ~ /dor_rx_time/ { dor_rx = $2; }
$1 ~ /dom_tx_time/ { dom_tx = $2; }
$1 ~ /dom_rx_time/ { dom_rx = $2; }

$1 ~ /DOM_0[ab]_TCAL_round_trip_[0-9][0-9][0-9][0-9][0-9]/ {}


































