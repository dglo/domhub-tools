# Makefile for domhub-tools
# Arthur Jones and John Jacobsen
# $Id: Makefile,v 1.4 2005-03-22 21:46:44 jacobsen Exp $

all:
	cd moat   && make
	cd domapp && make
	cd devel  && make

install:
	cd moat   && make install
	cd domapp && make install
	cd devel  && make install

clean:
	cd moat   && make clean
	cd domapp && make clean
	cd devel  && make clean
