# Makefile for domhub-tools
# Arthur Jones and John Jacobsen
# $Id: Makefile,v 1.3 2005-03-15 01:06:06 jacobsen Exp $

all:
	pushd moat   && make && popd
	pushd domapp && make && popd

install:
	pushd moat   && make install && popd
	pushd domapp && make install && popd

clean:
	pushd moat   && make clean && popd
	pushd domapp && make clean && popd
