# Makefile for domhub-tools/domapp
# Jacobsen
# $Id: Makefile,v 1.5 2005-03-16 22:51:28 jacobsen Exp $

INSTALL_BIN = /usr/local/bin

all:
	make domapptest

domapptest: domapptest.c domapp.h
	gcc -Wall -o domapptest domapptest.c

clean:
	rm -f domapptest

install:
	install domapp_multitest.pl $(INSTALL_BIN)
	install domapptest          $(INSTALL_BIN)
	install upload_domapp.pl    $(INSTALL_BIN)


