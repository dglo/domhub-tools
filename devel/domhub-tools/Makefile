all: se tcalcycle domterm domserv xovr rtcalc

rtcalc: rtcalc.c
	gcc -Wall -g -O -o rtcalc rtcalc.c

xovr: xovr.c
	gcc -Wall -g -O -o xovr xovr.c

se: se.c
	gcc -Wall -g -o se se.c -lutil

tcalcycle: tcalcycle.c
	gcc -Wall -g -o tcalcycle tcalcycle.c

domterm: domterm.c
	gcc -Wall -g -o domterm domterm.c

domserv: domserv.c
	gcc -Wall -g -o domserv domserv.c -lutil

EXPS=cb-version.exp ib-versions.exp
AWKS=dom.awk dor.awk tcal-calc.awk tcal-cvt.awk tcal.awk
SHS=configboot.sh domstate.sh echo-mode.sh \
	iceboot.sh insrel.sh ldall.sh \
	tcal-kalle.sh tcal-stf.sh tcal.sh versions.sh \
        softboot.sh
CSHS=common.sh

install: se tcalcycle domserv domterm rtcalc
	install -D se tcalcycle domserv domterm rtcalc /usr/local/bin
	@mkdir -p /usr/local/share/domhub-tools
	install -D $(AWKS) $(CSHS) $(SHS) $(EXPS) /usr/local/share/domhub-tools
	for f in $(SHS); do \
		lnnm=`echo $$f | sed 's/.sh$$//1'`; \
		ln -f /usr/local/share/domhub-tools/$${f} \
			/usr/local/bin/$${lnnm}; \
	done

uninstall:
	cd /usr/local/bin; rm se tcal

clean:
	rm -f domterm domserv se tcalcycle *.o

