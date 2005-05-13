#!/usr/bin/perl

# upload_and_test.pl
# John Jacobsen, NPX Designs, Inc., jacobsen\@npxdesigns.com
# Started: Sat Nov 20 13:18:25 2004

package MY_PACKAGE;
use strict;
use Getopt::Long;

sub testDOM;
sub mydie { die "FAIL: ".shift; }

sub usage { return <<EOF;
Usage: $0 [options] <dom0> <dom1> ...
Options: 
    -u <image>
    Upload <image> rather than use domapp already in flash.

    -f:    Test flasher board function

    DOMs can be \"all\" or, e.g., \"01a, 10b, 31a\"
    Must power on and be in iceboot first.

EOF
;
}

my $help;
my $image;
my $testflasher;
GetOptions("help|h"          => \$help,
	   "upload|u=s"      => \$image,
	   "testflasher|f"   => \$testflasher) || die usage;

die usage if $help;

my $dat = "/usr/local/bin/domapptest";
mydie "Can't find domapptest program $dat.\n" unless -e $dat;
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

print "$0: Starting tests at ".(scalar localtime)."\n";

foreach my $dom (@doms) {
    mydie "Test of domapp (image ".(defined $image?"$image":"in flash").") on $dom failed!\n"
	unless testDOM($dom);
}

print "$0: SUCCESS at ".(scalar localtime)."\n";

exit;

sub softboot { 
    my $dom = shift;
    print "Softbooting $dom... ";
    my $result = `/usr/local/bin/sb.pl $dom`;
    return 0 if $result !~ /ok/i;
    print "OK.\n";
    return 1;
}

sub upload {
    my $dom = shift;
    my $image = shift;
    print "Uploading $image to $dom... ";
    my $uploadcmd = "/usr/local/bin/upload_domapp.pl $card{$dom} $pair{$dom} $aorb{$dom} $image";
    my $tmpfile = ".tmp_ul_$dom"."_$$";
    system "$uploadcmd 2>&1 > $tmpfile";
    my $result = `cat $tmpfile`;
    unlink $tmpfile || mydie "Can't unlink $tmpfile!\n";
    if($result !~ /Done, sayonara./) {
        print "upload failed: session text:\n$uploadcmd\n\n$result\n\n";
        return 0;
    } else {
        print "OK.\n";
    }
    return 1;
}

sub versionTest {
    my $dom = shift;
    print "Checking version with domapptest... ";
    my $cmd = "$dat -V $dom 2>&1";
    my $result = `$cmd`;
    if($result !~ /DOMApp version is \'(.+?)\'/) {
	print "Version retrieval from domapp failed:\ncommand: $cmd\nresult:\n$result\n\n";
	return 0;
    } else {
	print "OK.  Version is $1.\n";
    } 
    return 1;
}

sub shortEchoTest {
    my $dom = shift;
    print "Performing short domapp echo message test... ";
    my $cmd = "$dat -d2 -E1 $dom 2>&1";
    my $result = `$cmd`;
    if($result =~ /Done \((\d+) usec\)\./) {
	print "OK ($1 usec).\n";
    } else {
	print "Short echo test failed:\n";
	print "Command: $cmd\n";
	print "Result:\n$result\n\n";
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
	my $result = `$cmd`;
	if($result =~ /Done \((\d+) usec\)\./) {
	    print "done ($1 usec)... check contents: ";
	} else {
	    print "Test of monitoring of LC state changes failed:\n";
	    print "Command: $cmd\n";
	    print "Result:\n$result\n\n";
	    return 0;
	}
	my @dmtext = `/usr/local/bin/decodemoni -v $moniFile 2>&1`;
	my $gotwin = 0;
	my $gotmode = 0;
	for(@dmtext) {
# STATE CHANGE: LC WIN <- (100, 100, 100, 100)
	    if(/LC WIN <- \((\d+), (\d+), (\d+), (\d+)\)/) {
		if($1 ne $win0 || $2 ne $win1 || $3 ne $win2 || $4 ne $win3) {
		    print "Window mismatch ($1 vs $win0, $2 vs $win1, $3 vs $win2, $4 vs $win3\n";
		    return 0;
		} else {
		    $gotwin = 1;
		}
	    }
	    if(/LC MODE <- (\d+)/) {
		if($1 ne $mode)  {
		    print "Mode mismatch ($1 vs. $mode).\n";
		    print @dmtext;
		    return 0;
		} else {
		    $gotmode = 1;
		}
	    }
	}
	if(! $gotwin) { 
	    print @dmtext;
	    print "Didn't get monitoring record indicating LC window change!\n";
	    return 0;
	} 
	if(! $gotmode) {
	    print @dmtext;
	    print "Didn't get monitoring record indicating LC mode change!\n";
	    return 0;
	}
	print "OK.\n";
    }
    return 1;
}

sub shortMoniTest {
    my $dom = shift;
    print "Performing short test of monitoring... ";
    my $moniFile = "short_$dom.moni";
    my $cmd = "$dat -d2 -M1 -m $moniFile $dom 2>&1";
    my $result = `$cmd`;
    if($result =~ /Done \((\d+) usec\)\./) {
        print "done ($1 usec)... check contents: ";
    } else {
        print "Short monitoring test failed:\n";
        print "Command: $cmd\n";
        print "Result:\n$result\n\n";
        return 0;
    }
    my $dmtext = `/usr/local/bin/decodemoni -v $moniFile 2>&1`;
    if($dmtext !~ /MONI SELF TEST OK/) {
	print "Test failed: desired monitoring string was not present.\n";
	print "Monitoring output:\n$dmtext\n";
	return 0;
    } else {
	print "OK.\n";
    }
    return 1;
}

sub domappmode { 
    my $dom = shift;
    print "Putting DOM in domapp mode... ";
    my $cmd = "/usr/local/bin/se.pl $dom domapp domapp 2>&1";
    my $result = `$cmd`;
    if($result !~ /SUCCESS/) {
	print "Change state of DOM $dom to domapp failed:\n";
	print "Command: $cmd\n";
	print "Result:\n$result\n\n";
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
		    print "Missing flag in trig line $line!\n";
		    return 0;
		}
	    }
	    # else look for UNKNOWN_TRIG LC_UP_ENA or LC_DN_ENA
	    if($unkn && $flagstr !~ /UNKNOWN_TRIG/) { 
		print "UNKNOWN_TRIG flag required but absent in line $line.\n";
		return 0;
	    }
	    if($lcup && $flagstr !~ /LC_UP_ENA/) {
		print "LC_UP_ENA flag required but absent in line $line.\n";
                return 0;
            }
            if($lcdn && $flagstr !~ /LC_DN_ENA/) {
                print "LC_DN_ENA flag required but absent in line $line.\n";
                return 0;
            }
	    my $hittype = hex($2); 
	    if($hittype != $type) { 
		print "Hit line: $line\n";
		print "Hit type $hittype doesn't match required type $type!\n";
		return 0;
	    }
	} else {
	    print "Bad hit type line '$line'.\n";
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
    print "Command: $cmd\n";
    my $result = `$cmd`;
    if($result =~ /Done \((\d+) usec\)\./) {
        print "done ($1 usec)... check contents: ";
    } else {
        print "Short $name run failed::\n";
        print "Command: $cmd\n";
        print "Result:\n$result\n\n";
        return 0;
    }
    my $numhits = `/usr/local/bin/decodeeng $engFile | grep "time stamp" | wc -l`;
    if($numhits =~ /^\s+(\d+)$/ && $1 > 0) {
	print "OK ($1 hits).\n";
    } else {
	print "Didn't get any hit data - check $engFile.\n";
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
    my $result = `$cmd 2>&1`;
    if($result =~ /Flasher board ID is \'(.*?)\'/) {
	if($1 eq "") {
	    print "Flasher board ID was empty.\n";
	    return 0;
	} else {
	    print "Got flasher board ID $1.\n";
	}
    } else {
	print "Version string request: didn't get ID (wrong domapp version?)\n";
	print "Session:\n$result\n";
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
    print "Command: $cmd\n";
    my $result = `$cmd`;
    print "Result:\n$result";
    return 1;
}

sub testDOM {
# Upload DOM software and test.  Return 1 if success, else 0.
    my $dom = shift;
    return 0 unless softboot($dom);
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
    return 0 unless shortMoniTest($dom);
    return 0 unless LCMoniTest($dom);
    return 0 unless collectTestPatternDataTestNoLC($dom);
    return 0 unless collectCPUTrigDataTestNoLC($dom);
    return 0 unless collectTestPatternDataTestLCUp($dom);
    return 0 unless collectTestPatternDataTestLCDn($dom);
    return 0 unless collectTestPatternDataTestLCUpDn($dom);
    return 1;
}

__END__

