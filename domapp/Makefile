# Makefile for domhub-tools/domapp
# Jacobsen
# $Id: Makefile,v 1.8 2005-05-19 21:34:59 jacobsen Exp $

INSTALL_BIN = /usr/local/bin

all:
	make domapptest decomp decodemoni

decodemoni: decodemoni.c domapp.h
	gcc -Wall -o decodemoni decodemoni.c

decodeeng: decodeeng.c domapp.h
	gcc -Wall -o decodeeng decodeeng.c

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
	install decodemoni          $(INSTALL_BIN)

