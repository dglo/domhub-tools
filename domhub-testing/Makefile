.c.o:
	gcc -c -Wall $<

all: echo-test open-test mjb-run-test mjb-sched

echo-test: echo-test.c
	gcc -o echo-test -Wall echo-test.c

mjb-run-test: mjb-run-test.o mjb-util.o
	gcc -o mjb-run-test -Wall mjb-run-test.o mjb-util.o

mjb-sched: mjb-sched.o mjb-util.o
	gcc -o mjb-sched -Wall mjb-sched.o mjb-util.o

open-test: open-test.c
	gcc -o open-test -Wall open-test.c

clean:
	rm -f echo-test open-test mjb-run-test mjb-sched *.o

BIN=echo-test open-test mjb-run-test mjb-sched
TESTS=current-test.sh domid-test.sh echo-test.sh echo-throttle-test.sh \
	fpga-reload-test.sh quiet-test.sh run-test.sh sink-test.sh \
	slow-open-test.sh softboot-test.sh source-test.sh tcal-test.sh \
	temp-test.sh wiggle-test.sh wr-block-test.sh throughput.sh

RESULTS=domid-results.sh quiet-results.sh softboot-results.sh \
	throughput-all-results.sh throughput-AB.sh echo-results.sh \
	echo-throttle-results.sh sink-results.sh source-results.sh \
	tcal-results.sh
QUERIES=details-qry.sh error-qry.sh even-schedule-qry.sh results-qry.sh

ROOT=
BINPATH=$(ROOT)/usr/local/bin
SHAREPATH=$(ROOT)/usr/local/share/domhub-testing

install: all
	@mkdir -p $(SHAREPATH)
	install -D $(BIN) $(TESTS) $(RESULTS) $(QUERIES) mjb.sh run-mjb.sh \
		tests.txt \
		$(SHAREPATH)
	@cd $(SHAREPATH); \
		ln -f throughput-AB.sh throughput-A-results.sh; \
		ln -f throughput-AB.sh throughput-B-results.sh
	@mkdir -p $(BINPATH)
	ln -f $(SHAREPATH)/run-mjb.sh $(BINPATH)/run-mjb

spec-files:
	@echo $(SHAREPATH)
	@echo $(BINPATH)/run-mjb

