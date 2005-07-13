#
# do tcal analysis using trailing edge crossover...
#
$1 ~ /^dom_[0-9][0-9]$/ {
   ar="";
}

$1 ~ /^do[mr]_[0-9][0-9]$/ {
   ar=ar $2 "\n";
}

$1 ~ /dor_47/ { dorf = system("xovr 1.0*centroid/centroidsum; }
$1 ~ /dom_47/ { 
    domf = 1.0*centroid / centroidsum;
    print dorf, domf, dor_tx, dor_rx, dom_tx, dom_rx;
}

$1 ~ /dor_tx_time/ { dor_tx = $2; }
$1 ~ /dor_rx_time/ { dor_rx = $2; }
$1 ~ /dom_tx_time/ { dom_tx = $2; }
$1 ~ /dom_rx_time/ { dom_rx = $2; }

$1 ~ /DOM_0[ab]_TCAL_round_trip_[0-9][0-9][0-9][0-9][0-9]/ {}


































