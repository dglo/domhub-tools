#!/bin/bash

#
# mkldall.sh, make a ldall.sh tarball...
#
if [[ -d ldall-install ]]; then
	echo "mkldall.sh: ldall-install already exists, plz remove it..."
	exit 1
fi

mkdir ldall-install

if ! cp ib-versions.exp cb-version.exp ldall-install; then
	echo "mkldall.sh: can not cp exp files"
	exit 1
fi

if ! cp insrel.sh ldall.sh ldall-install; then
	echo "mkldall.sh: can not cp shell scripts"
	exit 1
fi

if ! cp se ../dor-driver/driver/domterm ldall-install; then
	echo "mkldall.sh: can not cp executables"
	exit 1
fi

if ! tar cf - ldall ldall-install | gzip -c > ldall-install.tar.gz; then
	echo "mkldall.sh: can not create archive"
	exit 1
fi

rm -rf ldall-install

