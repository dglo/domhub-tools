# Makefile for domhub-tools/domapp
# Jacobsen
# $Id: Makefile,v 1.11 2005-06-02 18:13:31 jacobsen Exp $

INSTALL_BIN = /usr/local/bin

BINS = domapptest decomp decodemoni decodeeng decodesn
all:
	make $(BINS)

decodemoni: decodemoni.c domapp.h
	gcc -Wall -o decodemoni decodemoni.c

decodeeng: decodeeng.c
	gcc -Wall -o decodeeng -I ../devel/domhub-tools decodeeng.c

domapptest: domapptest.c domapp.h
	gcc -Wall -o domapptest domapptest.c

decomp: decomp.c
	gcc -Wall -o decomp decomp.c

decodesn: decodesn.c
	gcc -Wall -o decodesn decodesn.c

clean:
	rm -f $(BINS)

install:
	install domapptest          $(INSTALL_BIN)
	install upload_domapp.pl    $(INSTALL_BIN)
	install decomp              $(INSTALL_BIN)
	install decodemoni          $(INSTALL_BIN)
	install decodeeng           $(INSTALL_BIN)
	install decodesn            $(INSTALL_BIN)
	install domapp_multitest.pl $(INSTALL_BIN)
	ln -f -s $(INSTALL_BIN)/domapp_multitest.pl $(INSTALL_BIN)/dmt
