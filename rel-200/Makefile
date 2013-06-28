SUBDIRS=domhub-tools domhub-testing
REL=$(shell cat rel.num)
SRT=domhub-tools-$(REL)
RPMDIR=~/rpmbuild
ARCH=$(shell arch)
RPM=$(RPMDIR)/RPMS/$(ARCH)/$(SRT)-1.$(ARCH).rpm
SPEC=$(RPMDIR)/SPECS/domhub-tools.spec
STB=$(SRT).tar.gz
FILES=domhub-tools.description Makefile rel.num ChangeLog
ROOT=
BINPATH=$(ROOT)/usr/local/bin
# Version control directories to exclude
VCS=.svn

all:
	@for dir in $(SUBDIRS); do (cd $$dir && make ); done

rhdirs:
	mkdir -p $(RPMDIR)
	for dir in SPECS SOURCES BUILD RPMS SRPMS ; do \
		mkdir -p $(RPMDIR)/$$dir; \
	done

clean:
	@for dir in $(SUBDIRS); do (cd $$dir && make clean ); done

install:
	@if [[ ! -d $(BINPATH) ]]; then mkdir -p $(BINPATH); fi
	@for dir in $(SUBDIRS); do \
		(cd $$dir && make ROOT=$(ROOT) install ); \
	done
	install -D rel.num $(ROOT)/usr/local/share/domhub-tools/rel.num

stb: $(STB)

$(STB): clean
	@if [[ ! -f rel.num ]]; then echo 100 > rel.num; fi
	@mkdir $(SRT)
	@tar cf - $(SUBDIRS) $(FILES) --exclude=$(VCS) | ( cd $(SRT); tar xf - )
	@tar cf - $(SRT) | gzip -c > $(STB)
	@rm -rf $(SRT)
	@echo created: $(STB)

release:
	cp $(RPM) /net/user/pdaq/packaged-releases/domhub-tools/rel-2xx
	cp ChangeLog /net/user/pdaq/packaged-releases/domhub-tools/rel-2xx/RELEASE_NOTES
	@svn cp `svn info|grep URL|cut -d ' ' -f 2` \
		http://code.icecube.wisc.edu/daq/projects/domhub-tools/releases/rel-$(REL) -m rel-$(REL)
	@echo "`cat rel.num` 1 + p" | dc > rel.num.2
	@mv rel.num.2 rel.num
	@svn commit -m "incremented" rel.num

rpm: $(RPM)

spec: $(SPEC)

$(SPEC): spec-header spec-description spec-prep spec-build spec-install \
	spec-clean spec-files

spec-header:
	@echo "Summary: dom manipulation and testing programs" > $(SPEC)
	@echo "Name: domhub-tools" >> $(SPEC)
	@echo "Version: `cat rel.num`" >> $(SPEC)
	@echo "Release: 1" >> $(SPEC)
#	@echo "Copyright: GPL" >> $(SPEC)
	@echo "License: GPL" >> $(SPEC)
	@echo "Group: Applications/System" >> $(SPEC)
#	@echo "Source0: http://glacier.lbl.gov/\~arthur/domhub-tools/domhub-tools-`cat rel.num`.tar.gz" >> $(SPEC)
	@echo "Source0: domhub-tools-`cat rel.num`.tar.gz" >> $(SPEC)
	@echo "BuildRoot: /tmp/domhub-tools" >> $(SPEC)

spec-description:
	@echo " " >> $(SPEC)
	@echo "%description" >> $(SPEC)
	@cat domhub-tools.description >> $(SPEC)

spec-prep:
	@echo " " >> $(SPEC)
	@echo "%prep" >> $(SPEC)
	@echo "%setup" >> $(SPEC)
	@echo "%define _unpackaged_files_terminate_build 0" >> $(SPEC)
spec-build:
	@echo " " >> $(SPEC)
	@echo "%build" >> $(SPEC)
	@echo "make" >> $(SPEC)

spec-install:
	@echo " " >> $(SPEC)
	@echo "%install" >> $(SPEC)
	@echo "make \"ROOT=\$$RPM_BUILD_ROOT\" install" >> $(SPEC)

spec-clean:
	@echo " " >> $(SPEC)
	@echo "%clean" >> $(SPEC)

spec-files:
	@echo " " >> $(SPEC)
	@echo "%files" >> $(SPEC)
	@echo "%defattr(-, root, root, -)" >> $(SPEC)
#	@echo "/$(SRT).tar.gz" >> $(SPEC)
	@for s in $(SUBDIRS); do (make -C $$s -s spec-files); done >> $(SPEC)

spec-changelog:
	@echo " " >> $(SPEC)
	@echo "%changelog" >> $(SPEC)
	@echo "* release `cat rel.num`" >> $(SPEC)

$(RPM): rhdirs $(STB) $(SPEC) 
	@cp $(STB) $(RPMDIR)/SOURCES
	(cd $(RPMDIR)/SPECS; rpmbuild -ba $(SPEC))
