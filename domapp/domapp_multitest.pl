#!/usr/bin/perl

# John Jacobsen, NPX Designs, Inc., jacobsen\@npxdesigns.com
# Started: Sat Nov 20 13:18:25 2004
# $Id: domapp_multitest.pl,v 1.27 2005-05-29 20:42:48 jacobsen Exp $

package DOMAPP_MULTITEST;
use strict;
use Getopt::Long;

sub testDOM;     sub loadFPGA;     sub docmd;      sub hadError; sub filly;
sub hadWarning;  sub printWarning; sub printc;     sub delim;
sub endTests;    sub usage;        sub logresults; sub collectDoms;
sub haveLogs;

sub sigged { die "Got signal, bye bye.\n"; }
$SIG{INT} = $SIG{KILL} = \&sigged;
    
my $failstart = "\n\nFAILURE ------------------------------------------------\n";
my $failend   =     "--------------------------------------------------------\n";
my $O            = filly $0;
my $msgcols      = 50;
my $speThreshDAC = 9;
my $speThresh    = 600;
my $pulserDAC    = 11;
my $pulserAmp    = 500;
my $defaultDACs  = "-S0,850 -S1,2097 -S2,600 -S3,2048 "
    .              "-S4,850 -S5,2097 -S6,600 -S7,1925 "
    .              "-S10,700 -S13,800 -S14,1023 -S15,1023";
my $dat          = "/usr/local/bin/domapptest";
    

sub mydie { die $failstart.shift().$failend; }
    
my ($help, $image, $showcmds, $loadfpga, $detailed,
    $dohv, $doflasher, $dolong);

my $loops = 1;

GetOptions("help|h"          => \$help,
	   "upload|u=s"      => \$image,
	   "showcmds|s"      => \$showcmds,
           "dolong|o"        => \$dolong,
           "detailed|d"      => \$detailed,
	   "loadfpga|l=s"    => \$loadfpga,
           "dohv|V"          => \$dohv,
           "dat|A=s"         => \$dat,
           "loops|N=i"       => \$loops,
           "doflasher|F"     => \$doflasher) || die usage;

die usage if $help;

die "Can't find domapptest program $dat.\n" unless -e $dat;

if(defined $image) {
    mydie "Can't find domapp image (\"$image\")!  $O -h for help.\n"
	unless -f $image;
}

die "Log files exist; rm dmt????.log first.\n" if haveLogs;

my %card;
my %pair;
my %aorb;
my $iter;
my $fail = 0;
my $nt   = 0;
my @doms = @ARGV;
if(@doms == 0) { $doms[0] = "all"; }

collectDoms;

print "$O: Starting tests at '".(scalar localtime)."'\n";

# implement serially now, but think about parallelizing later

for($iter=0; $iter < $loops; $iter++) {
    foreach my $dom (@doms) {
	testDOM($dom);
    }
}

endTests($fail, $nt);

exit;

######################################################################

sub SKIP { printc "SKIPPING $_[0]... OK.\n"; return 1; }

sub endTests { 
    if($fail) {
	print "domapp_multitest: FAIL ($fail out of $nt tests)\n";
    } else {
	print "domapp_multitest: SUCCESS (all $nt tests passed)\n";
    }
    exit;
}

sub testDOM {
# Upload DOM software and test.  Return 1 if success, else 0.
    my $dom  = shift;

    $nt++; 
    unless(softboot($dom)) {
	$fail++; return 0;
    }
    
    if(defined $loadfpga) {
	$nt++; 
	if(!loadFPGA($dom, $loadfpga)) {
	    $fail++; return 0;
	}
    }

    if(defined $image) {
	$nt++;
	unless(upload($dom, $image)) {
	    $fail++; return 0;
	}
    } else {
	$nt++;
	unless(domappmode($dom)) {
	    $fail++; return 0;
	}
    }

    $nt++; $fail++ unless versionTest($dom);
    $nt++; $fail++ unless getDOMIDTest($dom);
    $nt++; $fail++ unless asciiMoniTest($dom);

    if($dolong) {
	$nt++; $fail++ unless doMultiplePedestalFetch($dom);
    }

    if($doflasher) {
	$nt++; $fail++ unless flasherVersionTest($dom);
    }

    if($dohv) {
	$nt++; $fail++ unless setHVTest($dom);
    }

    $nt++; $fail++ unless collectPulserDataTestNoLC($dom);   # Pulser test of SPE triggers
    $nt++; $fail++ unless SNCountsOnly($dom);
    $nt++; $fail++ unless SNCountsAndHits($dom);

    $nt++; $fail++ unless collectCPUTrigDataTestNoLC($dom);
    $nt++; $fail++ unless collectDiscTrigDataCompressedForced($dom);
    $nt++; $fail++ unless collectDiscTrigDataCompressedPulser($dom);
    $nt++; $fail++ unless collectDiscTrigDataTestNoLC($dom); # Should at least get forced triggers
    $nt++; $fail++ unless LCMoniTest($dom);
    $nt++; $fail++ unless shortEchoTest($dom);
    printc("Testing variable heartbeat/pulser rate:  \n");
    $nt++; $fail++ unless varyHeartbeatRateTestNoLC($dom);  
    $nt++; $fail++ unless swConfigMoniTest($dom);
    $nt++; $fail++ unless hwConfigMoniTest($dom);
    $nt++; $fail++ if $doflasher && !flasherTest($dom);

#    if(defined $dohv) {
#	return 0 unless collectDiscTrigDataTestNoLCWithHV($dom);
#    }

    return 1;
}

use constant CPUTRIG  => 1;
use constant DISCTRIG => 2;
use constant FMT_ENG  => 0;
use constant FMT_RG   => 1;
use constant CMP_NONE => 0;
use constant CMP_RG   => 1;

sub testHash {
    my %arg = @_;
    foreach my $key (keys %arg) {
	print "$key -> $arg{$key}\n";
    }
}

sub SNCountsOnly {
    my $dom = shift; die unless defined $dom;
    printc "Fetching SN data, no hit readout... ";
    my $snfile = "SNCounts_$dom.sn";
    my $cmd = "$dat $defaultDACs -d 4 -p -P 500 -K 1,0,6400,$snfile -T 2 $dom 2>&1";
    my $result = docmd $cmd;
    if($result =~ /ERROR/) {
	return logresults("Had ERROR in domapptest output:\n$result\n");
    } 
    if($result !~ /Done \((\d+) usec\)\./) {
        return logresults("ERROR: Did not find terminator string from "
			. "domapptest:\n$result\n");
    }
    print "OK.\n";
    return 1;
}

sub SNCountsAndHits {
    my $dom = shift; die unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
                                Trig        => DISCTRIG,
                                Name        => "SNTrigger",
                                DoPulser    => 1,
				Threshold   => $speThresh,
                                PulserRate  => 500,
                                Compression => CMP_NONE,
                                Format      => FMT_ENG,
                                SNDeadTime  => 6400,
                                skipRateChk => 1);
}

sub collectCPUTrigDataTestNoLC {
    my $dom = shift; die unless defined $dom;
    return doShortHitCollection(DOM         => $dom, 
				Trig        => CPUTRIG,
				Name        => "cpuTrigger", 
				DoPulser    => 0,
				Threshold   => 0, 
				PulserRate  => 1,
				Compression => CMP_NONE,
				Format      => FMT_ENG);
}

sub collectDiscTrigDataTestNoLC {
    my $dom = shift; die unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
                                Trig        => DISCTRIG,
                                Name        => "discTrigger",
                                DoPulser    => 0,
                                Threshold   => $speThresh,
                                PulserRate  => 1,
                                Compression => CMP_NONE,
                                Format      => FMT_ENG);
}

sub collectPulserDataTestNoLC {
    my $dom = shift; die unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
                                Trig        => DISCTRIG,
                                Name        => "pulserTrigger",
                                DoPulser    => 1,
                                Threshold   => $speThresh,
                                PulserRate  => 10,
                                Compression => CMP_NONE,
                                Format      => FMT_ENG);
}

sub varyHeartbeatRateTestNoLC {
    my $dom = shift; die unless defined $dom;
    my @rates = (10, 100, 1);
    foreach my $rate (@rates) {
	return 0 unless doShortHitCollection(DOM         => $dom,
					     Trig        => DISCTRIG,
					     Name        => "heartbeat_".$rate."Hz",
					     DoPulser    => 0,
					     Threshold   => $speThresh,
					     PulserRate  => $rate,
					     Compression => CMP_NONE,
					     Format      => FMT_ENG);
    }
    return 1;
}

sub collectDiscTrigDataCompressedForced {
    my $dom = shift; die unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
				Trig        => DISCTRIG,
				Name        => "comprForced",
				DoPulser    => 0,
				Threshold   => $speThresh,
				PulserRate  => 2000,
				Compression => CMP_RG,
				Format      => FMT_RG);
}

sub collectDiscTrigDataCompressedPulser {
    my $dom = shift; die unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
				Trig        => DISCTRIG,
				Name        => "comprPulsr",
				DoPulser    => 1,
				Threshold   => $speThresh,
				PulserRate  => 2000,
				Compression => CMP_RG,
				Format      => FMT_RG);
}

sub delim {
    print "-" x ($msgcols+3) . "\n";
}

sub printc {
    my $msg = shift;
    printf "%".$msgcols."s", $msg;
}

sub logresults {
    my $msg = shift;
    my $logfile = sprintf "dmt%04d.log",$nt;
    print "FAIL!  See $logfile for results.\n";
    open L, ">$logfile" || die "Can't open $logfile: $!\n";
    print L $msg;
    close L;
    return 0;
}

sub softboot { 
    my $dom = shift;
    printc "Softbooting $dom... ";
    my $result = `/usr/local/bin/sb.pl $dom`;
    if($result !~ /ok/i) {
	return logresults("Softboot result: $result\n");
    }
    my $details = $detailed?" (driver said softboot worked)":"";
    print "OK$details.\n";
    return 1;
}

sub loadFPGA {
    my $dom  = shift || die;
    my $fpga = shift || die;
    printc "Loading FPGA $fpga from flash on DOM $dom... ";
    my $se = "/usr/local/bin/se.pl"; die "Can't find $se!\n" unless -e $se;
    my $loadcmd = "$se $dom "
	.         "s\\\"\\\ $fpga\\\"\\\ find\\\ if\\\ fpga\\\ endif "
	.         "s\\\"\\\ $fpga\\\"\\\ find\\\ if\\\ fpga\\\ endif.+?\\>";
    my $result = docmd $loadcmd;
    if($result =~ /SUCCESS/) { 
        my $details = $detailed?" (se.pl script reported success)":"";
        print "OK$details.\n";
    } else {
	return logresults "Load of FPGA file failed.  Transcript:\n$result\n";
    }
    return 1;
}

sub upload {
    my $dom = shift;   die unless defined $dom;
    my $image = shift; die unless defined $image;
    my $f = filly $image;
    my $m = "Uploading $f to $dom... ";
    printc $m;
    my $uploadcmd = "/usr/local/bin/upload_domapp.pl $card{$dom} $pair{$dom} $aorb{$dom} $image";
    my $tmpfile = ".tmp_ul_$dom"."_$$";
    system "$uploadcmd 2>&1 > $tmpfile";
    my $result = `cat $tmpfile`;
    unlink $tmpfile || mydie "Can't unlink $tmpfile: $!\n";
    if($result !~ /Done, sayonara./) {
        print "\nupload failed: session text:\n$uploadcmd\n\n$result\n\n";
        return 0;
    } else {
	my $details = $detailed?" (upload_domapp.pl script reported success)":"";
	printc "$m"; print "OK$details.\n";
    }
    return 1;
}

sub versionTest {
    my $dom = shift;
    printc "Checking version with domapptest... ";
    my $cmd = "$dat -V $dom 2>&1";
    my $result = docmd $cmd;
    if($result !~ /DOMApp version is \'(.+?)\'/) {
	return logresults 
	    "Version retrieval from domapp failed:\ncommand: $cmd\nresult:\n$result\n\n";
    } else {
        my $details = $detailed?", got good version report from domapptest":"";
	print "OK ('$1'$details).\n";
    } 
    return 1;
}

sub setHVTest {
    my $dom = shift; die unless defined $dom;
    printc "Testing HV set/get... ";
    my $moniFile = "hv_test_$dom.moni";
    my $cmd = "$dat -L 500 -d 2 -w 1 -f 1 -M1 -m $moniFile $dom 2>&1";
    my $result = docmd $cmd;
    if($result !~ /Done \((\d+) usec\)\./) {
	my $moni = `decodemoni -v $moniFile 2>&1`;
	if($moni eq "") {
	    my $getMoniCmd = "$dat -d 1 -M1 -m last.moni $dom 2>&1";
	    my $result     = docmd $getMoniCmd;
	    $moni = "[original EMPTY -- following was fetched from domapp a second time around:]\n"
		.   $result
		.   `decodemoni -v last.moni`;
	}
	return logresults("Test of setting HV failed:\n"
	    .      "Command: $cmd\n"
	    .      "Result:\n$result\n\n"
	    .      "Monitoring:\n$moni\n");
    }
    print "OK.\n";
    return 1;
}

sub shortEchoTest {
    my $dom = shift;
    printc "Performing short domapp echo message test... ";
    my $cmd = "$dat -d2 -E1 $dom 2>&1";
    my $result = docmd $cmd;
    if($result =~ /Done \((\d+) usec\)\./) {        
	my $details = $detailed?" (domapptest program reported success)":"";
	print "OK$details.\n";
    } else {
	return logresults ("Short echo test failed:\n".
			   "Command: $cmd\n".
			   "Result:\n$result\n\n");
    }
    return 1;
}

sub LCMoniTest {
    my $dom = shift;
    printc "Testing moni. reporting of LC state chgs...\n";
    my $win0 = 100;
    my $win1 = 200;
    foreach my $mode(1..3) {
	my $moniFile = "lc_state_chg_mode$mode"."_$dom.moni";
	printc "Mode $mode: ";
	my $cmd = "$dat -d1 -M1 -m $moniFile -I $mode,$win0,$win1 $dom 2>&1";
	my $result = docmd $cmd;
	if($result !~ /Done \((\d+) usec\)\./) {
	    return logresults("Test of monitoring of LC state changes failed:\n".
			      "Command: $cmd\n".
			      "Result:\n$result\n\n");
	}

	my @dmtext = `/usr/local/bin/decodemoni -v $moniFile 2>&1`;
	# print @dmtext;
	my $gotwin = 0;
	my $gotmode = 0;
	for(@dmtext) {
	    if(hadError $_) {
		return logresults("Test of monitoring of LC state changes failed:\n"
				  ."Had error or warning in monitoring stream!\n".$_);
	    }
	    printWarning($_, $moniFile) if hadWarning $_;
# STATE CHANGE: LC WIN <- (100, 100)
	    if(/LC WIN <- \((\d+), (\d+)\)/) {
		if($1 ne $win0 || $2 ne $win1) {
		    return logresults("Window mismatch ($1 vs $win0, $2 vs $win1\n"
				      ."Line: $_\nFile: $moniFile\n");
		} else {
		    $gotwin = 1;
		}
	    }
	    if(/LC MODE <- (\d+)/) {
		if($1 ne $mode)  {
		    return logresults("Mode mismatch ($1 vs. $mode).\n".(join "\n",@dmtext));
		} else {
		    $gotmode = 1;
		}
	    }
	}
	if(! $gotwin) { 
	    return logresults((join "\n", @dmtext).
			      "Didn't get monitoring record indicating LC window change!\n");
	} 
	if(! $gotmode) {
            return logresults((join "\n", @dmtext).
			      "Didn't get monitoring record indicating LC mode change!\n");
	}
	my $details = $detailed?" (LC mode & window state change records looked good)":"";
        print "OK$details.\n";
    }
    return 1;
}

sub asciiMoniTest {
    my $dom = shift;
    printc "Testing ASCII monitoring... ";
    my $moniFile = "ascii_$dom.moni";
    my $cmd = "$dat -d0 -M1 -m $moniFile $dom 2>&1";
    my $result = docmd $cmd;
    if($result !~ /Done \((\d+) usec\)\./) {
        return logresults("Short monitoring test failed:\n".
			  "Command: $cmd\n".
			  "Result:\n$result\n\n");
    }
    my $dmtext = `/usr/local/bin/decodemoni -v $moniFile 2>&1`;
    if($dmtext !~ /MONI SELF TEST OK/) {
	print "Test failed: desired monitoring string was not present.\n";
	print "Monitoring output:\n$dmtext\n";
	return 0;
    } elsif(hadError $dmtext) {
	print "Test failed: monitoring stream had error or warning.\n";
        print "Monitoring output:\n$dmtext\n";
        return 0;
    } else {
	for(split '\n', $dmtext) {
	    printWarning($_, $moniFile) if hadWarning $_;
	}
        my $details = $detailed?" (got self test ASCII monitoring record)":"";
        print "OK$details.\n";
    }
    return 1;
}

sub getDOMIDTest {
    my $dom = shift; die unless defined $dom;
    printc "Testing fetch of DOM ID... ";
    my $cmd = "$dat -Q $dom 2>&1";
    my $result = docmd $cmd;
    if($result !~ /DOM ID is \'(.+?)\'/) {
        return logresults("DOM ID failed:\ncommand: $cmd\nresult:\n$result\n\n");
    } else {
        my $details = $detailed?", got good ID string from domapptest":"";
        print "OK ('$1'$details).\n";
    }
    return 1;
}


sub swConfigMoniTest {
    my $dom = shift;
    printc "Testing software configuration monitoring... ";
    my $moniFile = "sw_$dom.moni";
    my $cmd = "$dat -d2 -M1 -f 1 -m $moniFile $dom 2>&1";
    my $result = docmd $cmd;
    if($result !~ /Done \((\d+) usec\)\./) {
	return logresults("Short software monitoring test failed:\nCommand: $cmd\n".
			  "Result:\n$result\n\n");
    }
    my @dmtext = `/usr/local/bin/decodemoni -v $moniFile 2>&1`;
    my $gotone = 0;
    for(@dmtext) {
	if(/CF EVT/) {
	    $gotone++;
	    # print "\n$_";
	} elsif(hadError $_) {
	    return logresults("Monitoring stream had error: $_\n");
	}
	printWarning($_, $moniFile) if hadWarning($_);
    }
    if($gotone) {
        my $details = $detailed?" (got one or more software config. monitoring recs.)":"";
        print "OK$details.\n";
	return 1;
    } else {
	return logresults("No software configuration events found!\n");
    }
}



sub hwConfigMoniTest {
    my $dom = shift;
    printc "Testing hardware configuration monitoring... ";
    my $moniFile = "hw_$dom.moni";
    my $cmd = "$dat -d2 -M1 -w 1 -m $moniFile $dom 2>&1";
    my $result = docmd $cmd;
    if($result !~ /Done \((\d+) usec\)\./) {
	return logresults("HW monitoring test failed:\nCommand: $cmd\n".
			  "Result:\n$result\n\n");
    }
    my @dmtext = `/usr/local/bin/decodemoni -v $moniFile 2>&1`;
    my $gotone = 0;
    for(@dmtext) {
	if(/HW EVT/) {
	    $gotone++;
	    # print "\n$_";
	} elsif(hadError $_) {
	    return logresults("Have monitoring warning or error!\n$_");
	}
	printWarning($_, $moniFile) if hadWarning $_;
    }
    if($gotone) {
        my $details = $detailed?" (got one or more hardware config. monitoring recs.)":"";
        print "OK$details.\n";
	return 1;
    } else {
	return logresults("No hardware configuration events found!\n");
    }
}



sub domappmode { 
    my $dom = shift;
    printc "Putting DOM in domapp mode... ";
    my $cmd = "/usr/local/bin/se.pl $dom domapp domapp 2>&1";
    my $result = `$cmd`;
    if($result !~ /SUCCESS/) {
	return logresults("Change state of DOM $dom to domapp failed.  Result:\n$result\n\n");
    } else {
	print "OK.\n";
    }
    return 1;
}

sub checkEngTrigs {
    my $type     = shift; die unless defined $type;
    my $unkn     = shift; die unless defined $unkn;
    my $lcup     = shift; die unless defined $lcup;
    my $lcdn     = shift; die unless defined $lcdn;
    # If pulser is on, should ONLY have SPE triggers:
    my $puls     = shift; die unless defined $puls;
    my $summary  = shift; die unless defined $summary;
    my @typelines = @_;
    
    # print "Checking engineering event trigger lines for appropriate type/flags...\n";
    my $haveForcedTrig = 0;

    foreach my $line (@typelines) {
	chomp $line;
	# print "$line vs. $type $unkn $lcup $lcdn\n";
	if($line =~ /trigger type='.+?' flags=<(.+?)> \[(\S+)\]/) {
	    my $flagstr = $1;
	    if($flagstr eq "none") { # require no unkn, lcup, lcdn
		if($unkn || $lcup || $lcdn) {
		    return logresults("$summary\n(Hit file check failed: ".
				      "missing flag in trig line $line!)\n");
		}
	    }
	    # else look for UNKNOWN_TRIG LC_UP_ENA or LC_DN_ENA
	    if($unkn && $flagstr !~ /UNKNOWN_TRIG/) { 
		return logresults("$summary\n(Hit file check failed: ".
				  "UNKNOWN_TRIG flag required but absent in line $line).\n");
	    }
	    if($lcup && $flagstr !~ /LC_UP_ENA/) {
		return logresults( "$summary\n(Hit file check failed: ".
				   "LC_UP_ENA flag required but absent in line $line!)\n");
            }
            if($lcdn && $flagstr !~ /LC_DN_ENA/) {
                return logresults( "$summary\n(Hit file check failed: ".
				   "LC_DN_ENA flag required but absent in line $line!)\n");
            }
	    my $hittype = hex($2); 
	    $haveForcedTrig = 1 if $hittype == 1;
	    my $badhit = 0;
	    $badhit = 1 if $puls && ($type != 2 || $hittype != 2);
	    $badhit = 1 if $type ==2 && $hittype != 1 && $hittype != 2;
	    $badhit = 1 if $type != 2 && $hittype != $type;
	    if($badhit) {
		return logresults("$summary\n(Hit line: $line\n".
				  "Hit type $hittype doesn't match required type $type (pulser is "
				  .($puls?"ON":"off").")!)\n");
	    }
	} else {
	    return logresults("$summary\n(Hit file check failed: ".
			      "Bad hit type line '$line'!)\n");
	}
    }

    if($type == 1 && !$haveForcedTrig) {
	return logresults("$summary\n(Run type was 1 and did not have any forced triggers)!\n");
    } elsif($type == 2 && !$puls && !$haveForcedTrig) {
	return logresults("$summary\n(Run type was 2, pulser was off, but did not ".
			  "have any heartbeat triggers!)\n");
    } elsif($type == 2 && $puls && $haveForcedTrig) {
	return logresults("$summary\n(Run type was 2, pulser was on, and had ".
			  "heartbeat/forced triggers!)\n");
    }
    return 1;
}

sub docmd {
    my $cmd = shift; die unless defined $cmd;
    print "$cmd\n" if defined $showcmds;
    my $outfile = ".dm$$.".time;
    my $ret;
    if(defined $showcmds) {
	$ret = system "$cmd 2>&1 | tee $outfile";
    } else {
	$ret = system "$cmd &> $outfile";
    }
    if($ret & 127) {
	print "Got signal in subprocess ($ret)!\n";
	exit(1);
    }
    my $rez = `cat $outfile`;
    unlink $outfile; 
    return $rez;
}

sub hadError { my $s = shift; return 1 if ($s =~ /error/i); return 0; }
sub hadWarning { my $s = shift; return 1 if ($s =~ /warning/i); return 0; }
sub printWarning { 
    my $s = shift; 
    $s =~ s/\t//g;
    my $f = shift; 
    print "\nWarning:\n'$s'\n... appeared in monitoring stream $f.\n";
}

sub doShortHitCollection {
    my %args     = @_;
    my $dom      = $args{DOM};         die unless defined $dom;
    my $type     = $args{Trig};        die unless defined $type;
    my $name     = $args{Name};        die unless defined $name;
    my $lcup     = $args{LcUp};        $lcup = 0 unless defined $lcup;
    my $lcdn     = $args{LcDn};        $lcdn = 0 unless defined $lcdn;
    my $dur      = $args{Duration};    $dur  = 4 unless defined $dur;
    my $puls     = $args{DoPulser};    die unless defined $puls;
    my $thresh   = $args{Threshold};   die unless defined $thresh;
    my $dofb     = $args{DoFlasher};   $dofb   = 0  unless defined $dofb;
    my $bright   = $args{FBBright};    $bright = 1  unless defined $bright;
    my $win      = $args{FBWin};       $win    = 10 unless defined $win;
    my $delay    = $args{FBDelay};     $delay  = 0  unless defined $delay;
    my $mask     = $args{FBMask};      $mask   = 1  unless defined $mask;
    my $pulsrate = $args{PulserRate};  # Leave undefined to accept default
    my $compMode = $args{Compression}; # ""
    my $dataFmt  = $args{Format};      # ""
    my $SNDeadT  = $args{SNDeadTime};  # ""
    my $skipRateChk = $args{skipRateChk};

    printc "Collecting $name (trig. type $type) data... ";
    my $engFile = "short_$name"."_$dom.hits";
    my $monFile = "short_$name"."_$dom.moni";
    my $snFile  = "short_$name"."_$dom.sn"; # Only used if SNDeadT given
    unlink $engFile if -e $engFile;
    unlink $monFile if -e $monFile;
    my $mode    = 0;
    if($lcup && $lcdn) {
	$mode = 1;
    } elsif($lcup && !$lcdn) {
	$mode = 2;
    } elsif($lcdn && !$lcup) {
	$mode = 3;
    }
    my $lcstr       = $mode ? "-I $mode,100,100,100,100" : "";
    my $pulserArg   = $puls ? "-p -S$pulserDAC,$pulserAmp" : "";
    my $fmtArg      = (defined $dataFmt) ? "-X $dataFmt" : "";
    my $compArg     = (defined $compMode) ? "-Z $compMode" : "";
    my $threshArg   = "";
    my $snArg       = (defined $SNDeadT) ? "-K 1,0,$SNDeadT,$snFile" : "";
    if(defined $compMode && $compMode == CMP_RG) {
	$threshArg = "-R 100,100,100,100,100";
    }
    my ($pulsrateArg, $runArg);
    if($dofb) {
	$runArg = "-u $bright,$win,$delay,$mask,$pulsrate";
	$pulsrateArg = ""; 
# FIXME: check dacs!
#    my $cmd = "$dat -S0,850 -S1,2300 -S2,350 -S3,2250 -S7,2130 -S14,450"
#	." -H1 -M1 -m $moni -i $hits -d 5 $dom -B $bright,$win,$delay,$mask,$rate"
#	." 2>&1";

    } else {
	$runArg = "-B";
	$pulsrateArg = (defined $pulsrate) ? "-P $pulsrate" : "";
    }
    my $cmd       = "$dat -d $dur $defaultDACs -S$speThreshDAC,$thresh "
	.           " $pulserArg $pulsrateArg $fmtArg $compArg $threshArg $snArg "
	.           "-w 1 -f 1 -H1 -M1 -m $monFile -T $type $runArg -i $engFile $lcstr $dom 2>&1";

    my $result    = docmd $cmd;

    # Tenaciously fetch monitoring stream
    my $moni;
    if(! -f $monFile) {
	$moni = "ERROR: Monitoring file $monFile doesn't exist; DOM hosed?\n";
    } else {
	$moni      = `decodemoni -v $monFile 2>&1`; chomp $moni;
	if($moni eq "") {
	    my $getMoniCmd = "$dat -d 1 -M1 -m last.moni $dom 2>&1";
	    my $result     = docmd $getMoniCmd;
	    if(! -f "last.moni") {
		$moni = "ERROR: Original monitoring stream is empty and "
		    .   "secondary stream is missing; DOM hosed?\n";
	    } else {
		$moni = "[original EMPTY -- following was fetched "
		    .   "from domapp a second time around:]\n"
		    .   $result
		    .   `decodemoni -v last.moni`;
	    }
	}
    }

    my $summary = 
	"Short run $name:\n".
	"Hit file: $engFile\n".
	"Original monitoring file: $monFile\n".
	"Shell command: $cmd\n".
	"Result:\n$result\n\n".
	"Monitoring output:\n$moni\n";
    
    if(hadError $moni) {
	return logresults("$summary\n(Had error or warning in monitoring file $monFile.)\n");
    }
    if($result !~ /Done \((\d+) usec\)\./) {
	return logresults("$summary\n(Did not find terminator ['Done'] string from domapptest)\n");
    }
    if($result =~ /ERROR/) {
	return logresults("$summary\n(Had ERROR in domapptest output)\n");
    }

    for(split '\n', $moni) {
	printWarning($_, $monFile) if hadWarning($_);
    }

    # Check for trigger rate consistency
    if(!$skipRateChk && $dataFmt == 0 && defined $pulsrate) {
	# Look for discriminator trigger if running in pulser mode:
	my $desiredType = $puls ? "Discriminator Trigger" : "CPU Trigger";
	my $nhits   = `/usr/local/bin/decodeeng $engFile 2>&1 | grep "$desiredType" | wc -l`;
	if($nhits =~ /^\s+(\d+)$/ && $1 > 0) {
	    my $nhits = $1;
	    my $ratestr;
            my $evrate = $nhits/$dur;
            if($evrate < $pulsrate/3 || $evrate > $pulsrate*3) {
		return logresults("$summary\n(Measured forced trigger rate ($evrate Hz) ".
				  "doesn't match requested rate ($pulsrate Hz)).\n");
	    } else {
		$desiredType =~ m/(\S*)/;
		printf "($1 trig. rate %2.1f Hz) ", $evrate;
	    }
	} else {
	    return logresults("$summary\n(Didn't get any forced trigger data!)\n");
	}
    }
    # Check for SPE rate consistency if rate is defined and pulser in use:
    if($dataFmt == 0 && defined $pulsrate && $puls) {
	my @moni    = `decodemoni -v $monFile | grep HW`;
	my $spesum = 0;
	my $nspe   = 0;
	for(@moni) {
	    my $spe = (split '\s+')[32];
	    # print "Monitoring string $_ -> $spe\n";
	    $nspe++;
	    $spesum += $spe;
	}
	if($nspe == 0) {
	    return logresults("$summary\n(No HW monitoring records in $monFile!)");
	}
	my $speAvg = $spesum / $nspe;
	if(!$skipRateChk && $speAvg < $pulsrate/3 || $speAvg > $pulsrate*3) {
	    return logresults("$summary\n(Measured SPE discriminator rate ($speAvg Hz) doesn't ".
			      "match requested rate ($pulsrate Hz))!\n");
	}
    }

    my $nhitsline;
    if($dataFmt == 0) {
	$nhitsline = `/usr/local/bin/decodeeng $engFile 2>&1 | grep "time stamp" | wc -l`;
    } elsif($dataFmt == 1) {
	$nhitsline = `/usr/local/bin/decomp $engFile 2>&1 | grep "HIT" | wc -l`;
    } else {
	return logresults("$summary\n(BAD DATA FORMAT!!! ($dataFmt))\n");
    }

    # If asked for, look for supernova data
    my $SNbins        = 0;
    my $SNcountsTotal = 0;
    if(defined $SNDeadT) {
	my @snData = `/usr/local/bin/decodesn $snFile 2>&1`;
	for(@snData) {
	    if(/(\d+) counts/) {
		$SNbins ++;
		$SNcountsTotal += $1;
	    }
	}
	if($SNbins == 0) {
	    return logresults("$summary\n\nSupernova data file $snFile had no timeslice data!\n");
	}
	if($SNcountsTotal < 1) {
	    return logresults("$summary\n\nSupernova data file $snFile had no hits!\n");
	}
    }
    my $SNsummary = (defined $SNDeadT) ? ", $SNbins SN timeslices, $SNcountsTotal SN counts" : "";
    if($nhitsline =~ /^\s+(\d+)$/ && $1 > 0) {
	my $nhits = $1;
	my $ratestr;
	print "OK ($nhits hits$SNsummary).\n";
    } else {
	return logresults("$summary\n(Didn't get any hit data!)\n");
    }

    if($dataFmt == 0) {
	my @typelines = `/usr/local/bin/decodeeng $engFile 2>&1 | grep type`;
	if(!checkEngTrigs($type, 0, $lcup, $lcdn, $puls, $summary, @typelines)) {
	    return 0;
	}
    }
    return 1;
}

sub flasherVersionTest {
    my $dom  = shift;
    printc "Fetching flasher board ID... ";
    my $cmd = "$dat -z $dom 2>&1";
    my $result = docmd $cmd;
    if($result =~ /Flasher board ID is \'(.*?)\'/) {
	if($1 eq "") {
	    return logresults("Flasher board ID was empty.\n");
	} else {
	    return logresults("Got flasher board ID $1.\n");
	}
    } else {
	return logresults("Version string request: didn't get ID ".
			  "(wrong domapp version?  No flasher board attached?)\n".
			  "Session:\n$result\n");
    }
    print "OK.\n";
    return 1;
}

sub flasherTest { 
    my $dom  = shift; die unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
                                Trig        => CPUTRIG,
                                Name        => "Flasher",
                                DoPulser    => 0,
                                Threshold   => 0,
				DoFlasher   => 1,
				PulserRate  => 100,
				FBBright    => 1,
				FBWin       => 10,
				FBDelay     => 0,
				FBMask      => 1,
				Compression => CMP_NONE,
                                Format      => FMT_ENG,
                                skipRateChk => 1);
}

sub filly { my $pat = shift; my @l = split '/', $pat; return $l[-1]; }

sub doMultiplePedestalFetch {
    my $dom = shift; die unless defined $dom;
    printc "Running multiple pedestal fetch test... ";
    my $cmd = "$dat -o $dom 2>&1";
    my $result = docmd $cmd;
    if($result !~ /Done/) {
	print "\nTest failed... fetching monitoring data...\n";
        my $getMoniCmd = "$dat -d 1 -M1 -m last.moni $dom 2>&1";
        my $result     = docmd $getMoniCmd;
	my $moni       = `decodemoni -v last.moni|grep -v HDR`;
        return logresults("Command: $cmd\n".
			  "Result:\n$result\n\n".
			  "Monitoring stream:\n$moni\n");
    }
    print "OK.\n";
}


sub collectDoms {
    print "Available DOMs: ";
    if($doms[0] eq "all") {
	my @iscomstr = 
	    `cat /proc/driver/domhub/card*/pair*/dom*/is-communicating|grep "is communicating"`;
	my $found = 0;
	for(@iscomstr) {
	    if(/Card (\d+) Pair (\d+) DOM (\S+) is communicating/) {
		my $dom = "$1$2$3"; $dom =~ tr/A-Z/a-z/; 
		$card{$dom} = $1;
		$pair{$dom} = $2;
		$aorb{$dom} = $3; $aorb{$dom} =~ tr/A-Z/a-z/;
		print "$dom ";
		$doms[$found] = $dom;
		$found++;
	    }
	}
	mydie "No DOMs are communicating - did you power on?\n"
	    ."(Don't forget to put DOMs in Iceboot after powering on!\n" unless $found;
    } else {
	foreach my $dom (@doms) {
	    if($dom =~ /(\d)(\d)(\w)/) {
		$card{$dom} = $1;
		$pair{$dom} = $2;
		$aorb{$dom} = $3; $aorb{$dom} =~ tr/A-Z/a-z/;
		print "$dom ";
	    } else {
		mydie "Bad dom argument $dom.  $O -h for help.\n";
	    }
	}
    }
    print "\n";
}

sub usage { return <<EOF;
Usage: $O [options] <dom0> <dom1> ...

    DOMs can be \"all\" or, e.g., \"01a, 10b, 31a\"
    Must power on and be in iceboot first.

Options: 
     -u <image>:  Upload <image> rather testing flash image
     -s:          Show commands issued to domapptest
     -d:          Detailed report about what worked, instead
                  of just what didn't work.
     -F:          Run flasher tests (SEALED, DARK DOMs ONLY)
     -V:          Run tests requiring HV (SEALED, DARK DOMs ONLY)
     -A <prog>:   Use <prog> rather than $dat
     -l <name>:   Load FPGA image <name> from flash before test
     -N <loops>:  Iterate <loops> times
     -o:          Perform long duration tests

If -V or -F options are not given, only tests appropriate for a
bare DOM mainboard are given.

EOF
;
}

sub haveLogs {
    my @logs = <dmt????.log>;
    return (@logs>0)?1:0;
}

__END__

