#!/usr/bin/perl

# Simple script which puts newly powered-on DOM into the
# domapp state
#
# John Jacobsen, John Jacobsen IT Services, for LBNL/IceCube
# Dec. 2003
# $Id: upload_domapp.pl,v 1.5 2005-06-02 18:13:45 jacobsen Exp $

use Fcntl;
use strict;
use IO::Socket;
use IO::Select;
use Getopt::Long;
my $verbose = 0;
my $quiet   = 0;
$|++;

sub drain_iceboot;
sub usage { return <<EOF;
Usage: $0 [-f name] <card> <pair> <dom> <file>
	            <dom> is A or B.
          -f option writes flash using name <name>
	  -n option skips gunzip command
          -u option quits immediately after upload
	  -q option runs more quietly
EOF
;
	}
sub ymodem1kcmd;
sub pause { select undef,undef,undef,0.3; };
sub killdomserv;
sub domserv_command;

my $flash;
my $help;
my $uploadonly;
my $nogunzip;
my $quiet;
GetOptions("flash=s"    => \$flash,
	   "upload|u"   => \$uploadonly,
	   "nogunzip|n" => \$nogunzip,
	   "quiet|q"    => \$quiet,
	   "help|h"     => \$help) || die usage;

my $O = (split '/', $0)[-1];
print "$O by jacobsen\@npxdesigns.com for LBNL/IceCube...\n" unless $quiet;

die usage if $help;
# Check for domserv & sz...

my $domserv = "/usr/local/bin/domserv";
die "No $domserv!\n" unless -x $domserv;

my $sz = "/usr/bin/sz";
die "No $sz!\n" unless -x $sz;

# Get DOM address...

my $card = shift;
my $pair = shift;
my $dom  = shift;
my $file = shift;
die usage unless defined $card && defined $pair && defined $dom && defined $file;
die "Can't find file $file to upload.\n" unless -e $file;
$dom =~ tr/[a-z]/[A-Z]/;
die usage unless $dom eq "A" || $dom eq "B";
print "$file -> $card $pair $dom...\n" unless $quiet;

my $port = 4001 + $card * 8 + $pair * 2 + ($dom eq 'A' ? 0 : 1);
my $szport = $port + 500;
my $szargs = "-q --ymodem -k --tcp-client localhost:$szport $file";

print "Talking port $port, SZ port $szport.\n" unless $quiet;
# Start domserv...

my $pid = fork;
die "Can't fork: $!\n" unless defined $pid;

if($pid == 0) {
    my $domserv_cmd = "$domserv -dh 2>&1 > /dev/null";
    print "EXEC($domserv_cmd)\n" unless $quiet;
    open DS, "|$domserv_cmd";
    my $domsrvinput = "open dom $card$pair$dom";
    print DS "$domsrvinput\n";
    print "DOMSERV($domsrvinput)\n" unless $quiet;
    close DS;
    sleep 1000;
    # Domserv waits at this point
    exit; # Never happens
}

# After this point pid is our child process (domserv).
# connect and upload here
select undef, undef, undef, 0.3; # Wait for domserv to start up

if(domserv_command("localhost", $port, "ymodem1k", "CCC")) {
    warn "FAIL: ymodem1k didn't give expected 'CCC...' pattern (wrong DOM state?)\n";
    killdomserv $pid;
    exit;
}

my $cmd = "$sz $szargs 2>&1\n";
print $cmd unless $quiet;
sleep 1;
my $szresult = `$cmd`;
print "SZ command result: $szresult\n" unless $quiet;

if(domserv_command("localhost", $port, ".s")) {
    warn "FAIL: domserv_command failed (.s).\n";
    killdomserv $pid;
    exit;
}

if(!defined $uploadonly) {
    if(! $nogunzip && domserv_command("localhost", $port, "gunzip")) {
	warn "FAIL: domserv_command failed (gunzip).\n";
	killdomserv $pid;
	exit;
    }
    
    if(defined $flash) {
	if(domserv_command("localhost", $port, "s\" $flash\" create")) {
	    warn "FAIL: domserv_command failed (write flash).\n";
	    killdomserv $pid;
	    exit -1;
	}
    } else {
	if(domserv_command("localhost", $port, "exec")) {
	    warn "FAIL: domserv_command failed (exec).\n";
	    killdomserv $pid;
	    exit;
	}
    }
}

select undef, undef, undef, 0.3;
killdomserv $pid;

print "SUCCESS\n";
exit;

sub printable {
    my $b = shift;
    return 1 if ord($b) > 31 && ord($b) < 127;
    return 0;
}

sub domserv_command {
    my $hostname = shift; die unless defined $hostname;
    my $port     = shift; die unless defined $port;
    my $cmd      = shift; die unless defined $cmd;
    my $expect   = shift;
    # Wait for previous socket to close
    select undef, undef, undef, 0.1;
    my $socket = new IO::Socket::INET(PeerAddr   => $hostname,
				      PeerPort   => $port,
				      Proto      => 'tcp',
				      Blocking   => 0
				      );
    
    if(!defined $socket) {
	warn "FAIL: Can't set up socket to $hostname:$port :-- $!\n";
	return 1;
    }
    syswrite $socket, "\r\r$cmd\r";
    my $sel = new IO::Select($socket);
    my $buf;
    my $totbuf = "";
    my $gotexpect = 0;
    while($sel->can_read(0.6)) {
	my $read = sysread($socket, $buf, 1);
	if($read) {
	    $totbuf .= $buf;
	    print " " if !$quiet && $buf eq "\r";
	    print $buf if !$quiet && printable($buf);
	    if(defined $expect) {
		if($totbuf =~ /$expect/m) {
		    # print "Got EXPECT($expect)!\n";
		    $gotexpect = 1;
		    last;
		}
	    }
	} else {
	    if(defined $expect) {
		return 1;
	    } else { # Don't need anything, just done
		last;
	    }
	}
    }
    close($socket);
    if(defined $expect and ! $gotexpect) {
	return 1;
    } else { # Alles gute
	return 0;
    }
}

sub killdomserv {
    my $pid = shift;
    return undef unless defined $pid;
    return undef unless $pid > 0;
    kill 9, $pid;
    system "killall domserv 2>&1 > /dev/null";

}

