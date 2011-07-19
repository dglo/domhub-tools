SUBDIRS=domhub-tools domhub-testing
RELEASE=rel-$(shell /bin/bash -c 'cat rel.num' )

all:
	@for dir in $(SUBDIRS); do (cd $$dir && make ); done

rpm:
	./dorpm $(RELEASE)

clean:
	@for dir in $(SUBDIRS); do (cd $$dir && make clean ); done

install:
	@for dir in $(SUBDIRS); do (cd $$dir && make install ); done
	install -D rel.num /usr/local/share/domhub-tools/rel.num

release: clean
	@if [[ ! -f rel.num ]]; then echo 100 > rel.num; fi
	@mkdir "domhub-tools-`cat rel.num`"
	@tar cf - $(SUBDIRS) Makefile rel.num | \
		(cd "domhub-tools-`cat rel.num`"; tar xf -)
	@tar cf - "domhub-tools-`cat rel.num`" | gzip -c > \
		domhub-tools-`cat rel.num`.tar.gz
	@rm -rf "domhub-tools-`cat rel.num`"
	@echo "created: domhub-tools-`cat rel.num`.tar.gz"
	@echo "`cat rel.num` 1 + p" | dc > rel.num.2
	@mv rel.num.2 rel.num
