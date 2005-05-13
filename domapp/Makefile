# Makefile for domhub-tools/domapp
# Jacobsen
# $Id: Makefile,v 1.3 2005-03-16 16:39:39 arthur Exp $

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


