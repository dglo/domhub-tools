SUBDIRS=domhub-tools domhub-testing
REL=$(shell cat rel.num)
SRT=domhub-tools-$(REL)
# hmmm... redhat and debian have this in different places...
#RPMDIR=/usr/src/rpm
RPMDIR=/usr/src/redhat
RPM=$(RPMDIR)/RPMS/i386/$(SRT)-1.i386.rpm
SPEC=$(RPMDIR)/SPECS/domhub-tools.spec
STB=$(SRT).tar.gz
FILES=domhub-tools.description Makefile rel.num ChangeLog

all:
	@for dir in $(SUBDIRS); do (cd $$dir && make ); done

clean:
	@for dir in $(SUBDIRS); do (cd $$dir && make clean ); done

install:
	@for dir in $(SUBDIRS); do (cd $$dir && make install ); done
	install -D rel.num /usr/local/share/domhub-tools/rel.num

$(STB): clean
	@if [[ ! -f rel.num ]]; then echo 100 > rel.num; fi
	@mkdir $(SRT)
	@tar cf - $(SUBDIRS) $(FILES) | ( cd $(SRT); tar xf - )
	@tar cf - $(SRT) | gzip -c > $(STB)
	@rm -rf $(SRT)
	@echo created: $(STB)

release:
	@scp $(STB) arthur@glacier.lbl.gov:public_html/domhub-tools
	@scp $(RPM) arthur@glacier.lbl.gov:public_html/rpms
	@cg tag rel-$(REL)
	@gzip -dc $(STB) | tar xf -
	@(cd $(SRT) && cvs import -m "release `cat rel.num`" domhub-tools/rel-200 rel-2xx rel-$(REL))
	@rm -rf $(SRT)
	@echo "`cat rel.num` 1 + p" | dc > rel.num.2
	@mv rel.num.2 rel.num
	@scp ChangeLog arthur@glacier.lbl.gov:public_html/domhub-tools

rpm: $(RPM)

$(SPEC): spec-header spec-description spec-prep spec-build spec-install \
	spec-clean spec-files

spec-header:
	@echo "Summary: dom manipulation and testing programs" > $(SPEC)
	@echo "Name: domhub-tools" >> $(SPEC)
	@echo "Version: `cat rel.num`" >> $(SPEC)
	@echo "Release: 1" >> $(SPEC)
	@echo "Copyright: GPL" >> $(SPEC)
	@echo "Group: Applications/System" >> $(SPEC)
	@echo "Source: http://glacier.lbl.gov/\~arthur/domhub-tools/domhub-tools-`cat rel.num`.tar.gz" >> $(SPEC)
	@echo "%define __check_files %{nil}" >> $(SPEC)
spec-description:
	@echo " " >> $(SPEC)
	@echo "%description" >> $(SPEC)
	@cat domhub-tools.description >> $(SPEC)

spec-prep:
	@echo " " >> $(SPEC)
	@echo "%prep" >> $(SPEC)
	@echo "%setup" >> $(SPEC)

spec-build:
	@echo " " >> $(SPEC)
	@echo "%build" >> $(SPEC)
	@echo "make" >> $(SPEC)

spec-install:
	@echo " " >> $(SPEC)
	@echo "%install" >> $(SPEC)
	@echo "make install" >> $(SPEC)

spec-clean:
	@echo " " >> $(SPEC)
	@echo "%clean" >> $(SPEC)

spec-files:
	@echo " " >> $(SPEC)
	@echo "%files" >> $(SPEC)
	@for s in $(SUBDIRS); do (make -C $$s -s spec-files); done >> $(SPEC)

spec-changelog:
	@echo " " >> $(SPEC)
	@echo "%changelog" >> $(SPEC)
	@echo "* release `cat rel.num`" >> $(SPEC)

$(RPM): $(STB) $(SPEC)
	@cp $(STB) $(RPMDIR)/SOURCES
	(cd $(RPMDIR)/SPECS; rpmbuild -ba $(SPEC))