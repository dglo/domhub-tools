Summary: IceCube DOM Application (domapp) testing applications
Name: domhub-tools
Version: %{VER}
Release: %{REL}
Source0: %{name}-%{version}.tgz
License: Copyright 2003 LBNL/IceCube collaboration (sorry, *NOT* GPL)
Group: System Environment/Base
BuildRoot: %{_tmppath}/%{name}-root
Prefix: %{_prefix}
Requires: dor-driver

%description
IceCube DOM Hub Testing Applications (MJB, ...)

%prep
%setup -q

%build
make clean; cd rel-100; make

%install
install -d ${RPM_BUILD_ROOT}/usr/local/share
install -d ${RPM_BUILD_ROOT}/usr/local/share/domhub-tools
install -d ${RPM_BUILD_ROOT}/usr/local/share/domhub-testing
install -d ${RPM_BUILD_ROOT}/usr/local/bin

# domhub-tools

install -D rel-100/domhub-tools/se \
           rel-100/domhub-tools/tcalcycle \
           rel-100/domhub-tools/domserv \
           rel-100/domhub-tools/domterm \
           rel-100/domhub-tools/decodetcal \
              ${RPM_BUILD_ROOT}/usr/local/bin

install -D rel-100/domhub-tools/dom.awk \
           rel-100/domhub-tools/dor.awk \
           rel-100/domhub-tools/tcal-calc.awk \
           rel-100/domhub-tools/tcal-cvt.awk \
           rel-100/domhub-tools/tcal.awk \
              ${RPM_BUILD_ROOT}/usr/local/share/domhub-tools

install -D rel-100/domhub-tools/configboot.sh \
           rel-100/domhub-tools/domstate.sh \
           rel-100/domhub-tools/echo-mode.sh \
           rel-100/domhub-tools/iceboot.sh \
           rel-100/domhub-tools/insrel.sh \
           rel-100/domhub-tools/ldall.sh \
           rel-100/domhub-tools/tcal-kalle.sh \
           rel-100/domhub-tools/tcal-stf.sh \
           rel-100/domhub-tools/tcal.sh \
           rel-100/domhub-tools/versions.sh \
           rel-100/domhub-tools/softboot.sh \
           rel-100/domhub-tools/domhub-version.sh \
           rel-100/domhub-tools/common.sh \
              ${RPM_BUILD_ROOT}/usr/local/share/domhub-tools

install -D rel-100/domhub-tools/cb-version.exp \
           rel-100/domhub-tools/ib-versions.exp \
              ${RPM_BUILD_ROOT}/usr/local/share/domhub-tools

# domhub-testing

install -D rel-100/domhub-testing/echo-test \
           rel-100/domhub-testing/open-test \
              ${RPM_BUILD_ROOT}/usr/local/share/domhub-testing

install -D rel-100/domhub-testing/current-test.sh \
           rel-100/domhub-testing/domid-test.sh \
           rel-100/domhub-testing/echo-test.sh \
           rel-100/domhub-testing/echo-throttle-test.sh \
           rel-100/domhub-testing/fpga-reload-test.sh \
           rel-100/domhub-testing/quiet-test.sh \
           rel-100/domhub-testing/run-test.sh \
           rel-100/domhub-testing/sink-test.sh \
           rel-100/domhub-testing/slow-open-test.sh \
           rel-100/domhub-testing/softboot-test.sh \
           rel-100/domhub-testing/source-test.sh \
           rel-100/domhub-testing/tcal-test.sh \
           rel-100/domhub-testing/temp-test.sh \
           rel-100/domhub-testing/wiggle-test.sh \
           rel-100/domhub-testing/wr-block-test.sh \
           rel-100/domhub-testing/throughput.sh \
              ${RPM_BUILD_ROOT}/usr/local/share/domhub-testing

install -D rel-100/domhub-testing/domid-results.sh \
           rel-100/domhub-testing/quiet-results.sh \
           rel-100/domhub-testing/softboot-results.sh \
           rel-100/domhub-testing/throughput-all-results.sh \
           rel-100/domhub-testing/throughput-AB.sh \
           rel-100/domhub-testing/echo-results.sh \
           rel-100/domhub-testing/echo-throttle-results.sh \
           rel-100/domhub-testing/sink-results.sh \
           rel-100/domhub-testing/source-results.sh \
           rel-100/domhub-testing/tcal-results.sh \
              ${RPM_BUILD_ROOT}/usr/local/share/domhub-testing

install -D rel-100/domhub-testing/details-qry.sh \
           rel-100/domhub-testing/error-qry.sh \
           rel-100/domhub-testing/even-schedule-qry.sh \
           rel-100/domhub-testing/results-qry.sh \
              ${RPM_BUILD_ROOT}/usr/local/share/domhub-testing

install -D rel-100/domhub-testing/mjb.sh \
           rel-100/domhub-testing/run-mjb.sh \
           rel-100/domhub-testing/tests.txt \
              ${RPM_BUILD_ROOT}/usr/local/share/domhub-testing

# other
install -D rel-100/rel.num \
              ${RPM_BUILD_ROOT}/usr/local/share/rel.num

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
/usr/local/bin/se
/usr/local/bin/tcalcycle
/usr/local/bin/domserv
/usr/local/bin/domterm
/usr/local/bin/decodetcal
/usr/local/share/rel.num
/usr/local/share/domhub-testing/current-test.sh
/usr/local/share/domhub-testing/details-qry.sh
/usr/local/share/domhub-testing/domid-results.sh
/usr/local/share/domhub-testing/domid-test.sh
/usr/local/share/domhub-testing/echo-results.sh
/usr/local/share/domhub-testing/echo-test
/usr/local/share/domhub-testing/echo-test.sh
/usr/local/share/domhub-testing/echo-throttle-results.sh
/usr/local/share/domhub-testing/echo-throttle-test.sh
/usr/local/share/domhub-testing/error-qry.sh
/usr/local/share/domhub-testing/even-schedule-qry.sh
/usr/local/share/domhub-testing/fpga-reload-test.sh
/usr/local/share/domhub-testing/mjb.sh
/usr/local/share/domhub-testing/open-test
/usr/local/share/domhub-testing/quiet-results.sh
/usr/local/share/domhub-testing/quiet-test.sh
/usr/local/share/domhub-testing/results-qry.sh
/usr/local/share/domhub-testing/run-mjb.sh
/usr/local/share/domhub-testing/run-test.sh
/usr/local/share/domhub-testing/sink-results.sh
/usr/local/share/domhub-testing/sink-test.sh
/usr/local/share/domhub-testing/slow-open-test.sh
/usr/local/share/domhub-testing/softboot-results.sh
/usr/local/share/domhub-testing/softboot-test.sh
/usr/local/share/domhub-testing/source-results.sh
/usr/local/share/domhub-testing/source-test.sh
/usr/local/share/domhub-testing/tcal-results.sh
/usr/local/share/domhub-testing/tcal-test.sh
/usr/local/share/domhub-testing/temp-test.sh
/usr/local/share/domhub-testing/tests.txt
/usr/local/share/domhub-testing/throughput-AB.sh
/usr/local/share/domhub-testing/throughput-all-results.sh
/usr/local/share/domhub-testing/throughput.sh
/usr/local/share/domhub-testing/wiggle-test.sh
/usr/local/share/domhub-testing/wr-block-test.sh
/usr/local/share/domhub-tools/cb-version.exp
/usr/local/share/domhub-tools/common.sh
/usr/local/share/domhub-tools/configboot.sh
/usr/local/share/domhub-tools/dom.awk
/usr/local/share/domhub-tools/domhub-version.sh
/usr/local/share/domhub-tools/domstate.sh
/usr/local/share/domhub-tools/dor.awk
/usr/local/share/domhub-tools/echo-mode.sh
/usr/local/share/domhub-tools/ib-versions.exp
/usr/local/share/domhub-tools/iceboot.sh
/usr/local/share/domhub-tools/insrel.sh
/usr/local/share/domhub-tools/ldall.sh
/usr/local/share/domhub-tools/softboot.sh
/usr/local/share/domhub-tools/tcal-calc.awk
/usr/local/share/domhub-tools/tcal-cvt.awk
/usr/local/share/domhub-tools/tcal-kalle.sh
/usr/local/share/domhub-tools/tcal-stf.sh
/usr/local/share/domhub-tools/tcal.awk
/usr/local/share/domhub-tools/tcal.sh
/usr/local/share/domhub-tools/versions.sh

%post
ln -f ${RPM_BUILD_ROOT}/usr/local/share/domhub-tools/configboot.sh \
	${RPM_BUILD_ROOT}/usr/local/bin/configboot
ln -f ${RPM_BUILD_ROOT}/usr/local/share/domhub-tools/domstate.sh \
	${RPM_BUILD_ROOT}/usr/local/bin/domstate
ln -f ${RPM_BUILD_ROOT}/usr/local/share/domhub-tools/echo-mode.sh \
	${RPM_BUILD_ROOT}/usr/local/bin/echo-mode
ln -f ${RPM_BUILD_ROOT}/usr/local/share/domhub-tools/iceboot.sh \
	${RPM_BUILD_ROOT}/usr/local/bin/iceboot
ln -f ${RPM_BUILD_ROOT}/usr/local/share/domhub-tools/insrel.sh \
	${RPM_BUILD_ROOT}/usr/local/bin/insrel
ln -f ${RPM_BUILD_ROOT}/usr/local/share/domhub-tools/ldall.sh \
	${RPM_BUILD_ROOT}/usr/local/bin/ldall
ln -f ${RPM_BUILD_ROOT}/usr/local/share/domhub-tools/tcal-kalle.sh \
	${RPM_BUILD_ROOT}/usr/local/bin/tcal-kalle
ln -f ${RPM_BUILD_ROOT}/usr/local/share/domhub-tools/tcal-stf.sh \
	${RPM_BUILD_ROOT}/usr/local/bin/tcal-stf
ln -f ${RPM_BUILD_ROOT}/usr/local/share/domhub-tools/tcal.sh \
	${RPM_BUILD_ROOT}/usr/local/bin/tcal
ln -f ${RPM_BUILD_ROOT}/usr/local/share/domhub-tools/versions.sh \
	${RPM_BUILD_ROOT}/usr/local/bin/versions
ln -f ${RPM_BUILD_ROOT}/usr/local/share/domhub-tools/softboot.sh \
	${RPM_BUILD_ROOT}/usr/local/bin/softboot
ln -f ${RPM_BUILD_ROOT}/usr/local/share/domhub-tools/domhub-version.sh \
	${RPM_BUILD_ROOT}/usr/local/bin/domhub-version
# domhub-testing
ln -f ${RPM_BUILD_ROOT}/usr/local/share/domhub-testing/throughput-AB.sh \
        ${RPM_BUILD_ROOT}/usr/local/share/domhub-testing/throughput-A-results.sh
ln -f ${RPM_BUILD_ROOT}/usr/local/share/domhub-testing/throughput-AB.sh \
        ${RPM_BUILD_ROOT}/usr/local/share/domhub-testing/throughput-B-results.sh
ln -f ${RPM_BUILD_ROOT}/usr/local/share/domhub-testing/run-mjb.sh \
        ${RPM_BUILD_ROOT}/usr/local/bin/run-mjb

%postun
rm -f /usr/local/bin/ldall
rm -f /usr/local/bin/configboot
rm -f /usr/local/bin/domstate
rm -f /usr/local/bin/echo-mode
rm -f /usr/local/bin/iceboot
rm -f /usr/local/bin/insrel
rm -f /usr/local/bin/ldall
rm -f /usr/local/bin/tcal-kalle
rm -f /usr/local/bin/tcal-stf
rm -f /usr/local/bin/tcal
rm -f /usr/local/bin/versions
rm -f /usr/local/bin/softboot
rm -f /usr/local/bin/domhub-version
rm -f /usr/local/share/domhub-testing/throughput-A-results.sh
rm -f /usr/local/share/domhub-testing/throughput-B-results.sh
rm -f /usr/local/share/domhub-tools/pwr.sh
rm -f /usr/local/share/domhub-tools/rel.num
rm -f /usr/local/bin/run-mjb
rmdir /usr/local/share/domhub-testing
rmdir /usr/local/share/domhub-tools

%changelog
* Wed Jul 13 2005 John E. Jacobsen <jacobsen@npxdesigns.com>
- First version 

