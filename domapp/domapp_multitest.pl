#!/usr/bin/perl

# John Jacobsen, NPX Designs, Inc., jacobsen\@npxdesigns.com
# Started: Sat Nov 20 13:18:25 2004
# $Id: domapp_multitest.pl,v 1.33 2005-06-13 21:51:29 jacobsen Exp $

package DOMAPP_MULTITEST;
use strict;
use Getopt::Long;

sub testDOM;     sub loadFPGA;     sub docmd;       sub hadError;      
sub hadWarning;  sub versionTest;  sub mydie;
sub endTests;    sub usage;        sub collectDoms; sub getDOMIDTest;
sub reapKids;    sub killKids;     sub shortEchoTest;                
sub logmsg;      sub logOf;        sub asciiMoniTest;
sub checkProcs;  sub filly;        sub doMultiplePedestalFetch;
sub flasherVersionTest;            sub setHVTest;
sub configMoniTest;                sub flasherTest;
sub collectPulserDataTestNoLC;     sub SNCountsOnly;
sub SNCountsAndHits;               sub collectCPUTrigDataTestNoLC;
sub SNCountsAndHits_noHitReadout;  sub SNCountsAndHits1Hz;
sub SNCountsAndHits_noMoni;        sub SNCountsAndHits4kHz;
sub SNCountsAndHits1Hz_noHitReadout;
sub SNCountsAndHits4kHz_noHitReadout;
sub SNCountsOnly_noReadout;

sub collectDiscTrigDataCompressedForced;
sub collectDiscTrigDataCompressedPulser;
sub collectDiscTrigDataTestNoLC;
sub LCMoniTest;
sub varyHeartbeatRateTestNoLC;

sub sigged { reapKids; die "Got signal, bye bye.\n"; }
$SIG{INT} = $SIG{KILL} = \&sigged;
    
my $logfile      = "UNASSIGNED.log";
my $O            = filly $0;
my $msgcols      = 50;
my $speThreshDAC = 9;
my $speThresh    = 600;
my $pulserDAC    = 11;
my $pulserAmp    = 500;
my $defaultdur   = 10; # Does all tests at least once
my $duration     = $defaultdur;
my $dorandom     = 0;
my $defaultDACs  = "-S0,850 -S1,2097 -S2,600 -S3,2048 "
    .              "-S4,850 -S5,2097 -S6,600 -S7,1925 "
    .              "-S10,700 -S13,800 -S14,1023 -S15,1023";
my $dat          = "/usr/local/bin/domapptest";
    
my ($help, $image, $showcmds, $loadfpga, $detailed,
    $dohv, $doflasher, $dolong, $rmlogs, $compOnly);
my $snmode       = 4;
my $datDuration  = 4;


GetOptions("help|h"          => \$help,
	   "upload|u=s"      => \$image,
	   "s"               => \$showcmds,
           "dolong|o"        => \$dolong,
           "detailed|d"      => \$detailed,
	   "loadfpga|l=s"    => \$loadfpga,
           "dohv|V"          => \$dohv,
           "dat|A=s"         => \$dat,
	   "duration|t=i"    => \$duration,
	   "x=i"             => \$datDuration,
	   "R"               => \$dorandom,
	   "componly|C"      => \$compOnly,
	   "sn=i"            => \$snmode,
           "doflasher|F"     => \$doflasher) || die usage;

die usage if $help;
die usage if $snmode < 0 || $snmode > 5;

die "Can't find domapptest program $dat.\n" unless -e $dat;

if(defined $image) {
    die "Can't find domapp image (\"$image\")!  $O -h for help.\n"
	unless -f $image;
}


my %card;
my %pair;
my %aorb;
my $iter;
my $fail = 0;
my $nt   = 0;
my @doms = @ARGV;
if(@doms == 0) { $doms[0] = "all"; }

collectDoms;

foreach my $dom (@doms) {
    my $log = logOf($dom);
    if(-f $log) {
	if($rmlogs) {
	    unlink $log || die "Can't unlink $log: $!\n";
	} else {
	    die "Log file for DOM $dom exists ($log); remove it or use -r option.\n";
	}
    }
    print "Log for $dom is $log\n";
}

checkProcs;

my ($sec,$min,$hr,$mday,$mon,$yr,$wday,$yday,$isdst) = localtime;
$yr += 1900;
$mon++;
my $ts = sprintf("$yr-%02d-%02d__%02d:%02d:%02d", $mon, $mday, $hr, $min, $sec);
my $testdir = "DMT__$ts";
my $logfile = "DMT.out";

print "Creating $testdir... ";
mkdir $testdir || die "Can't create $testdir: $!\n";
print "OK.\n";
print "Creating symlink latest_dmt to $testdir... ";
if(-e "latest_dmt") {
    unlink "latest_dmt" || die "Can't unlink existing latest_dmt: $!\n";
}
symlink($testdir, "latest_dmt")
    || die "Can't symlink $testdir"."->latest_dmt: $!.\n";

chdir $testdir || die "Can't chdir $testdir: $!\n";

open LOG, ">$logfile" || die "Can't open $logfile: $!\n";
my $ofh = select(LOG); $| = 1; select $ofh;

print "\nResults to appear in directory $testdir\n\n";

my $kid = fork;
mydie "Backgrounding fork failed!\n" unless defined $kid;
if($kid) {
    print LOG "Test sequence $testdir\n\n";
    print LOG "Parameters:\n";
    print LOG "DoLong         = ".($dolong?"TRUE":"false")."\n";
    print LOG "FPGA           = ".(defined $loadfpga?"$loadfpga":"flash default")."\n";
    print LOG "Test Pgm       = $dat\n";
    print LOG "Total duration = $duration sec.\n";
    print LOG "Test durations = $datDuration sec.\n";
    print LOG "DoRandomize    = ".($dorandom?"TRUE":"false")."\n";
    print LOG "DoHV           = ".($dohv?"TRUE":"false")."\n";
    print LOG "DoFlasher      = ".($doflasher?"TRUE":"false")."\n";
    print LOG "Compr. only    = ".($compOnly?"TRUE":"false")."\n";
    print LOG "SN mode        = $snmode\n";
    print LOG "Tests running in background.... come back in $duration seconds!\n";
    exit;
}

my %kidproc;
my $haveErr=0;
foreach my $dom (@doms) {
    $kidproc{$dom} = fork;
    if(!defined $kidproc{$dom}) {
	print LOG "ERROR: fork for DOM $dom failed!\n";
	$haveErr = 1;
	last;
    }
    if($kidproc{$dom} == 0) { # I'm the kid! 
	$logfile = logOf $dom;
	unlink($logfile) if -e $logfile;
	$SIG{INT} = $SIG{KILL} = sub { logmsg "signal\n"; exit; };
	testDOM($dom, $duration);
	exit;
    }
}

if($haveErr) {
    reapKids;
    mydie "FAIL: Quitting due to failed fork.\n";
}

reapKids;
my $haveFAIL = 0;
foreach my $dom (@doms) {
    my $domlog = logOf $dom;
    my $tail = `tail -1 $domlog`; chomp $tail;
    if($tail !~ /ending tests/) {
	print LOG "Did not find termination string in $domlog: '$tail'.\n";
	$haveFAIL++;
	next;
    }
    print LOG "$dom ($domlog): $tail\n";
    if($tail =~ /\s+(\d+) failures/) {
	$haveFAIL++ unless $1 == 0;
    } else {
	$haveFAIL++;
    }
}

if($haveFAIL) {
    print LOG "$O: FAIL.\n";
    system "touch FAIL";
} else {
    print LOG "$O: SUCCESS.\n";
    system "touch SUCCESS\n";
}

exit;

######################################################################

sub endTests { 
    if($fail) {
	print "domapp_multitest: FAIL ($fail out of $nt tests)\n";
    } else {
	print "domapp_multitest: SUCCESS (all $nt tests passed)\n";
    }
    exit;
}

sub resetState {
    my $dom = shift;
    return 0 unless(softboot($dom));
    if(defined $loadfpga) {
        return 0 unless loadFPGA($dom, $loadfpga);
    }
    if(defined $image) {
        return 0 unless(upload($dom, $image));
    } else {
        return 0 unless domappmode($dom);
	sleep 4; # Should let FPGA reload before doing anything else
    }
}

sub testDOM {
# Upload DOM software and test.  Return 1 if success, else 0.
    my $dom  = shift;
   
    return 0 unless resetState $dom;

    # Start tests in fixed order, then randomize if desired
    my @tests;
    if($compOnly) {
	push(@tests, sub { collectDiscTrigDataCompressedForced($dom);});
	push(@tests, sub { collectDiscTrigDataCompressedPulser($dom);});
    } elsif($snmode == 1) {
#	push(@tests, sub { SNCountsOnly($dom);                       });
	push(@tests, sub { SNCountsOnlyDoMoni($dom);                 });
    } elsif($snmode == 2) {
	push(@tests, sub { SNCountsAndHits($dom);                    });
    } elsif($snmode == 3) {
	push(@tests, sub { SNCountsOnly($dom);                       });
        push(@tests, sub { SNCountsAndHits($dom);                    });
    } elsif($snmode == 6) {
        push(@tests, sub { SNCountsOnly_noReadout($dom);             });
	push(@tests, sub { resetState($dom);                         });
    } elsif($snmode == 5) {
        push(@tests, sub { SNCountsOnly_noReadout($dom);             });
        push(@tests, sub { SNCountsOnly($dom);                       });
	push(@tests, sub { SNCountsAndHits1Hz_noHitReadout($dom);    });
	push(@tests, sub { SNCountsAndHits1Hz($dom);                 });
	push(@tests, sub { SNCountsAndHits_noReadoutNoMoni($dom);    });
	push(@tests, sub { SNCountsAndHits_noHitReadout($dom);       });
	push(@tests, sub { SNCountsAndHits_noReadout($dom);          });
	push(@tests, sub { SNCountsAndHits_noMoni($dom);             });
        push(@tests, sub { SNCountsAndHits($dom);                    });
	push(@tests, sub { SNCountsAndHits4kHz_noHitReadout($dom);   });
	push(@tests, sub { SNCountsAndHits4kHz($dom);                });
	push(@tests, sub { resetState($dom);                         });
    } else {
	push(@tests, sub { versionTest $dom;                         });
	push(@tests, sub { getDOMIDTest($dom);                       });
	push(@tests, sub { doMultiplePedestalFetch($dom)             }) if $dolong;
	push(@tests, sub { flasherVersionTest($dom)                  }) if $doflasher;
	push(@tests, sub { setHVTest($dom)                           }) if $dohv;
	push(@tests, sub { shortEchoTest($dom);                      });
	push(@tests, sub { configMoniTest($dom, "CF");               });
	push(@tests, sub { configMoniTest($dom, "HW");               });
	push(@tests, sub { flasherTest($dom)                         }) if $doflasher;
	push(@tests, sub { SNCountsOnly($dom);                       }) unless $snmode == 0;
	push(@tests, sub { SNCountsAndHits($dom);                    }) unless $snmode == 0;
	push(@tests, sub { collectPulserDataTestNoLC($dom);          });
	push(@tests, sub { collectCPUTrigDataTestNoLC($dom);         });
	push(@tests, sub { collectDiscTrigDataCompressedForced($dom);});
	push(@tests, sub { collectDiscTrigDataCompressedPulser($dom);});
	push(@tests, sub { collectDiscTrigDataTestNoLC($dom);        });
	push(@tests, sub { LCMoniTest($dom, 1);                      });
	push(@tests, sub { LCMoniTest($dom, 2);                      });
	push(@tests, sub { LCMoniTest($dom, 3);                      });
	push(@tests, sub { varyHeartbeatRateTestNoLC($dom, 10);      });
	push(@tests, sub { varyHeartbeatRateTestNoLC($dom, 100);     });
	push(@tests, sub { varyHeartbeatRateTestNoLC($dom, 1);       });
	# push(@tests, sub { resetState $dom;                          });
    }
    # Sequential
    my $t0 = time;
    my $n  = 0;
    my $nf = 0;
    for(@tests) {
	$n++;
	$nf++ unless &$_;
    }
    # Random
    while(time-$t0 < $duration) {
	if($dorandom) {
	    my $itest = int(rand((scalar @tests)+1));
	    if($itest > (scalar @tests)-1) { $itest = (scalar @tests)-1; }
	    my $test = $tests[$itest];
	    $n++;
	    $nf++ unless &$test;
	} else {
	    for(@tests) {
		$n++;
		$nf++ unless &$_;
	    }
	}
    }
    logmsg("ending tests, $n total, $nf failures.\n");
}

use constant CPUTRIG  => 1;
use constant DISCTRIG => 2;
use constant FMT_ENG  => 0;
use constant FMT_RG   => 1;
use constant CMP_NONE => 0;
use constant CMP_RG   => 1;

sub SNCountsOnly {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    my $snfile = "SNCounts_$dom.sn";
    my $testname = "sn-counts-only";
    my $cmd = "$dat $defaultDACs -d $datDuration -p -P 500 -K 1,0,6400,$snfile -T 2 $dom 2>&1";
    my $result = docmd $cmd;
    if($result =~ /ERROR/) {
	return logmsg "$testname FAIL: domapptest error\n$result\n";
    } 
    if($result !~ /Done \((\d+) usec\)\./) {
	return logmsg "$testname FAIL: domapptest error\n$result\n";
    }
    my $details = $detailed?"(domapptest finished)":"";
    logmsg "$testname $details\n";
    return 1;
}

sub SNCountsOnlyDoMoni {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    my $snfile = "SNCountsMoni_$dom.sn";
    my $testname = "sn-counts-only-domoni";
    my $monFile  = "SNCountsMoni_$dom.moni";
    my $cmd = "$dat $defaultDACs -d $datDuration -p -P 500 -m $monFile -w 1 -f 1 -M1 "
	.     "-K 1,0,6400,$snfile -T 2 $dom 2>&1";
    my $result = docmd $cmd;
    if($result =~ /ERROR/) {
	return logmsg "$testname FAIL: domapptest error\n$result\n";
    } 
    if($result !~ /Done \((\d+) usec\)\./) {
	return logmsg "$testname FAIL: domapptest error\n$result\n";
    }
    my $details = $detailed?"(domapptest finished)":"";
    logmsg "$testname $details\n";
    return 1;
}


sub SNCountsOnly_noReadout {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    my $testname = "sn-counts-only-noread";
    my $snfile = "SNCounts_$dom.sn";
    my $cmd = "$dat $defaultDACs -d $datDuration -p -P 500 -K 0,0,6400,$snfile -T 2 $dom 2>&1";
    my $result = docmd $cmd;
    if($result =~ /ERROR/) {
	return logmsg "$testname FAIL: domapptest error\n$result\n";
    } 
    if($result !~ /Done \((\d+) usec\)\./) {
	return logmsg "$testname FAIL: domapptest error\n$result\n";
    }
    my $details = $detailed?"(domapptest finished)":"";
    logmsg "$testname $details\n";
    return 1;
}

sub SNCountsAndHits {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
                                Trig        => DISCTRIG,
                                Name        => "SNTrigger",
				Duration    => $datDuration,
                                DoPulser    => 1,
				Threshold   => $speThresh,
                                PulserRate  => 500,
                                Compression => CMP_NONE,
                                Format      => FMT_ENG,
                                doSN        => 1,
                                SNDeadTime  => 6400,
                                skipRateChk => 1);
}


sub SNCountsAndHits1Hz {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
                                Trig        => DISCTRIG,
                                Name        => "SNTrigger1Hz",
				Duration    => $datDuration,
                                DoPulser    => 1,
				Threshold   => $speThresh,
                                PulserRate  => 1,
                                Compression => CMP_NONE,
                                Format      => FMT_ENG,
                                doSN        => 1,
                                SNDeadTime  => 6400,
                                skipRateChk => 1);
}


sub SNCountsAndHits4kHz {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
                                Trig        => DISCTRIG,
                                Name        => "SNTrigger4kHz",
				Duration    => $datDuration,
                                DoPulser    => 1,
				Threshold   => $speThresh,
                                PulserRate  => 4000,
                                Compression => CMP_NONE,
                                Format      => FMT_ENG,
                                doSN        => 1,
                                SNDeadTime  => 6400,
                                skipRateChk => 1);
}



sub SNCountsAndHits1Hz_noHitReadout {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
                                Trig        => DISCTRIG,
                                Name        => "SNTrigger1HzNoHits",
				Duration    => $datDuration,
                                DoPulser    => 1,
				Threshold   => $speThresh,
                                PulserRate  => 1,
                                Compression => CMP_NONE,
                                Format      => FMT_ENG,
                                doSN        => 1,
                                SNDeadTime  => 6400,
                                HitFreq     => 0,
                                skipRateChk => 1);
}


sub SNCountsAndHits4kHz_noHitReadout {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
                                Trig        => DISCTRIG,
                                Name        => "SNTrigger4kHzNoHits",
				Duration    => $datDuration,
                                DoPulser    => 1,
				Threshold   => $speThresh,
                                PulserRate  => 4000,
                                Compression => CMP_NONE,
                                Format      => FMT_ENG,
                                doSN        => 1,
                                SNDeadTime  => 6400,
                                HitFreq     => 0,
                                skipRateChk => 1);
}

sub SNCountsAndHits_noReadout {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
                                Trig        => DISCTRIG,
                                Name        => "SNTriggerNoReadNoCnts",
				Duration    => $datDuration,
                                DoPulser    => 1,
				Threshold   => $speThresh,
                                PulserRate  => 500,
                                Compression => CMP_NONE,
                                Format      => FMT_ENG,
                                doSN        => 1,
                                SNDeadTime  => 6400,
                                HitFreq     => 0,
                                CountFreq   => 0,
                                skipRateChk => 1);
}


sub SNCountsAndHits_noReadoutNoMoni {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
                                Trig        => DISCTRIG,
                                Name        => "SNTriggerNoReadNoMoni",
				Duration    => $datDuration,
                                DoPulser    => 1,
				Threshold   => $speThresh,
                                PulserRate  => 500,
                                Compression => CMP_NONE,
                                Format      => FMT_ENG,
                                doSN        => 1,
                                SNDeadTime  => 6400,
                                HitFreq     => 0,
                                CountFreq   => 0,
                                MoniFreq    => 0,
                                skipRateChk => 1);
}


sub SNCountsAndHits_noMoni {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
                                Trig        => DISCTRIG,
                                Name        => "SNTriggerNoMoni",
				Duration    => $datDuration,
                                DoPulser    => 1,
				Threshold   => $speThresh,
                                PulserRate  => 500,
                                Compression => CMP_NONE,
                                Format      => FMT_ENG,
                                doSN        => 1,
                                SNDeadTime  => 6400,
                                MoniFreq    => 0,
                                skipRateChk => 1);
}


sub SNCountsAndHits_noHitReadout {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
                                Trig        => DISCTRIG,
                                Name        => "SNTriggerNoReadHits",
				Duration    => $datDuration,
                                DoPulser    => 1,
				Threshold   => $speThresh,
                                PulserRate  => 500,
                                Compression => CMP_NONE,
                                Format      => FMT_ENG,
                                doSN        => 1,
                                SNDeadTime  => 6400,
                                HitFreq     => 0,
                                skipRateChk => 1);
}



sub SNCountsAndHits_noCountReadout {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
                                Trig        => DISCTRIG,
                                Name        => "SNTriggerNoCounts",
				Duration    => $datDuration,
                                DoPulser    => 1,
				Threshold   => $speThresh,
                                PulserRate  => 500,
                                Compression => CMP_NONE,
                                Format      => FMT_ENG,
                                doSN        => 1,
                                SNDeadTime  => 6400,
                                HitFreq     => 1,
                                CountFreq   => 0,
                                skipRateChk => 1);
}


sub collectCPUTrigDataTestNoLC {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    return doShortHitCollection(DOM         => $dom, 
				Trig        => CPUTRIG,
				Name        => "cpuTrigger", 
				Duration    => $datDuration,
				DoPulser    => 0,
				Threshold   => 0, 
				PulserRate  => 1,
				Compression => CMP_NONE,
				Format      => FMT_ENG);
}

sub collectDiscTrigDataTestNoLC {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
                                Trig        => DISCTRIG,
                                Name        => "discTrigger",
				Duration    => $datDuration,
                                DoPulser    => 0,
                                Threshold   => $speThresh,
                                PulserRate  => 1,
                                Compression => CMP_NONE,
                                Format      => FMT_ENG);
}

sub collectPulserDataTestNoLC {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
                                Trig        => DISCTRIG,
                                Name        => "pulserTrigger",
				Duration    => $datDuration,
                                DoPulser    => 1,
                                Threshold   => $speThresh,
                                PulserRate  => 10,
                                Compression => CMP_NONE,
                                Format      => FMT_ENG);
}

sub varyHeartbeatRateTestNoLC {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    my $rate = shift; mydie("missing arg") unless defined $rate;
    return doShortHitCollection(DOM         => $dom,
				Trig        => DISCTRIG,
				Name        => "heartbeat_".$rate."Hz",
				Duration    => $datDuration,
				DoPulser    => 0,
				Threshold   => $speThresh,
				PulserRate  => $rate,
				Compression => CMP_NONE,
				Format      => FMT_ENG);
}

sub collectDiscTrigDataCompressedForced {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
				Trig        => DISCTRIG,
				Name        => "comprForced",
				Duration    => $datDuration,
				DoPulser    => 0,
				Threshold   => $speThresh,
				PulserRate  => 2000,
				Compression => CMP_RG,
				Format      => FMT_RG);
}

sub collectDiscTrigDataCompressedPulser {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
				Trig        => DISCTRIG,
				Name        => "comprPulsr",
				Duration    => $datDuration,
				DoPulser    => 1,
				Threshold   => $speThresh,
				PulserRate  => 2000,
				Compression => CMP_RG,
				Format      => FMT_RG);
}

sub softboot { 
    my $dom = shift;
    my $result = `/usr/local/bin/sb.pl $dom`;
    if($result !~ /ok/i) {
	return logmsg("softboot FAIL: $result\n");
    }
    my $details = $detailed?" (driver said softboot worked)":"";
    logmsg "softboot $details\n";
    return 1;
}

sub loadFPGA {
    my $dom  = shift || mydie;
    my $fpga = shift || mydie;
    my $se = "/usr/local/bin/se.pl"; mydie "Can't find $se!\n" unless -e $se;
    my $loadcmd = "$se $dom "
	.         "s\\\"\\\ $fpga\\\"\\\ find\\\ if\\\ fpga\\\ endif "
	.         "s\\\"\\\ $fpga\\\"\\\ find\\\ if\\\ fpga\\\ endif.+?\\>";
    my $result = docmd $loadcmd;
    if($result =~ /SUCCESS/) { 
        my $details = $detailed?" (se.pl script reported success)":"";
	logmsg "FPGA load $fpga $details\n";
    } else {
	return logmsg "FPGA load $fpga FAIL: $result\n";
    }
    return 1;
}

sub upload {
    my $dom = shift;   mydie("missing arg") unless defined $dom;
    my $image = shift; mydie("missing arg") unless defined $image;
    my $f = filly $image;
    my $uploadcmd = "/usr/local/bin/upload_domapp.pl $card{$dom} $pair{$dom} $aorb{$dom} $image";
    my $tmpfile = ".tmp_ul_$dom"."_$$";
    system "$uploadcmd 2>&1 > $tmpfile";
    my $result = `cat $tmpfile`;
    unlink $tmpfile || mydie "Can't unlink $tmpfile: $!\n";
    if($result !~ /SUCCESS/) {
        logmsg "upload $f: FAIL: $uploadcmd\n\n$result\n\n";
        return 0;
    } else {
	my $details = $detailed?" (upload_domapp.pl script reported success)":"";
	logmsg "upload $f $details\n";
    }
    return 1;
}

sub versionTest {
    my $dom = shift;
    my $cmd = "$dat -V $dom 2>&1";
    my $result = docmd $cmd;
    if($result !~ /DOMApp version is \'(.+?)\'/) {
	return logmsg "version FAIL: $cmd\nresult:\n$result\n\n";
    } else {
        my $details = $detailed?"(got good version report from domapptest)":"";
	logmsg "version '$1' $details\n";
    } 
    return 1;
}

sub setHVTest {
    my $dom = shift; mydie("missing arg") unless defined $dom;
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
	return logmsg("hv FAIL: ".
		      "Command: $cmd\n".
		      "Result:\n$result\n\n".
		      "Monitoring:\n$moni\n");
    }
    my $details = $detailed?", ":"(HV set/get requests worked; set value matched get value)";
    logmsg "hv $details\n";
    return 1;
}

sub shortEchoTest {
    my $dom = shift;
    my $cmd = "$dat -d$datDuration -E1 $dom 2>&1";
    my $result = docmd $cmd;
    if($result !~ /Done \((\d+) usec\)\./) {        
	return logmsg "echo FAIL: $cmd\n$result\n";
    }
    my $details = $detailed?"(domapptest reported success)":"";
    logmsg "echo $details\n";
    return 1;
}

sub LCMoniTest {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    my $mode = shift; mydie("missing arg") unless defined $mode;
    my $win0 = 100;
    my $win1 = 200;
    my $moniFile = "lc_state_chg_mode$mode"."_$dom.moni";
    my $cmd = "$dat -G -d2 -M1 -m $moniFile -I $mode,$win0,$win1 $dom 2>&1";
    my $result = docmd $cmd;
    if($result !~ /Done \((\d+) usec\)\./) {
	return logmsg "moni state chg. ($mode) FAIL: domapptest error $_\n"
	    .         "Command: $cmd\n"
	    .         "Result:\n$result\n";
    }
    my @dmtext = `/usr/local/bin/decodemoni -v $moniFile 2>&1`;
    # print @dmtext;
    my $gotwin = 0;
    my $gotmode = 0;
    for(@dmtext) {
	if(hadError $_ || hadWarning $_) {
	    return logmsg "moni state chg. ($mode) FAIL: moni error $_\n";
	}
# STATE CHANGE: LC WIN <- (100, 100)
	if(/LC WIN <- \((\d+), (\d+)\)/) {
	    if($1 ne $win0 || $2 ne $win1) {
		return logmsg "moni state chg. ($mode) FAIL: "
		    .         "window mismatch ($1 vs $win0, $2 vs $win1); "
		    .          "Line: $_ File: $moniFile\n";
	    } else {
		$gotwin = 1;
	    }
	}
	if(/LC MODE <- (\d+)/) {
	    if($1 eq $mode)  {
		$gotmode = 1;
	    }
	}
    }
    if(! $gotwin) { 
        return logmsg "moni state chg. ($mode) FAIL: "
	    .         "Didn't get monitoring record indicating LC window change!\n";
    } 
    if(! $gotmode) {
	return logmsg "moni state chg. ($mode) FAIL: "
	    .         "Didn't get monitoring record indicating correct LC mode change!\n";
    }
    my $details = $detailed?" (LC mode & window state change records looked good)":"";
    logmsg "moni state chg. ($mode) $details\n";
    return 1;
}

sub asciiMoniTest {
    my $dom = shift;
    my $moniFile = "ascii_$dom.moni";
    my $cmd = "$dat -d0 -M1 -m $moniFile $dom 2>&1";
    my $result = docmd $cmd;
    if($result !~ /Done \((\d+) usec\)\./) {
        return logmsg("ASCII monitoring FAIL: 'Done' not found.\n".
		      "Command: $cmd\n".
		      "Result:\n$result\n\n");
    }
    my $dmtext = `/usr/local/bin/decodemoni -v $moniFile 2>&1`;
    if($dmtext !~ /MONI SELF TEST OK/) {
	return logmsg("ASCII monitoring FAIL: desired monitoring string was not present.\n".
		      "Command: $cmd\n".
		      "Result:\n$result\n\n");
    } elsif(hadError $dmtext || hadWarning $dmtext) {
	return logmsg("ASCII monitoring FAIL: monitoring stream had error or warning.\n".
		      "Monitoring output:\n$dmtext\n".
                      "Command: $cmd\n".
                      "Result:\n$result\n\n");
    } else {
        my $details = $detailed?" (got self test ASCII monitoring record)":"";
	logmsg "ASCII monitoring $details\n";
	return 1;
    }
}

sub getDOMIDTest {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    my $cmd = "$dat -Q $dom 2>&1";
    my $result = docmd $cmd;
    if($result !~ /DOM ID is \'(.+?)\'/) {
        return logmsg("DOM ID FAIL: $cmd\nresult:\n$result\n\n");
    } else {
        my $details = $detailed?", got good ID string from domapptest":"";
        logmsg "DOM ID ('$1') $details\n";
    }
    return 1;
}


sub configMoniTest {
    my $dom = shift;
    my $pat = shift;
    mydie unless $pat == "CF" || $pat == "HW";
    my $moniFile = "$pat"."_$dom.moni";
    my $patsw = ($pat=="CF")?"-f":"-w";
    my $cmd = "$dat -G -d2 -M1 $patsw 1 -m $moniFile $dom 2>&1";
    my $result = docmd $cmd;
    if($result !~ /Done \((\d+) usec\)\./) {
	return logmsg "$pat monitoring: FAIL: domapptest error: $cmd\n$result\n";
    }
    my @dmtext = `/usr/local/bin/decodemoni -v $moniFile 2>&1`;
    my $gotone = 0;
    for(@dmtext) {
	if(/$pat EVT/) {
	    $gotone++;
	} elsif(hadError $_ || hadWarning $_) {
	    return logmsg "$pat monitoring: FAIL: moni stream had error or warning: $_\n";
	}
    }
    if(!$gotone) {
	return logmsg "$pat monitoring: FAIL: no $pat records found!\n";
    }
    my $details = $detailed?" (got one or more $pat monitoring recs.)":"";
    logmsg "$pat monitoring $details\n";
    return 1;
}

sub domappmode { 
    my $dom = shift;
    my $cmd = "/usr/local/bin/se.pl $dom domapp domapp 2>&1";
    my $result = docmd $cmd;
    if($result !~ /SUCCESS/) {
	return logmsg("domapp change state FAIL.\nResult:\n$result\n\n");
    } else {
	logmsg "domapp change state\n";
    }
    return 1;
}

sub checkEngTrigs {
    my $type     = shift; mydie("missing arg") unless defined $type;
    my $unkn     = shift; mydie("missing arg") unless defined $unkn;
    my $lcup     = shift; mydie("missing arg") unless defined $lcup;
    my $lcdn     = shift; mydie("missing arg") unless defined $lcdn;
    # If pulser is on, should ONLY have SPE triggers:
    my $puls     = shift; mydie("missing arg") unless defined $puls;
    my @typelines = @_;
    
    my $haveForcedTrig = 0;

    foreach my $line (@typelines) {
	chomp $line;
	# print "$line vs. $type $unkn $lcup $lcdn\n";
	if($line =~ /trigger type='.+?' flags=<(.+?)> \[(\S+)\]/) {
	    my $flagstr = $1;
	    if($flagstr eq "none") { # require no unkn, lcup, lcdn
		if($unkn || $lcup || $lcdn) {
		    return "Hit file check failed: missing flag in trig line $line!";
		}
	    }
	    # else look for UNKNOWN_TRIG LC_UP_ENA or LC_DN_ENA
	    if($unkn && $flagstr !~ /UNKNOWN_TRIG/) { 
		return "Hit file check failed: UNKNOWN_TRIG flag required"
		    .  "but absent in line $line!";
	    }
	    if($lcup && $flagstr !~ /LC_UP_ENA/) {
		return "Hit file check failed: "
		    .  "LC_UP_ENA flag required but absent in line $line!";
            }
            if($lcdn && $flagstr !~ /LC_DN_ENA/) {
		return "Hit file check failed: "
		    .  "LC_DN_ENA flag required but absentin line $line!";
            }
	    my $hittype = hex($2); 
	    $haveForcedTrig = 1 if $hittype == 1;
	    my $badhit = 0;
	    $badhit = 1 if $puls && ($type != 2 || $hittype != 2);
	    $badhit = 1 if $type ==2 && $hittype != 1 && $hittype != 2;
	    $badhit = 1 if $type != 2 && $hittype != $type;
	    if($badhit) {
		return "Hit type $hittype doesn't match required type $type (pulser is "
		    .  ($puls?"ON":"off").")!";
	    }
	} else {
	    return "Hit file check failed: Bad hit type line '$line'!";
	}
    }

    if($type == 1 && !$haveForcedTrig) {
	
	return "Run type was 1 and did not have any forced triggers)!";
    } elsif($type == 2 && !$puls && !$haveForcedTrig) {
	return "Run type was 2, pulser was off, but did not "
	    .  "have any heartbeat triggers!";
    } elsif($type == 2 && $puls && $haveForcedTrig) {
	return "Run type was 2, pulser was on, and had "
	    .  "heartbeat/forced triggers!";
    }
    return "SUCCESS";
}

sub docmd {
    my $cmd = shift; mydie("missing arg") unless defined $cmd;
    logmsg "$cmd\n" if defined $showcmds;
    my $outfile = ".dm$$.".time;
    my $ret = system "$cmd &> $outfile";
    if($ret & 127) {
	logmsg "signal in subprocess ($ret)\n";
	exit(1);
    }
    my $rez = `cat $outfile`;
    logmsg "$rez" if defined $showcmds;
    unlink $outfile; 
    return $rez;
}

sub hadError { my $s = shift; return 1 if ($s =~ /error/i); return 0; }
sub hadWarning { my $s = shift; return 1 if ($s =~ /warning/i); return 0; }

sub doShortHitCollection {
    my %args        = @_;
    my $dom         = $args{DOM};         mydie("missing arg") unless defined $dom;
    my $type        = $args{Trig};        mydie("missing arg") unless defined $type;
    my $name        = $args{Name};        mydie("missing arg") unless defined $name;
    my $testname    = "hits $name trig=$type";
    my $lcup        = $args{LcUp};        $lcup = 0 unless defined $lcup;
    my $lcdn        = $args{LcDn};        $lcdn = 0 unless defined $lcdn;
    my $dur         = $args{Duration};    $dur  = 4 unless defined $dur;
    my $puls        = $args{DoPulser};    mydie("missing arg") unless defined $puls;
    my $thresh      = $args{Threshold};   mydie("missing arg") unless defined $thresh;
    my $dofb        = $args{DoFlasher};   $dofb   = 0  unless defined $dofb;
    my $bright      = $args{FBBright};    $bright = 1  unless defined $bright;
    my $win         = $args{FBWin};       $win    = 10 unless defined $win;
    my $delay       = $args{FBDelay};     $delay  = 0  unless defined $delay;
    my $mask        = $args{FBMask};      $mask   = 1  unless defined $mask;
    my $pulsrate    = $args{PulserRate};  # Leave undefined to accept default
    my $compMode    = $args{Compression}; # ""
    my $dataFmt     = $args{Format};      # ""
    my $doSN        = $args{doSN};        # ""
    my $SNDeadT     = $args{SNDeadTime};  # ""
    my $hitFreq     = $args{HitFreq};    $hitFreq   = 1 unless defined $hitFreq;
    my $moniFreq    = $args{MoniFreq};   $moniFreq  = 1 unless defined $moniFreq;
    my $countFreq   = $args{CountFreq};  $countFreq = 1 unless defined $countFreq;
    my $skipRateChk = $args{skipRateChk};

    my $engFile = "short_$name"."_$dom.hits";
    my $monFile = "short_$name"."_$dom.moni";
    my $snFile  = "short_$name"."_$dom.sn"; # Only used if $doSN
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
    my $snArg       = $doSN ? "-K $countFreq,0,$SNDeadT,$snFile" : "";
    my $moniArg     = ($moniFreq > 0)?"-w 1 -f 1 -M$moniFreq -m $monFile":"";
    if(defined $compMode && $compMode == CMP_RG) {
	$threshArg = "-R 100,100,100,100,100";
    }
    my ($pulsrateArg, $runArg);
    if($dofb) {
	$runArg = "-u $bright,$win,$delay,$mask,$pulsrate";
	$pulsrateArg = ""; 
# FIXME: check dacs!
    } else {
	$runArg = "-B";
	$pulsrateArg = (defined $pulsrate) ? "-P $pulsrate" : "";
    }
    my $cmd       = "$dat -G -d $dur $defaultDACs -S$speThreshDAC,$thresh "
	.           " $pulserArg $pulsrateArg $fmtArg $compArg $threshArg $snArg "
	.           "$moniArg -H$hitFreq -T $type $runArg "
	.           "-i $engFile $lcstr $dom 2>&1";

    my $result    = docmd $cmd;

    # Tenaciously fetch monitoring stream
    my $moni;
    if($moniFreq > 0) {
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
    }

    my $summary = 
	"Short run $name:\n".
	"Hit file: $engFile\n".
	"Original monitoring file: $monFile\n".
	"Shell command: $cmd\n".
	"Result:\n$result\n\n".
	"Monitoring output:\n$moni\n";
    
    if(hadError $moni || hadWarning $moni) {
	return logmsg "$testname FAIL: error or warning in or reading $monFile:\n$summary";
    }
    if($result !~ /Done \((\d+) usec\)\./) {
	return logmsg "$testname FAIL: domapptest finished abnormally\n$summary";
    }
    if($result =~ /ERROR/) {
	return logmsg "$testname FAIL: ERROR in domapptest output\n$summary";
    }

    # Check for trigger rate consistency
    my $trigType = "?";
    my $trigRate = "?";
    if(!$skipRateChk && $dataFmt == 0 && defined $pulsrate) {
	# Look for discriminator trigger if running in pulser mode:
	my $desiredType = $puls ? "Discriminator Trigger" : "CPU Trigger";
	my $nhits   = `/usr/local/bin/decodeeng $engFile 2>&1 | grep "$desiredType" | wc -l`;
	if($nhits =~ /^\s+(\d+)$/ && $1 > 0) {
	    my $nhits = $1;
            my $evrate = $nhits/$dur;
            if($evrate < $pulsrate/3 || $evrate > $pulsrate*3) {
		return logmsg "$testname FAIL: measured forced trigger rate ($evrate Hz) ".
		    "doesn't match requested rate ($pulsrate Hz))\n$summary\n";
	    } else {
		$desiredType =~ m/(\S*)/;
		$trigType = $1;
		$trigRate = $evrate;
	    }
	} else {
	    return logmsg "$testname FAIL: didn't get any forced trigger data!\n$summary\n";
	}
    }
    # Check for SPE rate consistency if rate is defined and pulser in use:
    if($dataFmt == 0 && $moniFreq > 0 && defined $pulsrate && $puls) {
	my @moni   = `decodemoni -v $monFile | grep HW`;
	my $spesum = 0;
	my $nspe   = 0;
	for(@moni) {
	    my $spe = (split '\s+')[32];
	    $nspe++;
	    $spesum += $spe;
	}
	if($nspe == 0) {
	    return logmsg "$testname FAIL: no HW moni records in $monFile!\n$summary\n";
	}
	my $speAvg = $spesum / $nspe;
	if(!$skipRateChk && $speAvg < $pulsrate/3 || $speAvg > $pulsrate*3) {
	    return logmsg "$testname FAIL: measured SPE discriminator rate ($speAvg Hz) doesn't ".
		"match requested rate ($pulsrate Hz)!\n$summary\n";
	}
    }

    my $nhitsline;
    if($dataFmt == 0) {
	$nhitsline = `/usr/local/bin/decodeeng $engFile 2>&1 | grep "time stamp" | wc -l`;
    } elsif($dataFmt == 1) {
	my @decompHits = `/usr/local/bin/decomp $engFile 2>&1`;
	my @errWarn = grep /error|warning/i, @decompHits;
	my @hitsLine = grep /HIT/, @decompHits;
	$nhitsline = scalar @hitsLine;
	if(scalar @errWarn > 0) {
	    my $errWarn = join '', @errWarn;
	    return logmsg "$testname FAIL: had ERROR or WARNING in decompressed $engFile!\n"
		.         "$summary\n";
	}
    } else {
	return logmsg "$testname FAIL: BAD DATA FORMAT ($dataFmt)\n$summary\n";
    }

    # If asked for, look for supernova data
    my $SNbins        = 0;
    my $SNcountsTotal = 0;
    if($doSN && $countFreq > 0) {
	my @snData = `/usr/local/bin/decodesn $snFile 2>&1`;
	for(@snData) {
	    if(/(\d+) counts/) {
		$SNbins ++;
		$SNcountsTotal += $1;
	    }
	}
	if($SNbins == 0) {
	    return logmsg("$testname FAIL: $snFile had no timeslice data!\n$summary\n");
	}
	if($SNcountsTotal < 1) {
	    return logmsg("$testname FAIL: supernova data file $snFile had no hits!\n$summary\n");
	}
    }

    if($dataFmt == 0 && $hitFreq > 0) {
	my @typelines = `/usr/local/bin/decodeeng $engFile 2>&1 | grep type`;
	my $chkEngResult = checkEngTrigs($type, 0, $lcup, $lcdn, $puls, @typelines);
	if($chkEngResult ne "SUCCESS") {
	    return logmsg "$testname FAIL: engineering event check failure:\n"
		.         "$chkEngResult\n$summary\n";
	}
    }

    if($nhitsline !~ /^\s*(\d+)$/) {
        return logmsg "$testname FAIL: didn't get any hit data\n$summary\n";
    } else {
	my $nhits = $1;
	if($hitFreq==0 || $nhits > 0) {
	    logmsg "$testname nhits=$nhits snbins=$SNbins sntot=$SNcountsTotal\n";
	} else {
	    return logmsg "$testname FAIL, nhits=$nhits\n$summary\n";
	}
    }

    return 1;
}

sub flasherVersionTest {
    my $dom  = shift;
    my $cmd = "$dat -z $dom 2>&1";
    my $result = docmd $cmd;
    my $fbid;
    if($result =~ /Flasher board ID is \'(.*?)\'/) {
	if($1 eq "") {
	    return logmsg("flasher board ID FAIL: flasher board ID was empty\n$cmd\n$result\n");
	} else {
	    $fbid = $1;
	}
    } else {
	return logmsg("flasher board ID FAIL: $cmd\n$result\n");
    }
    my $details = $detailed?"(found nonempty flasher board ID)":"";
    logmsg "flasher board ID ($fbid) $details\n";
    return 1;
}

sub flasherTest { 
    my $dom  = shift; mydie("missing arg") unless defined $dom;
    return doShortHitCollection(DOM         => $dom,
                                Trig        => CPUTRIG,
                                Name        => "Flasher",
				Duration    => $datDuration,
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
    my $dom = shift; mydie("missing arg") unless defined $dom;
    my $cmd = "$dat -o $dom 2>&1";
    my $result = docmd $cmd;
    if($result !~ /Done/) {
        my $getMoniCmd = "$dat -d 1 -M1 -m last.moni $dom 2>&1";
        my $result     = docmd $getMoniCmd;
	my $moni       = `decodemoni -v last.moni|grep -v HDR`;
        return logmsg("multi pedestal fetch FAIL:\n".
		      "Command: $cmd\n".
		      "Result:\n$result\n\n".
		      "Monitoring stream:\n$moni\n");
    }
    my $details = $detailed?"(got 'Done' string from domapptest)":"";
    logmsg "multi pedestal fetch $details\n";
    return 1;
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

sub reapKids {
    use POSIX ":sys_wait_h";
    my $kid;
    while(1) {
	$kid = waitpid(-1, &WNOHANG);
	if($kid == -1) {
	    last;
	} else {
	    select(undef,undef,undef,0.01);
	}
    }
}

sub killKids {
    for(@_) {
	kill('KILL', $_) || mydie "Can't kill $_: $!\n";
    }
}

sub logmsg {
    my $msg  = shift;
    my $time = time;
    my $now  = scalar localtime;
    open L, ">>$logfile" || mydie "Can't open $logfile: $!\n";
    print L "$time ($now) $msg";
    close L;
    return 0;
}

sub logOf {
    my $dom = shift; mydie("missing arg") unless defined $dom;
    return "domapp$dom.log";
}

sub checkProcs {
    my @processes = `ps ax | grep $O | grep -v grep`;
    my $numprocs = 0;
    for(@processes) {
	$numprocs++ if(/perl.+?$O/);
    }
    if($numprocs > 1) {
	print @processes;
	die "$O is already running!\n";
    }
}

sub mydie { 
    my $m = shift; 
    $m = "bad arg?" unless defined $m; 
    print LOG "$O: FATAL ERROR ($m)\n"; 
    die $m; 
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
     -t <sec>:    Run for <sec> seconds (min/default: run all tests
                  sequentially, once)
     -x <sec>:    Default duration for each data-taking run
     -o:          Perform long duration tests (normally skipped)
     -C:          Test only compressed data (pedestal collection, ...)
     -R:          Randomize tests after first sequential set is complete
     -sn n:       Test supernova data collection:
                  0 = skip all supernova tests
                  1 = test SN scaler collection only
                  2 = test scaler collection + hit data only
                  3 = test modes 1 (counts only) and 2 (counts+hits) only
                      (no other tests)
                  4 = (default) allow SN tests and other tests as well

If -V or -F options are not given, only tests appropriate for a
bare DOM mainboard are given.

EOF
;
}


__END__
