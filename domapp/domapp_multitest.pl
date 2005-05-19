#!/usr/bin/perl

# upload_and_test.pl
# John Jacobsen, NPX Designs, Inc., jacobsen\@npxdesigns.com
# Started: Sat Nov 20 13:18:25 2004

package MY_PACKAGE;
use strict;
use Getopt::Long;
sub testDOM;     sub loadFPGA; sub docmd; sub hadError; sub filly;
sub hadWarning; sub printWarning;
sub printc;  sub delim;


my $failstart = "\n\nFAILURE ------------------------------------------------\n";
my $failend   =     "--------------------------------------------------------\n";
my $lasterr;
my $O            = filly $0;
my $msgcols      = 52;
my $speThreshDAC = 9;
my $speThresh    = 600;
my $pulserDAC    = 11;
my $pulserAmp    = 500;
my $defaultDACS  = "-S0,850 -S1,2097 -S2,600 -S3,2048 "
    .              "-S4,850 -S5,2097 -S6,600 -S7,1925 "
    .              "-S10,700 -S13,800 -S14,1023 -S15,1023";
my $dat          = "/usr/local/bin/domapptest";


sub mydie { die $failstart.shift().$failend; }

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

If -V or -F options are not given, only tests appropriate for a
bare DOM mainboard are given.

EOF
;
}

my ($help, $image, $showcmds, $loadfpga, $detailed,
    $dohv, $doflasher);
GetOptions("help|h"          => \$help,
	   "upload|u=s"      => \$image,
	   "showcmds|s"      => \$showcmds,
           "detailed|d"      => \$detailed,
	   "loadfpga|l=s"    => \$loadfpga,
           "dohv|V"          => \$dohv,
           "dat|A=s"         => \$dat,
           "doflasher|F"     => \$doflasher) || die usage;

die usage if $help;

die "Can't find domapptest program $dat.\n" unless -e $dat;
my @doms   = @ARGV;
if(@doms == 0) { $doms[0] = "all"; }

if(defined $image) {
    mydie "Can't find domapp image (\"$image\")!  $O -h for help.\n"
	unless -f $image;
}

my %card;
my %pair;
my %aorb;

print "$O: Starting tests at '".(scalar localtime)."'\n";

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

# implement serially now, but think about parallelizing later

foreach my $dom (@doms) {
    mydie "Test of domapp (image ".(defined $image?"$image":"in flash").") on $dom failed!\n"
	."$lasterr"."$O: FAIL\n\n" unless testDOM($dom);
}

print "\n$O: SUCCESS at '".(scalar localtime)."'\n";

exit;

sub testDOM {
# Upload DOM software and test.  Return 1 if success, else 0.
    my $dom = shift;
    return 0 unless softboot($dom);
    if(defined $loadfpga) {
	return 0 unless loadFPGA($dom, $loadfpga);
    }
    if(defined $image) {
	return 0 unless upload($dom, $image);
    } else {
	return 0 unless domappmode($dom);
    }

    return 0 unless versionTest($dom);
    return 0 unless getDOMIDTest($dom);
    return 0 unless asciiMoniTest($dom);
    return 0 if $dohv && !setHVTest($dom);
    return 0 unless shortEchoTest($dom);
    return 0 unless collectPulserDataTestNoLC($dom);   # Pulser test of SPE triggers
    return 0 unless collectCPUTrigDataTestNoLC($dom);
    return 0 unless collectDiscTrigDataTestNoLC($dom); # Should at least get forced triggers
    printc("Testing variable heartbeat/pulser rate:  \n");
    return 0 unless varyHeartbeatRateTestNoLC($dom);  
    print "SKIPPING collectDiscTrigDataCompressed\n"; # return 0 unless collectDiscTrigDataCompressed($dom);
    return 0 unless swConfigMoniTest($dom);
    return 0 unless hwConfigMoniTest($dom);
    return 0 unless LCMoniTest($dom);

    if(defined $doflasher) {
	return 0 unless flasherVersionTest($dom);
	return 0 unless flasherTest($dom);
    }

    if(defined $dohv) {
	return 0 unless collectDiscTrigDataTestNoLC($dom);
    }

    return 1;
}

use constant CPUTRIG  => 1;
use constant DISCTRIG => 2;
use constant FMT_ENG  => 0;
use constant FMT_RG   => 1;
use constant CMP_NONE => 0;
use constant CMP_RG   => 1;

sub collectCPUTrigDataTestNoLC {
    my $dom = shift;
    return doShortHitCollection($dom, CPUTRIG, "cpuTrigger", 0, 0, 4, 0, 
				0, undef, CMP_NONE, FMT_ENG);
}

sub collectDiscTrigDataTestNoLC {
    my $dom = shift;
    return doShortHitCollection($dom, DISCTRIG, "discTrigger", 0, 0, 4, 0, 
				$speThresh, undef, CMP_NONE, FMT_ENG);
}

sub collectPulserDataTestNoLC {
    my $dom = shift;
    return doShortHitCollection($dom, DISCTRIG, "pulserTrigger", 0, 0, 4, 1, 
				$speThresh, 10, CMP_NONE, FMT_ENG);
}

sub varyHeartbeatRateTestNoLC {
    my $dom       = shift;
    return 0 unless doShortHitCollection($dom, DISCTRIG, "heartbeat_10Hz",  
					 0, 0, 4, 0, $speThresh, 10, CMP_NONE, FMT_ENG);
    return 0 unless doShortHitCollection($dom, DISCTRIG, "heartbeat_100Hz", 
					 0, 0, 4, 0, $speThresh, 100, CMP_NONE, FMT_ENG);
    return 0 unless doShortHitCollection($dom, DISCTRIG, "heartbeat_1Hz",
					 0, 0, 4, 0, $speThresh, 1, CMP_NONE, FMT_ENG);
    return 1;
}

sub collectDiscTrigDataCompressed {
    my $dom = shift;
    return doShortHitCollection($dom, DISCTRIG, "discTrigCompr", 0, 0, 4, 0, 
				$speThresh, 2000, CMP_RG, FMT_RG);
}

sub delim {
    print "-" x ($msgcols+3) . "\n";
}

sub printc {
    my $msg = shift;
    printf "%".$msgcols."s", $msg;
}

sub softboot { 
    my $dom = shift;
    printc "Softbooting $dom... ";
    my $result = `/usr/local/bin/sb.pl $dom`;
    if($result !~ /ok/i) {
	$lasterr = "Softboot result: $result\n";
	return 0;
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
    my $loadcmd = "$se $dom s\\\"\\\ $fpga\\\"\\\ find\\\ if\\\ fpga\\\ endif"
	." s\\\"\\\ $fpga\\\"\\\ find\\\ if\\\ fpga\\\ endif";
    my $result = `$loadcmd 2>&1`;
    if($result =~ /SUCCESS/) { 
        my $details = $detailed?" (se.pl script reported success)":"";
        print "OK$details.\n";
	sleep 1;
    } else {
	$lasterr = "Load of FPGA file failed.  Transcript:\n$result\n";
	return 0;
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
	$lasterr = "Version retrieval from domapp failed:\ncommand: $cmd\nresult:\n$result\n\n";
	return 0;
    } else {
        my $details = $detailed?", got good version report from domapptest":"";
	print "OK ('$1'$details).\n";
    } 
    return 1;
}

sub setHVTest {
    my $dom = shift; die unless defined $dom;
    printc "Testing HV set/get (not really)... ";
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
	$lasterr = "Test of setting HV failed:\n"
	    .      "Command: $cmd\n"
	    .      "Result:\n$result\n\n"
	    .      "Monitoring:\n$moni\n";
	return 0;
    }
    print "OK.";
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
	$lasterr = "Short echo test failed:\n".
	    "Command: $cmd\n".
	    "Result:\n$result\n\n";
	return 0;
    }
    return 1;
}

sub LCMoniTest {
    my $dom = shift;
    printc "Testing monitoring reporting of LC state changes...\n";
    my $moniFile = "lc_state_chg_$dom.moni";
    my $win0 = 100;
    my $win1 = 200;
    my $win2 = 300;
    my $win3 = 400;
    foreach my $mode(1..3) {
	printc "Mode $mode: ";
	my $cmd = "$dat -d1 -M1 -m $moniFile -I $mode,$win0,$win1,$win2,$win3 $dom 2>&1";
	my $result = docmd $cmd;
	if($result !~ /Done \((\d+) usec\)\./) {
	    $lasterr = "Test of monitoring of LC state changes failed:\n".
		"Command: $cmd\n".
		"Result:\n$result\n\n";
	    return 0;
	}

	my @dmtext = `/usr/local/bin/decodemoni -v $moniFile 2>&1`;
	# print @dmtext;
	my $gotwin = 0;
	my $gotmode = 0;
	for(@dmtext) {
	    if(hadError $_) {
		$lasterr = "Test of monitoring of LC state changes failed:\n"
		    ."Had error or warning in monitoring stream!\n".$_;
		return 0;
	    }
	    printWarning($_, $moniFile) if hadWarning $_;
# STATE CHANGE: LC WIN <- (100, 100, 100, 100)
	    if(/LC WIN <- \((\d+), (\d+), (\d+), (\d+)\)/) {
		if($1 ne $win0 || $2 ne $win1 || $3 ne $win2 || $4 ne $win3) {
		    $lasterr =
			"Window mismatch ($1 vs $win0, $2 vs $win1, $3 vs $win2, $4 vs $win3\n";
		    return 0;
		} else {
		    $gotwin = 1;
		}
	    }
	    if(/LC MODE <- (\d+)/) {
		if($1 ne $mode)  {
		    $lasterr = "Mode mismatch ($1 vs. $mode).\n".(join "\n",@dmtext);
		    return 0;
		} else {
		    $gotmode = 1;
		}
	    }
	}
	if(! $gotwin) { 
	    $lasterr = (join "\n", @dmtext).
		"Didn't get monitoring record indicating LC window change!\n";
	    return 0;
	} 
	if(! $gotmode) {
            $lasterr = (join "\n", @dmtext).
		"Didn't get monitoring record indicating LC mode change!\n";
	    return 0;
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
    my $cmd = "$dat -d1 -M1 -m $moniFile $dom 2>&1";
    my $result = docmd $cmd;
    if($result !~ /Done \((\d+) usec\)\./) {
        $lasterr = "Short monitoring test failed:\n".
	    "Command: $cmd\n".
	    "Result:\n$result\n\n";
        return 0;
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
        $lasterr = "DOM ID failed:\ncommand: $cmd\nresult:\n$result\n\n";
        return 0;
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
	$lasterr = "Short software monitoring test failed:\nCommand: $cmd\n".
	    "Result:\n$result\n\n";
        return 0;
    }
    my @dmtext = `/usr/local/bin/decodemoni -v $moniFile 2>&1`;
    my $gotone = 0;
    for(@dmtext) {
	if(/CF EVT/) {
	    $gotone++;
	    # print "\n$_";
	} elsif(hadError $_) {
	    $lasterr = "Monitoring stream had error: $_\n";
	    return 0;
	}
	printWarning($_, $moniFile) if hadWarning($_);
    }
    if($gotone) {
        my $details = $detailed?" (got one or more software config. monitoring recs.)":"";
        print "OK$details.\n";
	return 1;
    } else {
	$lasterr = "No software configuration events found!\n";
	return 0;
    }
}



sub hwConfigMoniTest {
    my $dom = shift;
    printc "Testing hardware configuration monitoring... ";
    my $moniFile = "hw_$dom.moni";
    my $cmd = "$dat -d2 -M1 -w 1 -m $moniFile $dom 2>&1";
    my $result = docmd $cmd;
    if($result !~ /Done \((\d+) usec\)\./) {
	$lasterr = "HW monitoring test failed:\nCommand: $cmd\n".
	    "Result:\n$result\n\n";
        return 0;
    }
    my @dmtext = `/usr/local/bin/decodemoni -v $moniFile 2>&1`;
    my $gotone = 0;
    for(@dmtext) {
	if(/HW EVT/) {
	    $gotone++;
	    # print "\n$_";
	} elsif(hadError $_) {
	    $lasterr = "Have monitoring warning or error!\n$_";
	    return 0;
	}
	printWarning($_, $moniFile) if hadWarning $_;
    }
    if($gotone) {
        my $details = $detailed?" (got one or more hardware config. monitoring recs.)":"";
        print "OK$details.\n";
	return 1;
    } else {
	$lasterr = "No hardware configuration events found!\n";
	return 0;
    }
}



sub domappmode { 
    my $dom = shift;
    printc "Putting DOM in domapp mode... ";
    my $cmd = "/usr/local/bin/se.pl $dom domapp domapp 2>&1";
    my $result = `$cmd`;
    if($result !~ /SUCCESS/) {
	$lasterr = "Change state of DOM $dom to domapp failed.  Result:\n$result\n\n";
        return 0;
    } else {
	print "OK.\n";
    }
    return 1;
}

sub checkEngTrigs {
    my $type = shift; die unless defined $type;
    my $unkn = shift; die unless defined $unkn;
    my $lcup = shift; die unless defined $lcup;
    my $lcdn = shift; die unless defined $lcdn;
    # If pulser is on, should ONLY have SPE triggers:
    my $puls = shift; die unless defined $puls;
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
		    $lasterr = "Missing flag in trig line $line!\n";
		    return 0;
		}
	    }
	    # else look for UNKNOWN_TRIG LC_UP_ENA or LC_DN_ENA
	    if($unkn && $flagstr !~ /UNKNOWN_TRIG/) { 
		$lasterr = "UNKNOWN_TRIG flag required but absent in line $line.\n";
		return 0;
	    }
	    if($lcup && $flagstr !~ /LC_UP_ENA/) {
		$lasterr =  "LC_UP_ENA flag required but absent in line $line.\n";
                return 0;
            }
            if($lcdn && $flagstr !~ /LC_DN_ENA/) {
                $lasterr =  "LC_DN_ENA flag required but absent in line $line.\n";
                return 0;
            }
	    my $hittype = hex($2); 
	    $haveForcedTrig = 1 if $hittype == 1;
	    my $badhit = 0;
	    $badhit = 1 if $puls && ($type != 2 || $hittype != 2);
	    $badhit = 1 if $type ==2 && $hittype != 1 && $hittype != 2;
	    $badhit = 1 if $type != 2 && $hittype != $type;
	    if($badhit) {
		$lasterr = "Hit line: $line\n".
		    "Hit type $hittype doesn't match required type $type (pulser is "
		    .($puls?"ON":"off").")!\n";
		return 0;
	    }
	} else {
	    $lasterr = "Bad hit type line '$line'.\n";
	    return 0;
	}
    }

    if($type == 1 && !$haveForcedTrig) {
	$lasterr = "Run type was 1 and did not have any forced triggers!\n";
	return 0;
    } elsif($type == 2 && !$puls && !$haveForcedTrig) {
	$lasterr = "Run type was 2, pulser was off, but did not have any heartbeat triggers!\n";
	return 0;
    } elsif($type == 2 && $puls && $haveForcedTrig) {
	$lasterr = "Run type was 2, pulser was on, and had heartbeat/forced triggers!\n";
	return 0;
    }
    return 1;
}

sub docmd {
    my $cmd = shift; die unless defined $cmd;
    print "$cmd\n" if defined $showcmds;
    my $outfile = ".dm$$.".time;
    if(defined $showcmds) {
	system "$cmd 2>&1 | tee $outfile";
    } else {
	system "$cmd &> $outfile";
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
    my $dom      = shift; die unless defined $dom;
    my $type     = shift; die unless defined $type;
    my $name     = shift; die unless defined $name;
    my $lcup     = shift; die unless defined $lcup;
    my $lcdn     = shift; die unless defined $lcdn;
    my $dur      = shift; die unless defined $dur;
    my $puls     = shift; die unless defined $puls;
    my $thresh   = shift; die unless defined $thresh;
    my $pulsrate = shift; # Leave undefined to accept default
    my $compMode = shift; # ""
    my $dataFmt  = shift; # ""

    printc "Collecting $name (trigger type $type) data... ";
    my $engFile = "short_$name"."_$dom.hits";
    my $monFile = "short_$name"."_$dom.moni";
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
    my $pulsrateArg = (defined $pulsrate) ? "-P $pulsrate" : "";
    my $fmtArg      = (defined $dataFmt) ? "-X $dataFmt" : "";
    my $compArg     = (defined $compMode) ? "-Z $compMode" : "";
    my $threshArg   = "";
    if(defined $compMode && $compMode == CMP_RG) {
	$threshArg = "-R 100,100,100,100,100";
    }
    my $cmd       = "$dat -d $dur $defaultDACS -S$speThreshDAC,$thresh "
	.           " $pulserArg $pulsrateArg $fmtArg $compArg $threshArg "
	.           "-w 1 -f 1 -H1 -M1 -m $monFile -T $type -B -i $engFile $lcstr $dom 2>&1";

    my $result    = docmd $cmd;
    my $moni      = `decodemoni -v $monFile`; chomp $moni;
    if($moni eq "") {
	my $getMoniCmd = "$dat -d 1 -M1 -m last.moni $dom 2>&1";
	my $result     = docmd $getMoniCmd;
	$moni = "[original EMPTY -- following was fetched from domapp a second time around:]\n"
	    .   $result
	    .   `decodemoni -v last.moni`;
    }
    my $ha        = hadError $moni;
    if(hadError $moni || $result !~ /Done \((\d+) usec\)\./) {
        $lasterr = "Short $name run failed::\n".
	    "Command: $cmd\n".
	    "Result:\n$result\n\n".
	    "Monitoring:\n$moni\n";
	$lasterr .= "(Had error or warning in monitoring file $monFile.)\n"
	    if $ha;
        return 0;
    }
    for(split '\n', $moni) {
	printWarning($_, $monFile) if hadWarning($_);
    }

    # Check for trigger rate consistency
    if($dataFmt == 0 && defined $pulsrate) {
	# Look for discriminator trigger if running in pulser mode:
	my $desiredType = $puls ? "Discriminator Trigger" : "CPU Trigger";
	my $nhits   = `/usr/local/bin/decodeeng $engFile 2>&1 | grep "$desiredType" | wc -l`;
	if($nhits =~ /^\s+(\d+)$/ && $1 > 0) {
	    my $nhits = $1;
	    my $ratestr;
            my $evrate = $nhits/$dur;
            if($evrate < $pulsrate/2.5 || $evrate > $pulsrate*2.5) {
		$lasterr = "Measured forced trigger rate ($evrate Hz) doesn't match requested rate ($pulsrate Hz).\n";
		return 0;
	    } else {
		printf "($desiredType rate %2.2f Hz) ", $evrate;
	    }
	} else {
	    $lasterr = "Didn't get any forced trigger data - check $engFile.\n".
		"Monitoring stream:\n$moni\ndomapptest log:\n$result\n";
	    return 0;
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
	    $lasterr = "No HW monitoring records in $monFile... check $monFile.\n"
		.       "Monitoring stream:\n$moni\ndomapptest log:\n$result\n";
	    return 0;
	}
	my $speAvg = $spesum / $nspe;
	if($speAvg < $pulsrate/2.5 || $speAvg > $pulsrate*2.5) {
	    $lasterr = "Measured SPE discriminator rate ($speAvg Hz) doesn't match requested rate ($pulsrate Hz).\n"
		.      "Monitoring stream:\n$moni\ndomapptest log:\n$result\n";
	    return 0;
	}
    }

    my $nhitsline;
    if($dataFmt == 0) {
	$nhitsline = `/usr/local/bin/decodeeng $engFile 2>&1 | grep "time stamp" | wc -l`;
    } elsif($dataFmt == 1) {
	$nhitsline = `/usr/local/bin/decomp $engFile 2>&1 | grep "HIT" | wc -l`;
    } else {
	$lasterr = "BAD DATA FORMAT!!! ($dataFmt)\n";
	return 0;
    }

    if($nhitsline =~ /^\s+(\d+)$/ && $1 > 0) {
	my $nhits = $1;
	my $ratestr;
	print "OK ($nhits hits).\n";
    } else {
	$lasterr = "Didn't get any hit data - check $engFile.\n".
	    "Monitoring stream:\n$moni\ndomapptest log:\n$result\n";
	return 0;
    }

    if($dataFmt == 0) {
	my @typelines = `/usr/local/bin/decodeeng $engFile 2>&1 | grep type`;
	if(!checkEngTrigs($type, 0, $lcup, $lcdn, $puls, @typelines)) {
	    $lasterr .= "Engineering event file was $engFile.\n"
		.       "Monitoring was $monFile.\n";
	    return 0;
	}
    }

    return 1;
}

sub flasherVersionTest {
    my $dom  = shift;
    my $cmd = "$dat -z $dom 2>&1";
    my $result = docmd $cmd;
    if($result =~ /Flasher board ID is \'(.*?)\'/) {
	if($1 eq "") {
	    $lasterr = "Flasher board ID was empty.\n";
	    return 0;
	} else {
	    $lasterr = "Got flasher board ID $1.\n";
	}
    } else {
	$lasterr = "Version string request: didn't get ID (wrong domapp version?)\n".
	    "Session:\n$result\n";
	return 0;
    }
    return 1;
}

sub flasherTest { 
    my $dom  = shift;
    my $moni = "flasher_$dom.moni";
    my $hits = "flasher_$dom.hits";
    my $bright = 1;
    my $win    = 10;
    my $delay  = 0;
    my $mask   = 1;
    my $rate   = 1;
    my $cmd = "$dat -S0,850 -S1,2300 -S2,350 -S3,2250 -S7,2130 -S14,450"
	." -H1 -M1 -m $moni -i $hits -d 5 -B $dom -Z $bright,$win,$delay,$mask,$rate"
	." 2>&1";
    my $result = docmd $cmd;
    print "Result:\n$result";
    return 1;
}

sub filly { my $pat = shift; my @l = split '/', $pat; return $l[-1]; }
__END__

