# Makefile for domhub-tools/domapp
# Jacobsen
# $Id: Makefile,v 1.4 2005-03-15 00:22:30 jacobsen Exp $

INSTALL_BIN = /usr/local/bin

all:
	make domapptest

domapptest: domapptest.c domapp.h
	gcc -Wall -o domapptest domapptest.c

clean:
	rm domapptest

install:
	install domapp_multitest.pl $(INSTALL_BIN)
	install domapptest          $(INSTALL_BIN)
	install upload_domapp.pl    $(INSTALL_BIN)


