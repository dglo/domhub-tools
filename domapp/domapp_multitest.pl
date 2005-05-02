#!/usr/bin/perl

# upload_and_test.pl
# John Jacobsen, NPX Designs, Inc., jacobsen\@npxdesigns.com
# Started: Sat Nov 20 13:18:25 2004

package MY_PACKAGE;
use strict;
use Getopt::Long;
sub testDOM; sub loadFPGA;
my $failstart = "\n\nFAILURE ------------------------------------------------\n";
my $failend   =     "--------------------------------------------------------\n";
my $lasterr;
sub mydie { die $failstart.shift().$failend; }

sub usage { return <<EOF;
Usage: $0 [options] <dom0> <dom1> ...
Options: 
    -u <image>:  Upload <image> rather testing flash image
    -f:          Test flasher board function
    -s:          Show commands issued to domapptest
    -d:          Detailed report about what worked, instead
                 of just what didn't work.
    -l <name>:   Load FPGA image <name> from flash before test
    DOMs can be \"all\" or, e.g., \"01a, 10b, 31a\"
    Must power on and be in iceboot first.
EOF
;
}

my ($help, $image, $testflasher, $showcmds, $loadfpga, $detailed);
GetOptions("help|h"          => \$help,
	   "upload|u=s"      => \$image,
	   "showcmds|s"      => \$showcmds,
           "detailed|d"      => \$detailed,
	   "loadfpga|l=s"    => \$loadfpga,
	   "testflasher|f"   => \$testflasher) || die usage;

die usage if $help;

my $dat = "/usr/local/bin/domapptest";
die "Can't find domapptest program $dat.\n" unless -e $dat;
my @doms   = @ARGV;
if(@doms == 0) { $doms[0] = "all"; }

if(defined $image) {
    mydie "Can't find domapp image (\"$image\")!  $0 -h for help.\n"
	unless -f $image;
}

my %card;
my %pair;
my %aorb;

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
	    mydie "Bad dom argument $dom.  $0 -h for help.\n";
	}
    }
}
print "\n";

# implement serially now, but think about parallelizing later

print "Starting tests at '".(scalar localtime)."'\n";

foreach my $dom (@doms) {
    mydie "Test of domapp (image ".(defined $image?"$image":"in flash").") on $dom failed!\n"
	."$lasterr" unless testDOM($dom);
}

print "$0: SUCCESS at ".(scalar localtime)."\n";

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
    if(defined $testflasher) {
	return 0 unless flasherVersionTest($dom);
	return 0 unless flasherTest($dom);
	return 1;
    }
    return 0 unless shortEchoTest($dom);
    return 0 unless asciiMoniTest($dom);
    return 0 unless swConfigMoniTest($dom);
    return 0 unless hwConfigMoniTest($dom);
    return 0 unless LCMoniTest($dom);
    return 1;
    return 0 unless collectTestPatternDataTestNoLC($dom);
    return 0 unless collectCPUTrigDataTestNoLC($dom);
    return 0 unless collectTestPatternDataTestLCUp($dom);
    return 0 unless collectTestPatternDataTestLCDn($dom);
    return 0 unless collectTestPatternDataTestLCUpDn($dom);
    return 1;
}



sub softboot { 
    my $dom = shift;
    print "Softbooting $dom... ";
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
    print "Loading FPGA $fpga from flash on DOM $dom... ";
    my $se = "/usr/local/bin/se.pl"; die "Can't find $se!\n" unless -e $se;
    my $loadcmd = "$se $dom s\\\"\\\ $fpga\\\"\\\ find\\\ if\\\ fpga\\\ endif"
	." s\\\"\\\ $fpga\\\"\\\ find\\\ if\\\ fpga\\\ endif";
    my $result = `$loadcmd 2>&1`;
    if($result =~ /SUCCESS/) { 
        my $details = $detailed?" (se.pl script reported success)":"";
        print "OK$details.\n";
    } else {
	$lasterr = "Load of FPGA file failed.  Transcript:\n$result\n";
	return 0;
    }
    return 1;
}

sub upload {
    my $dom = shift;
    my $image = shift;
    print "Uploading $image to $dom...\n";
    my $uploadcmd = "/usr/local/bin/upload_domapp.pl $card{$dom} $pair{$dom} $aorb{$dom} $image";
    my $tmpfile = ".tmp_ul_$dom"."_$$";
    system "$uploadcmd 2>&1 > $tmpfile";
    my $result = `cat $tmpfile`;
    unlink $tmpfile || mydie "Can't unlink $tmpfile: $!\n";
    if($result !~ /Done, sayonara./) {
        print "upload failed: session text:\n$uploadcmd\n\n$result\n\n";
        return 0;
    } else {
	my $details = $detailed?" (upload_domapp.pl script reported success)":"";
	print "OK$details.\n";
    }
    return 1;
}

sub versionTest {
    my $dom = shift;
    print "Checking version with domapptest... ";
    my $cmd = "$dat -V $dom 2>&1";
    print "$cmd\n" if defined $showcmds;
    my $result = `$cmd`;
    if($result !~ /DOMApp version is \'(.+?)\'/) {
	$lasterr = "Version retrieval from domapp failed:\ncommand: $cmd\nresult:\n$result\n\n";
	return 0;
    } else {
        my $details = $detailed?", got good version report from domapptest":"";
	print "OK ('$1'$details).\n";
    } 
    return 1;
}

sub shortEchoTest {
    my $dom = shift;
    print "Performing short domapp echo message test... ";
    my $cmd = "$dat -d2 -E1 $dom 2>&1";
    print "$cmd\n" if defined $showcmds;
    my $result = `$cmd`;
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
    print "Testing monitoring reporting of LC state changes...\n";
    my $moniFile = "lc_state_chg_$dom.moni";
    my $win0 = 100;
    my $win1 = 200;
    my $win2 = 300;
    my $win3 = 400;
    foreach my $mode(1..3) {
	print "Mode $mode: ";
	my $cmd = "$dat -d1 -M1 -m $moniFile -I $mode,$win0,$win1,$win2,$win3 $dom 2>&1";
	print "$cmd\n" if defined $showcmds;
	my $result = `$cmd`;
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
    print "Testing ASCII monitoring... ";
    my $moniFile = "ascii_$dom.moni";
    my $cmd = "$dat -d2 -M1 -m $moniFile $dom 2>&1";
    print "$cmd\n" if defined $showcmds;
    my $result = `$cmd`;
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
    } else {
        my $details = $detailed?" (got self test ASCII monitoring record)":"";
        print "OK$details.\n";
    }
    return 1;
}



sub swConfigMoniTest {
    my $dom = shift;
    print "Testing software configuration monitoring... ";
    my $moniFile = "sw_$dom.moni";
    my $cmd = "$dat -d4 -M1 -f 1 -m $moniFile $dom 2>&1";
    print "$cmd\n" if defined $showcmds;
    my $result = `$cmd`;
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
	}
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
    print "Testing hardware configuration monitoring... ";
    my $moniFile = "hw_$dom.moni";
    my $cmd = "$dat -d4 -M1 -w 1 -m $moniFile $dom 2>&1";
    print "$cmd\n" if defined $showcmds;
    my $result = `$cmd`;
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
	    print "\n$_";
	}
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
    print "Putting DOM in domapp mode... ";
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
    my $type = shift;
    my $unkn = shift;
    my $lcup = shift;
    my $lcdn = shift;
    my @typelines = @_;
    
    print "Checking engineering event trigger lines for appropriate type/flags...\n";
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
	    if($hittype != $type) { 
		$lasterr = "Hit line: $line\n".
		    "Hit type $hittype doesn't match required type $type!\n";
		return 0;
	    }
	} else {
	    $lasterr = "Bad hit type line '$line'.\n";
	    return 0;
	}
    }
    return 1;
}

sub doShortHitCollection {
    my $dom  = shift;
    my $type = shift;
    my $name = shift;
    my $lcup = shift;
    my $lcdn = shift;
    print "Collecting $name (trigger type $type) data...\n";
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
    my $lcstr = $mode ? "-I $mode,100,100,100,100" : "";
    my $cmd = "$dat -d2 -H1 -M1 -m $monFile -T $type -B -i $engFile $lcstr $dom 2>&1";
    print "$cmd\n" if defined $showcmds;
    my $result = `$cmd`;
    if($result !~ /Done \((\d+) usec\)\./) {
        $lasterr = "Short $name run failed::\n".
	    "Command: $cmd\n".
	    "Result:\n$result\n\n";
        return 0;
    }
    my $numhits = `/usr/local/bin/decodeeng $engFile | grep "time stamp" | wc -l`;
    if($numhits =~ /^\s+(\d+)$/ && $1 > 0) {
	print "OK ($1 hits).\n";
    } else {
	$lasterr = "Didn't get any hit data - check $engFile.\n";
	return 0;
    }
    my @typelines = `/usr/local/bin/decodeeng $engFile | grep type`;
    return 0 unless checkEngTrigs($type, 0, $lcup, $lcdn, @typelines);
    return 1;
}

sub collectTestPatternDataTestNoLC { 
    my $dom = shift;
    return doShortHitCollection($dom, 0, "testPattern", 0, 0);
}

sub collectCPUTrigDataTestNoLC {
    my $dom = shift;
    return doShortHitCollection($dom, 1, "cpuTrigger", 0, 0);
}

sub collectTestPatternDataTestLCUpDn {
    my $dom = shift;
    return doShortHitCollection($dom, 0, "testPatternLCUpDn", 1, 1);
}

sub collectTestPatternDataTestLCUp {
    my $dom = shift;
    return doShortHitCollection($dom, 0, "testPatternLCUp", 1, 0);
} 

sub collectTestPatternDataTestLCDn {
    my $dom = shift;
    return doShortHitCollection($dom, 0, "testPatternLCDn", 0, 1);
}

sub flasherVersionTest {
    my $dom  = shift;
    my $cmd = "$dat -z $dom";
    print "$cmd\n" if defined $showcmds;
    my $result = `$cmd 2>&1`;
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
    print "$cmd\n" if defined $showcmds;
    my $result = `$cmd`;
    print "Result:\n$result";
    return 1;
}

__END__

