#!/usr/bin/perl

# sink-till-fail.pl
# John Jacobsen, NPX Designs, Inc., jacobsen\@npxdesigns.com
# Started: Thu Dec 30 21:22:42 2004

package MY_PACKAGE;
use strict;

print "Welcome to $0.\n";

sub usage { return "Usage: $0 <dom>\nE.g. $0 00A\n\n"; }

my $dom = shift;
my $pktsiz = shift;
$pktsiz = 64 unless defined $pktsiz;
die usage unless defined $dom;
while(1) {
    my $sinkcmd = "./sink-test.sh $dom $pktsiz";
    print "$sinkcmd: ";
    my $result = `$sinkcmd`;
    print $result;
    last if $result =~ /timeout/i;
# 30A 20000 1280000 21190 0 0
    last unless $result =~ /(\S+) \d+ \d+ \d+ \d+ \d+/;
}


__END__

