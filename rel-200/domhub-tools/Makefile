.c.o:
	gcc -Wall -g -O -c $<

EXPS=cb-version.exp ib-versions.exp
AWKS=tcal-cvt.awk tcal.awk
SHS=configboot.sh domstate.sh echo-mode.sh \
	iceboot.sh insrel.sh ldall.sh \
	tcal-kalle.sh tcal-stf.sh tcal.sh versions.sh \
	softboot.sh domhub-version.sh pwr.sh flash.sh ldfb.sh
CSHS=common.sh
PROGS=se tcalcycle domserv domterm decodetcal rtcalc chkgps gps2a \
	xmln xovr

all: $(PROGS)

xovr: xovr.c
	gcc -o xovr -Wall -O -g xovr.c

xmln: xmln.c
	gcc -o xmln -Wall -O -g xmln.c -lexpat

se: se.o
	gcc -g -o se se.o -lutil

tcalcycle: tcalcycle.o
	gcc -g -o tcalcycle tcalcycle.o

decodetcal: decodetcal.o
	gcc -g -o decodetcal decodetcal.o

domterm: domterm.o
	gcc -g -o domterm domterm.o

domserv: domserv.o
	gcc -g -o domserv domserv.o -lutil

chkgps: chkgps.o
	gcc -g -o chkgps chkgps.o

gps2a: gps2a.o
	gcc -g -o gps2a gps2a.o

install: $(PROGS)
	install -D $(PROGS) /usr/local/bin
	@mkdir -p /usr/local/share/domhub-tools
	install -D $(AWKS) $(CSHS) $(SHS) $(EXPS) /usr/local/share/domhub-tools
	for f in $(SHS); do \
		lnnm=`echo $$f | sed 's/.sh$$//1'`; \
		ln -f /usr/local/share/domhub-tools/$${f} \
			/usr/local/bin/$${lnnm}; \
	done

uninstall:
	cd /usr/local/bin; rm $(PROGS)

clean:
	rm -f $(PROGS) *.o

spec-files:
	@echo /usr/local/share/domhub-tools
	@for f in $(PROGS); do echo /usr/local/bin/$${f}; done
	@for f in $(SHS); do \
		lnnm=`echo $$f | sed 's/.sh$$//1'`; \
		echo /usr/local/bin/$${lnnm}; \
	done
