all: echo-test open-test

echo-test: echo-test.c
	gcc -o echo-test -Wall echo-test.c

open-test: open-test.c
	gcc -o open-test -Wall open-test.c

clean:
	rm -f echo-test open-test

<<<<<<< Makefile
install:
	mkdir -p /usr/local/share/domhub-testing
	cp * /usr/local/share/domhub-testing

=======
BIN=echo-test open-test
TESTS=current-test.sh domid-test.sh echo-test.sh echo-throttle-test.sh \
	fpga-reload-test.sh quiet-test.sh run-test.sh sink-test.sh \
	slow-open-test.sh softboot-test.sh source-test.sh tcal-test.sh \
	temp-test.sh wiggle-test.sh wr-block-test.sh throughput.sh

RESULTS=domid-results.sh quiet-results.sh softboot-results.sh \
	throughput-all-results.sh throughput-AB.sh echo-results.sh \
	echo-throttle-results.sh sink-results.sh source-results.sh \
	tcal-results.sh
QUERIES=details-qry.sh error-qry.sh even-schedule-qry.sh results-qry.sh

install: all
	@mkdir -p /usr/local/share/domhub-testing
	install -D $(BIN) $(TESTS) $(RESULTS) $(QUERIES) mjb.sh run-mjb.sh \
		tests.txt \
		/usr/local/share/domhub-testing
	@cd /usr/local/share/domhub-testing; \
		ln -f throughput-AB.sh throughput-A-results.sh; \
		ln -f throughput-AB.sh throughput-B-results.sh
	@mkdir -p /usr/local/bin
	ln -f /usr/local/share/domhub-testing/run-mjb.sh /usr/local/bin/run-mjb
>>>>>>> 1.6
