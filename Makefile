# Makefile for domhub-tools
# Arthur Jones and John Jacobsen

all:
	pushd moat   && make && popd
	pushd domapp && make && popd

install:
	pushd moat   && make install && popd
	pushd domapp && make install && popd

clean:
	pushd moat   && make clean && popd
	pushd domapp && make clean && popd
