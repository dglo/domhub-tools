# Makefile for domhub-tools/domapp
# Jacobsen
# $Id: Makefile,v 1.3 2005-03-14 23:25:41 jacobsen Exp $

INSTALL_BIN = /usr/local/bin

all:
	make domapptest

domapptest: domapptest.c domapp.h
	gcc -Wall -o domapptest domapptest.c

clean:
	rm domapptest

install:
	install domapp_multitest.pl domapptest $(INSTALL_BIN)

