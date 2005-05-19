# Makefile for domhub-tools/domapp
# Jacobsen
# $Id: Makefile,v 1.6 2005-05-17 20:53:20 jacobsen Exp $

INSTALL_BIN = /usr/local/bin

all:
	make domapptest decomp

domapptest: domapptest.c domapp.h
	gcc -Wall -o domapptest domapptest.c

decomp: decomp.c
	gcc -Wall -o decomp decomp.c

clean:
	rm -f domapptest

install:
	install domapp_multitest.pl $(INSTALL_BIN)
	install domapptest          $(INSTALL_BIN)
	install upload_domapp.pl    $(INSTALL_BIN)
	install decomp              $(INSTALL_BIN)

