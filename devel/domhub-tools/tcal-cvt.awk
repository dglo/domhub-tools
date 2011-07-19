/^cal/ {
    idx = match($0, "cal\([0-9]+\)");
    if (idx==0) {
	print "tcal-cvt.awk: no cal match!";
	exit(1);
    }
    else {
	cal = substr($0, idx + 4, RLENGTH - 5);
    }

    idx = match($0, "dor_tx\(0x[0-9a-f]+\)");
    if (idx==0) {
	print "tcal-cvt.awk: no dor_tx match";
	exit(1);
    }
    else {
	dor_tx = toupper(substr($0, idx+9, RLENGTH-10));
	cmd = "echo 16 i " dor_tx " p | dc";
	cmd | getline tx;
	close(cmd);
	dor_tx = tx;
    }

    idx = match($0, "dor_rx\(0x[0-9a-f]+\)");
    if (idx==0) {
	print "tcal-cvt.awk: no dor_rx match";
	exit(1);
    }
    else {
	dor_rx = toupper(substr($0, idx+9, RLENGTH-10));
	cmd = "echo 16 i " dor_rx " p | dc";
	cmd | getline rx;
	close(cmd);
	dor_rx = rx;
    }

    idx = match($0, "dom_tx\(0x[0-9a-f]+\)");
    if (idx==0) {
	print "tcal-cvt.awk: no dom_tx match";
	exit(1);
    }
    else {
	dom_tx = toupper(substr($0, idx+9, RLENGTH-10));
	cmd = "echo 16 i " dom_tx " p | dc";
	cmd | getline tx;
	close(cmd);
	dom_tx = tx;
    }

    idx = match($0, "dom_rx\(0x[0-9a-f]+\)");
    if (idx==0) {
	print "tcal-cvt.awk: no dom_rx match";
	exit(1);
    }
    else {
	dom_rx = toupper(substr($0, idx+9, RLENGTH-10));
	cmd = "echo 16 i " dom_rx " p | dc";
	cmd | getline rx;
	close(cmd);
	dom_rx = rx;
    }
}

/^dor_wf/ {
    idx = match($0, "dor_wf\([0-9 ,]+\)");
    if (idx==0) {
	print("tcal-cvt.awk: no dor_wf match!");
	exit(1);
    }
    else {
	wfs = substr($0, idx + 7, RLENGTH-8);
	wf = split(wfs, a, ", ");
	printf "DOM_0a_TCAL_round_trip_%06d\n", (cal+1);
	print "dor_tx_time " dor_tx;
	print "dor_rx_time " dor_rx;
	for (i=1; i<=48; i++) printf "dor_%02d %d\n", (i-1), a[i];
    }
}

/^dom_wf/ {
    idx = match($0, "dom_wf\([0-9 ,]+\)");
    if (idx==0) {
        printf "tcal-cvt.awk: no dom_wf match!\n";
	printf "$0: '%s'\n", $0;
        exit(1);
    }
    else {
        wfs = substr($0, idx + 7, RLENGTH-8);
        wf = split(wfs, a, ", ");
        print "dom_tx_time " dom_tx;
        print "dom_rx_time " dom_rx;
        for (i=1; i<=48; i++) printf "dom_%02d %d\n", (i-1), a[i];
    }
}

