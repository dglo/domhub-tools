BEGIN { print "10 k"; }

{
   #
   # generate a dc file to do calculation
   #
   #   ( (domrx -  domtx )/2 + (dorrx - dortx) - 2*47  + dorfid + domfid )*50
   print $6 " " $5 " - 2 / " $4" " $3 " - + 47 2 * - " $1 " + " $2 "+ 50 * p";
}

END { print "q"; }

