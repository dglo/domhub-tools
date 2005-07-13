.c.o:
	gcc -Wall -g -O -c $<

EXPS=cb-version.exp ib-versions.exp
AWKS=dom.awk dor.awk tcal-calc.awk tcal-cvt.awk tcal.awk
SHS=configboot.sh domstate.sh echo-mode.sh \
	iceboot.sh insrel.sh ldall.sh \
	tcal-kalle.sh tcal-stf.sh tcal.sh versions.sh \
	softboot.sh domhub-version.sh
CSHS=common.sh
PROGS=se tcalcycle domserv domterm decodetcal

all: $(PROGS)

se: se.o
	gcc -g -o se se.o -lutil

tcalcycle: tcalcycle.o
	gcc -g -o tcalcycle tcalcycle.o

decodetcal: decodetcal.o
	gcc -g -o decodetcal decodetcal.o

decodemoni: decodemoni.o
	gcc -g -o decodemoni decodemoni.o

decodeeng: decodeeng.o
	gcc -g -o decodeeng decodeeng.o

domterm: domterm.o
	gcc -g -o domterm domterm.o

domserv: domserv.o
	gcc -g -o domserv domserv.o -lutil

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

