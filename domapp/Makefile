# Makefile for domhub-tools/domapp
# Jacobsen
# $Id: Makefile,v 1.2 2005-03-14 22:51:47 jacobsen Exp $

INSTALL_BIN = /usr/local/bin

all:
	domapptest

domapptest: domapptest.c domapp.h
	gcc -Wall -o domapptest domapptest.c

install:
	install domapp_multitest.pl domapptest $(INSTALL_BIN)

