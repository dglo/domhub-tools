/* domapptest.c
   John Jacobsen, jacobsen@npxdesigns.com, for LBNL/IceCube
   Started June, 2004
   $Id: domapptest.c,v 1.16 2005-05-26 20:26:01 jacobsen Exp $

   Tests several functions of DOMapp directly through the 
   DOR card interface/driver, bypassing any Java or network
   peculiarities.

*/

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <fcntl.h>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <time.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h> /* for EAGAIN */
#define _GNU_SOURCE
#include <getopt.h>
#include <sys/poll.h>

int usage(void) {
  fprintf(stderr, 
	  "Usage:\n"
	  "  domapptest [options] <DOM>\n"
	  "  <DOM> is of the form 00a, 00A, or /dev/dhc0w0dA\n"
	  "  [options] are any of:\n"
	  "    -h help: show this message\n"
	  "    -v show slightly more verbose output\n"
	  "    -V ask domapp for its release version\n"
	  "    -Q get DOM ID from DOM\n"
	  "    -c change mode from Iceboot to domapp first\n"
	  "    -s stuffing mode for maximum bandwidth\n"
	  "    -d run duration, seconds (default 10)\n"
	  "    -S <dac>,<val> Set DAC <dac> to <val>.  <dac> numeric only, sorry.\n"
	  "       Repeatable.\n"
	  "  Periodic message types:\n"
	  "    -E <freq>: Run echo test w/ relative frequency <freq>\n"
	  "    -M <freq>: Collect monitor data w/ relative frequency <freq>\n"
	  "    -H <freq>: Collect hit data w/ relative frequency <freq>\n"
	  "    -D <DAC#>,<minval>,<maxval>,<freq>:\n"
	  "       Set DAC <DAC#> w/ frequency <freq>,\n"
	  "       random integer values from <minval> to <maxval>, inclusive\n"
	  "  Monitoring:\n"
	  "    -w <sec>: Tell domapp to generate HW moni recs every <sec> seconds\n"
	  "    -f <sec>: Tell domapp to generate config moni recs every <sec> seconds\n"
	  "    -m <file>: Write monitoring data to <file>\n"
	  "  Hit data:\n"
	  "    -B Initiate triggering/data taking (do not use w/ -u option)\n"
	  "    -i <file>: Write hit data to <file>\n"
	  "    -T <trigmode>:\n"
	  "       Set trigger mode to <trigmode> (0=testpat 1=cpu 2=disc)\n"
          "    -Z <mode>: Set hit data compression mode (0==uncompressed 1==roadgrader)\n"
          "    -o: Test repeated collection of pedestals\n"
	  "    -X <mode>: Set hit data format (0==engineering format 1==raw)\n"
	  "    -A <ATWD>: Select ATWD (0 or 1) for hit data\n"
	  "    -N <nch0>,<nch1>,<nch2>,<nch3>: Number of samples (0,16,32,64,128)\n"
	  "                                    for each ATWD channel\n"
	  "    -W <wch0>,<wch1>,<wch2>,<wch3>: Sample width (1 or 2 bytes), each chan.\n"
	  "    -F <num>: Read out <num> (0..255) ATWD samples\n"
	  "    -I <mode>,<pre>,post>: Require local coincidence,\n"
	  "       with the two time windows given in nsec.\n"
	  "       Mode=1 (upper and lower enabled) 2 (upper only) 3 (lower only)\n"
	  "    -R <a0>,<a1>,<a2>,<a3>,<f> Set road-grader thresholds for both ATWDs and FADC\n"
	  "    -p: Run pulser to generate SPE triggers in absence of real PMT\n"
	  "    -P <rate>: Set pulser/heartbeat rate to <rate> Hz\n"
	  "    -L <Volts>: Set DOM high voltage (BE CAREFUL!). Volts == DAC units/2.\n"
	  "    -K <file>,<freq>,<mode>,<deadtime>: collect supernova data in file <file>; \n"
	  "       frequency is relative to hit, moni etc. messages.  \n"
	  "       Mode 0=spe, 1=mpe; deadtime in [6400, 512000].\n"
	  "  Flasher board interface:\n"
	  "    -z Fetch flasher board ID\n"
	  "    -u <bright>,<win>,<delay>,<mask>,<rate>: Flasher board run.  Do not use\n"
	  "       with -B option.\n"
	  "  Roll-your-own Custom Messages:\n"
	  "    -C <type>,<subtype> E.g., -C 4,12 gives EXPCONTROL_BEGIN_RUN message.\n"
	  );
  return 0;
}

#include "domapp.h"

#define MAX_MSGS_IN_FLIGHT    8 /* Don't queue more than 8 msgs at a time */
#define MAX_MSG_BYTES      8092
#define MAXIDLE             500
#define READCYCLE            10
#define DO_TEST_INJECT        0 /* Set to true if you want to inject test data */
#define MINLCWIN            100
#define MAXLCWIN           6200
#define MAXDACS              50
#define MAXFILENAME         512
#define ATWDCHSIZ           128
#define FADCSIZ             256

int is_printable(char c) { return c >= 32 && c <= 126; }
char printable(char c) { return is_printable(c) ? c : '.'; }
void showbuf(unsigned char *buf, int n);
void show_fpga(int icard);
int getBufSize(char *procFile);
int getDevFile(char *filename, int len, char *arg);
void drainMsgs(int filep, unsigned char * rdbuf, int bufsiz, int showIt, int timeOutTrials);
void fillEchoMessageData(DOMMSG *m, int max);
int * getCycle(int efreq, int mfreq, int hfreq, int dfreq, int sfreq);
int getRandInt(int min, int max);
int resetLBM(int filep, int bufsiz);
int beginRun(int filep, int bufsiz, int dopulser);
int beginFBRun(int filep, int bufsiz, unsigned short bright,
               unsigned short win, short delay, unsigned short mask, unsigned short rate);
int endRun(int filep, int bufsiz, int dopulser);
int setUpLC(int filep, int bufsiz, int mode, int pre_ns, int post_ns);
int clearLC(int filep, int bufsiz);
int turnOffLC(int filep, int bufsiz);
int setUpSN(int filep, int bufsiz, int snmode, int sndeadt);
int turnOffSN(int filep, int bufsiz);
int testPedestalCollection(int filep, int bufsiz);
int setUpPedsAndThresholds(int filep, int bufsiz, int dothresh, 
			   unsigned short atwdthresh[], 
			   unsigned short fadc_thresh);
int setHighVoltage(int filep, int bufsiz, int hv);
int highVoltageOff(int filep, int bufsiz);
int setPulserRate(int filep, int bufsiz, int rate);
int setCompression(int filep, int bufsiz, int mode);
int setDataFormat(int filep, int bufsiz, int mode);
void turnOffPeriodicMonitoring(int filep, int bufsiz);

#define EMPTY  0
#define ECHO   1
#define MONI   2
#define HITS   3
#define SETDAC 4
#define SN     5
char *msgstr[6] = {
  "EMPTY", "ECHO", "MONITOR", "HIT", "SETDAC", "SN"
};
static unsigned long long msgBytes[6];
static unsigned long msgs[6];

static unsigned short pedavg[2][4][ATWDCHSIZ];
static unsigned short fadcavg[FADCSIZ];
unsigned short atwd_thresh[4], fadc_thresh;



int main(int argc, char *argv[]) {
  unsigned char rdbuf[MAX_MSG_BYTES];
# define BSIZ 512
  char filename[BSIZ];

  srand((int) getpid());

  /************* Process command arguments ******************/

  int bufsiz=getBufSize("/proc/driver/domhub/bufsiz");
  if(sizeof(DOMMSG) < bufsiz) {
    printf("Error: sizeof(DOMMSG)=%d, driver bufsiz=%d, bufsiz too big.\n", 
	   sizeof(DOMMSG), bufsiz);
    exit(-1);
  }

  int doChangeState = 0;
  int secDuration   = 10;
  int stuffit       = 0;
  int hwival        = 0;
  int cfival        = 0;
  int efreq         = 0;
  int mfreq         = 0;
  int hfreq         = 0;
  int dfreq         = 0;
  int dacnum        = 0;
  int dacmin        = 0;
  int dacmax        = 0;
  int savemoni      = 0;
  int verbose       = 0;
  int askversion    = 0;
  int savehits      = 0;
  int trigMode      = 0;
  int pulserRate    = 0;
  int doPulserRate  = 0;
  int dopoll        = 0;
  int nsamps[4] = {0,0,0,0}, sampwids[4] = {2,2,2,2}, nadc = 0;
  int doCustom      = 0;
  int custType, custSubType;
  char monifile[MAXFILENAME];
  char hitsfile[MAXFILENAME];
  char snfile[MAXFILENAME];
  int monifd, hitsfd;
  int defineTrig    = 0;
  int defineEngrFmt = 0;
  int inflight      = 0;
  int dohitbuf       = 0;
  int setthresh     = 0;
  int defineATWD    = 0;
  int whichATWD     = 0;
  int dohv          = 0;
  int hvdac         = 0;
  int getDOMID      = 0;
  int dopulser      = 0;
  unsigned short dacs[MAXDACS],dacvals[MAXDACS];
  int dac,val,ndacs=0;
  int lcmode;
  int dofbid = 0;
  int dofbrun = 0;
  unsigned short bright, win, mask, rate;
  short delay;
  int dolc = 0, pre_ns, post_ns;
  unsigned long long dtrwmin = 0, dtrwmax = 0;
  int doFmt = 0, fmtMode = 0;
  int doComp = 0, compMode = 0;
  int doCompTest = 0; 
  int dosn = 0, snmode, sndeadt, sfreq=0;

  while(1) {
    char c = getopt(argc, argv, 
		    "QVovhcBOspzi:d:E:M:H:D:m:w:f:T:N:"
		    "W:F:C:R:A:S:L:I:P:Z:X:K:u:");
    if (c == -1) break;

    switch(c) {
    case 'Q': getDOMID = 1; break;
    case 'o': doCompTest = 1; break;
    case 'c': doChangeState = 1; break;
    case 'd': secDuration = atoi(optarg); break;
    case 's': stuffit = 1; break;
    case 'z': dofbid = 1; break;
    case 'X': doFmt = 1; fmtMode = atoi(optarg); break;
    case 'Z': doComp = 1; compMode = atoi(optarg); break;
    case 'A': whichATWD = atoi(optarg); defineATWD = 0; break;
    case 'E': efreq = atoi(optarg); dopoll = 1; break;
    case 'M': mfreq = atoi(optarg); dopoll = 1; break;
    case 'H': hfreq = atoi(optarg); dopoll = 1; break;
    case 'B': dohitbuf = 1; break;
    case 'p': dopulser = 1; break;
    case 'P': doPulserRate = 1; pulserRate = atoi(optarg); break;
    case 'u':
      if(sscanf(optarg, "%hu,%hu,%hd,%hu,%hu", &bright,&win,&delay,&mask,&rate)!=5) exit(usage());
      dofbrun = 1;
      break;
    case 'K': 
      if(sscanf(optarg, "%d,%d,%d,%s", 
		&sfreq, &snmode, &sndeadt, snfile)!=4) exit(usage());
      dosn = 1;
      break;
    case 'I': 
      if(sscanf(optarg, "%d,%d,%d", &lcmode,
		&pre_ns, &post_ns)!=3) exit(usage());
      dolc = 1;
      break;
     case 'R': 
       if(sscanf(optarg, "%hu,%hu,%hu,%hu,%hu", 
		 &atwd_thresh[0],&atwd_thresh[1],&atwd_thresh[2],&atwd_thresh[3],
		 &fadc_thresh)!=5) exit(usage());
      setthresh = 1;
      break;
    case 'D': 
      if(sscanf(optarg, "%d,%d,%d,%d", &dacnum,&dacmin,&dacmax,&dfreq)!=4) 
	exit(usage()); 
      break;
    case 'T': 
      if(sscanf(optarg, "%d", &trigMode)!=1) exit(usage()); 
      defineTrig = 1;
      break;
    case 'N': 
      if(sscanf(optarg, "%d,%d,%d,%d", &nsamps[0],&nsamps[1],&nsamps[2],&nsamps[3])!=4) 
	exit(usage()); 
      defineEngrFmt = 1;
      break;
    case 'W': 
      if(sscanf(optarg, "%d,%d,%d,%d", &sampwids[0],&sampwids[1],&sampwids[2],&sampwids[3])!=4) 
	exit(usage()); 
      defineEngrFmt = 1;
      break;
    case 'C': 
      if(sscanf(optarg, "%d,%d", &custType, &custSubType)!=2)
	exit(usage()); 
      doCustom = 1; break;
    case 'F': 
      if(sscanf(optarg, "%d", &nadc) != 1) exit(usage()); 
      defineEngrFmt = 1;
      break;
    case 'm': 
      if(sscanf(optarg,"%s",monifile)!=1) exit(usage());
      savemoni = 1; 
      break;
    case 'i': 
      if(sscanf(optarg,"%s",hitsfile)!=1) exit(usage());
      savehits = 1; 
      break;
    case 'w': hwival = atoi(optarg); break;
    case 'f': cfival = atoi(optarg); break;
    case 'L': dohv = 1; hvdac = atoi(optarg)*2; break;
    case 'S': 
      if(sscanf(optarg, "%d,%d", &dac, &val)!=2) { fprintf(stderr,"Bad arg. format!\n"); exit(usage()); }
      if(dac<0 || val<0) { fprintf(stderr,"DAC values must be positive!\n"); exit(-1); }
      if(ndacs >= MAXDACS) { fprintf(stderr,"Too many DAC values specified!\n"); exit(-1); }
      dacs[ndacs] = dac; 
      dacvals[ndacs++] = val;
      break;
    case 'v': verbose = 1; break;
    case 'V': askversion = 1; break;
    case 'h':
    default: exit(usage());
    }
  }

  /* Validate LC arguments */
  if(dolc && ((pre_ns  < MINLCWIN || post_ns  > MAXLCWIN) ||
	      (lcmode < 1 || lcmode > 3))) {
    fprintf(stderr,"Error: LC windows must be between %d and %d,\n"
	   "mode between 1 and 3.\n", MINLCWIN, MAXLCWIN);
    exit(-1);
  }

  /* Validate engineering format arguments */
  if(nadc<0 || nadc>255) {
    fprintf(stderr,"Error: number of ADC samples must be between 0 and 255.\n");
    exit(-1);
  }

  int ich;
  for(ich=0;ich<4;ich++) {
    if(sampwids[ich] != 1 && sampwids[ich] != 2) {
      fprintf(stderr,"Error: sample widths must be 1 or 2.\n");
      exit(usage());
    }
    if(nsamps[ich] != 0 && nsamps[ich] != 16 && nsamps[ich] != 32
       && nsamps[ich] != 64  && nsamps[ich] != 128) {
      fprintf(stderr,"Error: number of ATWD samples must be 0, 16, 32, 64, or 128.\n");
      exit(usage());
    }
  }

  if(dfreq) 
    fprintf(stderr,"Will set DAC %d to values in the range [%d, %d] with a relative freq. %d.\n",
	   dacnum, dacmin, dacmax, dfreq);

  int argcount = argc-optind;

  if(argcount < 1) exit(usage());

  if(getDevFile(filename, BSIZ, argv[optind])) exit(usage());

  /* Determine message frequencies */
  if(!efreq && !mfreq && !hfreq && !dfreq && !sfreq) {
    fprintf(stderr,"No message types specified... won't poll domapp for data.\n");
  } 

  int * cyclic;
  if(dopoll) {
    cyclic = getCycle(efreq, mfreq, hfreq, dfreq, sfreq);
    if(!cyclic) { fprintf(stderr,"Malloc failed.\n"); exit(-1); }
    int showfreq = 0, il;
    for(il=0;showfreq && il<efreq+mfreq+hfreq+dfreq;il++) {
      fprintf(stderr,"Entry %d <- %s\n", il, msgstr[cyclic[il]]);
    }
  }

  /* Open file(s) */
  int filep = open(filename, O_RDWR);
  if(filep <= 0) {
    fprintf(stderr,"Can't open file %s (%d:%s)\n", filename, errno, strerror(errno));
    exit(-1);
  }   

  if(doCompTest) {
    if(testPedestalCollection(filep, bufsiz)) exit(-1);
    fprintf(stderr,"Done.\n");
    exit(0);
  }

  if(savemoni) {
    fprintf(stderr,"Will save monitoring data to file %s.\n", monifile);
    monifd = open(monifile, O_RDWR|O_TRUNC|O_CREAT, 0644);
    if(monifd <= 0) {
      fprintf(stderr,"Can't open file %s for output (%d:%s)\n", monifile, errno, strerror(errno));
      exit(-1);
    }
  }

  if(savehits) {
    fprintf(stderr,"Will save hit data to file %s.\n", hitsfile);
    hitsfd = open(hitsfile, O_RDWR|O_TRUNC|O_CREAT, 0644);
    if(hitsfd <= 0) {
      fprintf(stderr,"Can't open file %s for output (%d:%s)\n", hitsfile, errno, strerror(errno));
      exit(-1);
    }
  }

  /* Change mode to domapp if required */
# define DOMAPPSTR "domapp\r"
  if(doChangeState) {
    drainMsgs(filep, rdbuf, MAX_MSG_BYTES, 1, 10); /* Show iceboot msgs */
    int nw = write(filep, DOMAPPSTR, strlen(DOMAPPSTR));
    fprintf(stderr,"Wrote %d bytes.\n", nw);
    usleep(1000000);
    drainMsgs(filep, rdbuf, MAX_MSG_BYTES, 1, 20);
    usleep(3000000);  
  }

  /* Prepare downgoing echomessage */
  DOMMSG * echoMsg = newEchoMsg();
  if(echoMsg == NULL) { fprintf(stderr,"Can't get message buffer!\n"); exit(-1); }
  int maxSendData = bufsiz-MSG_HDR_LEN; /* Size of DATA PORTION */
  fillEchoMessageData(echoMsg, maxSendData);

  /* Prepare downgoing monitor request message */
  DOMMSG * moniMsg = newMoniMsg();
  if(moniMsg == NULL) { fprintf(stderr,"Can't get monitor message buffer!\n"); exit(-1); }

  /* Prepare "set DAC" message */
  DOMMSG * dacMsg = newSetDacMsg(dacnum, 0); /* Will set DAC value in main loop below */
  if(dacMsg == NULL) { fprintf(stderr,"Couldn't get dacMsg!\n"); exit(-1); }

  /* Prepare "get hits" message */
  DOMMSG * getHitsMsg = newGetHitDataMsg();
  if(getHitsMsg == NULL) { fprintf(stderr,"Couldn't get buffer for hit request message!\n"); exit(-1); }

  /* Prepare "get SN data" message */
  DOMMSG * getSNDataMsg = newGetSNDataMsg();
  if(getSNDataMsg == NULL) { 
    fprintf(stderr,"Couldn't get buffer for SN data request message!\n");
    exit(-1); 
  }

  DOMMSG * msgReply = (DOMMSG *) malloc(sizeof(DOMMSG));
  if(msgReply == NULL) { fprintf(stderr,"Couldn't get buffer for message reply!\n"); exit(-1); }

  /* Start clock */
  int lastdtsec = 0;

  int r;

  if(getDOMID) {
    char ID[MAX_DATA_LEN];
    if((r=domsg(filep, bufsiz, 1000,
                MESSAGE_HANDLER, MSGHAND_GET_DOM_ID,
                "+X", ID)) != 0) {
      fprintf(stderr,"MSGHAND_GET_DOM_ID failed: %d\n", r);
      exit(-1);
    }
    fprintf(stderr,"DOM ID is '%s'\n", ID);
  }

  if(dofbid) {
    char fbid[MAX_DATA_LEN];
    if((r=domsg(filep, bufsiz, 1000,
                DATA_ACCESS, DATA_ACC_GET_FB_SERIAL,
                "+X", fbid)) != 0) {
      fprintf(stderr,"DATA_ACC_GET_FB_SERIAL failed: %d\n", r);
      exit(-1);
    }
    fprintf(stderr,"Flasher board ID is '%s'\n", fbid);
  }

  if(askversion) {
    char version[MAX_DATA_LEN];
    if((r=domsg(filep, bufsiz, 1000, 
		MESSAGE_HANDLER, MSGHAND_GET_DOMAPP_RELEASE, 
		"+X", version)) != 0) {
      fprintf(stderr,"MSGHAND_GET_DOMAPP_RELEASE failed: %d\n", r); 
      exit(-1);
    }
    fprintf(stderr,"DOMApp version is '%s'\n", version);
  }

  if(doCustom) {
    fprintf(stderr,"Sending message type %d, subtype %d... ",custType, custSubType);
    if((r=domsg(filep, bufsiz, 1000,
                custType, custSubType, "")) != 0) {
      fprintf(stderr,"\ncustom message failed: %d\n", r); 
      exit(-1);
    }
    fprintf(stderr,"OK.\n");
  }

  if(hwival || cfival) {
    fprintf(stderr,"Setting monitoring intervals (hw=%d sec, cf=%d sec)... ", hwival, cfival);
    if((r=domsg(filep, bufsiz, 1000,
                DATA_ACCESS, DATA_ACC_SET_MONI_IVAL, 
		"-LL", (unsigned long) hwival, (unsigned long) cfival)) != 0) {
      fprintf(stderr,"DATA_ACC_SET_MONI_IVAL failed: %d\n", r);
      exit(-1);
    }
    fprintf(stderr,"OK.\n");
  }

  if(defineATWD) {
    if(whichATWD != 0 && whichATWD != 1) {
      fprintf(stderr,"Error: must select ATWD 0 or 1!\n\n");
      exit(usage());
    }
    fprintf(stderr,"Selecting ATWD %d... ", whichATWD);
    if((r=domsg(filep, bufsiz, 1000, DOM_SLOW_CONTROL, DSC_SELECT_ATWD, "-C",
		(unsigned char) whichATWD)) != 0) {
      fprintf(stderr,"DSC_SELECT_ATWD failed: %d\n", r);
      exit(-1);
    }
    fprintf(stderr,"OK.\n");
  }

  if(defineEngrFmt) {
    fprintf(stderr,"Setting ATWD format to %d(%d) %d(%d) %d(%d) %d(%d) (%d FADC samps)... ",
	   nsamps[0], sampwids[0],
	   nsamps[1], sampwids[1],
	   nsamps[2], sampwids[2],
	   nsamps[3], sampwids[3], nadc);
    unsigned char mask0, mask1;
    getMasks(&mask0, &mask1, nsamps, sampwids);
    if((r=domsg(filep, bufsiz, 1000, DATA_ACCESS, DATA_ACC_SET_ENG_FMT, "-CCC",
		(unsigned char) (nadc&0xFF), mask0, mask1)) != 0) {
      fprintf(stderr,"DATA_ACC_SET_ENG_FMT failed: %d\n", r);
      exit(-1);
    }
    fprintf(stderr,"OK.\n");
  }

  /* Set DACs to desired values */
  int idac;
  for(idac=0; idac<ndacs; idac++) {
    fprintf(stderr,"Setting DAC %d to %d... ", dacs[idac], dacvals[idac]);
    if((r=domsg(filep, bufsiz, 1000, DOM_SLOW_CONTROL, DSC_WRITE_ONE_DAC, "-CCS", 
		dacs[idac], 0, dacvals[idac])) != 0) {
      fprintf(stderr,"DSC_WRITE_ONE_DAC failed: %d\n", r);
      exit(-1);
    }
    fprintf(stderr,"OK.\n");
  }

  if(doPulserRate) {
    if(setPulserRate(filep, bufsiz, pulserRate)) exit(-1);
  }

  if(doFmt) {
    if(setDataFormat(filep, bufsiz, fmtMode)) exit(-1);
    //printf("turned off data format!\n\n\n");
  }

  if(doComp) {
    if(compMode == 1) {
      if(setUpPedsAndThresholds(filep, bufsiz, setthresh, 
				atwd_thresh, fadc_thresh)) exit(-1);
    }
    //printf("turned off compression!!!!!\n\n\n"); //
    if(setCompression(filep, bufsiz, compMode)) exit(-1);
  }

  if(defineTrig) {
    fprintf(stderr,"Setting trigger mode to %d... ", trigMode);
    if((r=domsg(filep, bufsiz, 1000, DOM_SLOW_CONTROL, DSC_SET_TRIG_MODE, "-C", 
		(unsigned char) trigMode)) != 0) {
      fprintf(stderr,"DSC_SET_TRIG_MODE failed: %d\n", r);
      exit(-1);
    }

    unsigned char trigModeCheck = 0xFF; 
    if((r=domsg(filep, bufsiz, 1000, DOM_SLOW_CONTROL, DSC_GET_TRIG_MODE, "+C",
		&trigModeCheck)) != 0) {
      fprintf(stderr,"DSC_GET_TRIG_MODE failed: %d\n", r);
      exit(-1);
    }
    if(trigModeCheck != trigMode) { 
      fprintf(stderr,"DSC_GET_TRIG_MODE failed: trigModeCheck=%d trigMode=%d\n", trigModeCheck, trigMode);
      exit(-1);
    }
    
    fprintf(stderr,"OK.\n");
  }

  int hvon = 0;
  if(dohv) {
    if(setHighVoltage(filep, bufsiz, hvdac)) exit(-1);
    hvon = 1;
  }

  /* Set up local coincidence event selection for buffering */
  if(dolc) {
    if(setUpLC(filep, bufsiz, lcmode, pre_ns, post_ns)) {
      fprintf(stderr,"Domapp local coincidence initialization failed.\n");
      exit(-1);
    }
  } else { /* If !dolc, then set mode to zero */
    clearLC(filep, bufsiz);
  }

  if(dohitbuf && dofbrun) {
    fprintf(stderr, "Flasher run is incompatible with normal run modes! (-B)\n");
    exit(-1);
  }

  /* Start data taking ... */
  if(dohitbuf && beginRun(filep, bufsiz, dopulser)) {
    fprintf(stderr,"Run start failed.\n");
    exit(-1);
  }

  /* ... or do flasher run... */
  if(dofbrun && beginFBRun(filep, bufsiz, bright, win, delay, mask, rate)) {
    fprintf(stderr,"Flasher run start failed.\n");
    exit(-1);
  }

  /* Set up supernova system, if desired */
  int snfd;
  if(dosn) {
    printf("%s %d %d", snfile, snmode, sndeadt);
    if(setUpSN(filep, bufsiz, snmode, sndeadt)) {
      fprintf(stderr,"Domapp supernova readout initialization failed.\n");
      exit(-1);
    }
    snfd = open(snfile, O_RDWR|O_TRUNC|O_CREAT, 0644);
    if(snfd <= 0) {
      fprintf(stderr,"Can't open file %s for output (%d:%s)\n", snfile, errno, strerror(errno));
      exit(-1);
    }
  }

  /* keep gettimeofday near beginRun to time run correctly */
  struct timeval tstart; 
  gettimeofday(&tstart, NULL);


  struct timeval lastTWrite, lastTRead;

  fprintf(stderr,"Entering periodic data collection loop...\n");
  /* Messaging loop */
  int idle = 0;
  int icyc = 0;
  int done = 0;

  if(dopoll) {
    while(1) {
      int gotread  = 0;
      int gotwrite = 0;
      
      /* Send message until driver input buffer is full or inflight gets too big */
      while(inflight < MAX_MSGS_IN_FLIGHT) {
	DOMMSG * msgToSend;
	int sendType;
	switch(cyclic[icyc]) {
	case MONI: sendType = MONI; msgToSend = moniMsg; break;
	case HITS: sendType = HITS; msgToSend = getHitsMsg; break;
	case SN:   sendType = SN;   msgToSend = getSNDataMsg; break;
	case SETDAC: 
	  sendType = SETDAC; 
	  setDacMsgDacValue(dacMsg, getRandInt(dacmin, dacmax));
	  msgToSend = dacMsg; 
	  break;
	case ECHO: 
	default: sendType = ECHO; msgToSend = echoMsg; break;
	}
	//fprintf(stderr,"sending type %d...\n",sendType);
	/* Write the message */
	int len = sendMsg(filep, msgToSend);
	inflight++;
	if(len == 0) {
	  fprintf(stderr,"Bad return value from sendMsg (%d)!\n", len);
	  exit(-1);
	} else if(len == -1 && errno == EAGAIN) {
	  break;
	} else if(len == -1) {
	  fprintf(stderr,"sendMsg gave -1, errno=%d (%s).\n", errno, strerror(errno));
	  exit(-1);
	} else {
	  icyc++; if(icyc >= efreq+mfreq+hfreq+dfreq+sfreq) icyc=0;
	  msgBytes[sendType] += len;
	  gotwrite = 1;
	  /* Remember time of last write */
	  gettimeofday(&lastTWrite, NULL);
	}
	if(!stuffit) break; /* Don't do any more unless stuffing mode */
      }

      int iread=0;
      while(1) {
	int len = getMsg(filep, msgReply, bufsiz, 100);
	if(len == -1) { // EAGAIN
	  usleep(1000);
	} else if(len < 0) {
	  fprintf(stderr,"getMsg gave %d -- quitting.\n", len);
	  exit(-1);
	} else {
	  //fprintf(stderr,"got subtype %d...\n",msgSubType(msgReply));
	  gotread = 1;
	  gettimeofday(&lastTRead, NULL);
	  unsigned long long dtrw = (lastTRead.tv_sec - lastTWrite.tv_sec)*1000000 + 
	    (lastTRead.tv_usec - lastTWrite.tv_usec);
	  if(dtrwmin == 0 || dtrw < dtrwmin) dtrwmin = dtrw;
	  if(dtrw > dtrwmax) dtrwmax = dtrw;
	  //fprintf(stderr,"dtrw=%llu min=%llu max=%llu usec\n", dtrw, dtrwmin, dtrwmax);
	  
	  //fprintf(stderr,"\nGot %d byte reply from domapp.\n", len);
	  int rmt    = msgType(msgReply);
	  int rmst   = msgSubType(msgReply);
	  int dlen   = msgDataLen(msgReply);
	  int status = msgStatus(msgReply);
	  if(status != 1) {
	    fprintf(stderr,"ERROR: bad status from domapp (%d).\n", status);
	    fprintf(stderr,"mt=%d mst=%d len=%d\n", rmt, rmst, dlen);
	    exit(-1);
	  } else {
	    inflight--;
	    if(rmt == MESSAGE_HANDLER && rmst == MSGHAND_ECHO_MSG) {
	      msgs[ECHO]++;
	      msgBytes[ECHO] += len;
	    } else if(rmt == DATA_ACCESS && rmst == DATA_ACC_GET_NEXT_MONI_REC) {
	      if(dlen && savemoni) {
		int nm = write(monifd, msgReply->data, dlen);
		if(nm != dlen) { fprintf(stderr,"Short write (%d of %d bytes) to monitoring stream.\n", 
					nm, dlen); exit(-1); }
	      }
	      msgs[MONI]++;
	      msgBytes[MONI] += len;
	    } else if(rmt == DOM_SLOW_CONTROL && rmst == DSC_WRITE_ONE_DAC) {
	      msgs[SETDAC]++;
	      msgBytes[SETDAC] += len;
	    } else if(rmt == DATA_ACCESS && rmst == DATA_ACC_GET_DATA) {
	      msgs[HITS]++;
	      msgBytes[HITS] += len;
	      if(dlen && savehits) {
		int nh = write(hitsfd, msgReply->data, dlen);
		if(nh != dlen) { 
		  fprintf(stderr,"Short write (%d of %d bytes) to hit data stream.\n",
			  nh, dlen); 
		  exit(-1); 
		}
	      }
	    } else if(rmt == DATA_ACCESS && rmst == DATA_ACC_GET_SN_DATA) {
	      msgs[SN]++;
	      msgBytes[SN] += len;
	      if(dlen) {
		int ns = write(snfd, msgReply->data, dlen);
		if(ns != dlen) { 
		  fprintf(stderr,"Short write (%d of %d bytes) to hit data stream.\n",
			  ns, dlen); 
		  exit(-1);
		}
	      }
	    } else {
	      fprintf(stderr,"Unknown message mt=%d mst=%d len=%d\n", rmt, rmst, dlen);
	    }
	  } /* status ok */
	} /* length ok */
	
	/* Terminating condition:
	   stuffing mode: performed READCYCLE attempts to read data 
	   non-stuff mode: got a message reply.
	   FIXME: look for timeouts */
	iread++;
	if(stuffit) {
	  if(iread >= READCYCLE) break; /* On to write */
	} else {
	  if(gotread) break;
	}      
      } /* read cycle */

      if(!gotread && !gotwrite) {
	idle++;
	usleep(1000);
      } else { /* Only report statistics if something new got through */
	idle = 0;
	/* Check for done, show rates, etc. */
	struct timeval tnow;
	gettimeofday(&tnow, NULL);
	unsigned long long dt = (tnow.tv_sec - tstart.tv_sec)*1000000 
	  + (tnow.tv_usec - tstart.tv_usec);
	int dtsec = tnow.tv_sec - tstart.tv_sec;
	int dtusec = tnow.tv_usec - tstart.tv_usec;
	if(dtusec < 0) {
	  dtusec += 1000000;
	  dtsec --;
	}
	if(dtsec != lastdtsec && dtsec != 0 
	   &&        ((int)dtsec <= 10 /* Periodic criteria */
	       || !((((int)dtsec)%10) && dtsec<100)
	       || !((((int)dtsec)%100)&& dtsec<1000) 
	       ||  !(((int)dtsec)%1000))) {
	  double totBytes = (double) msgBytes[ECHO] + (double) msgBytes[MONI] + 
	    (double) msgBytes[HITS] + (double) msgBytes[SETDAC] + (double) msgBytes[SN];
	  double echoDataRate = totBytes / (((double) dtsec)*1E3);
	  fprintf(stderr,"%d.%06ds: %lu echo, %lu moni, %lu hit, %lu dac, %lu sn, "
		  "%2.2fMB, %2.2f kB/sec", 
		  dtsec, dtusec, msgs[ECHO], msgs[MONI], msgs[HITS], msgs[SETDAC], msgs[SN],
		  totBytes/1E6, echoDataRate);
	  if(verbose) {
	    fprintf(stderr," dtmin=%llu dtmax=%llu", dtrwmin, dtrwmax);
	  }
	  fprintf(stderr,"\n");
	}

	if(dohitbuf && dtsec >= secDuration && ! done) {
	  if(endRun(filep, bufsiz, dopulser)) {
	    fprintf(stderr,"endRun failed.\n");
	    exit(-1);
	  }
	  if(dolc && turnOffLC(filep, bufsiz))
	    fprintf(stderr,"turnOffLC failed.\n");
	  if(dosn && turnOffSN(filep, bufsiz))
	    fprintf(stderr,"turnOffSN failed.\n");
	  if(hwival || cfival) 
	    turnOffPeriodicMonitoring(filep, bufsiz);
	  done = 1;
	}
	/* Turn off HV when duration is up so we can see it in 
	   monitoring stream */
	if(dtsec >= secDuration && dohv && hvon) {
	  hvon = 0;
	  highVoltageOff(filep, bufsiz); /* We'll do again @ end of loop to be sure */
	}

	/* Add 1 sec to run length after run stop to get last monitoring, etc. events */
	if(dtsec >= secDuration+1) {
	  fprintf(stderr,"Done (%lld usec).\n",dt);
	  break;
	}
	lastdtsec = dtsec;
      }

      if(idle > MAXIDLE) {
	fprintf(stderr,"No successful reads or writes in %d trials.  DOM died?\n", idle);
	exit(-1);
      }
    }
  } /* if(dopoll) */
  
  if(dohv) highVoltageOff(filep, bufsiz);

  free(dacMsg);
  free(msgReply);  
  free(echoMsg);
  drainMsgs(filep, rdbuf, MAX_MSG_BYTES, 0, 10);
  close(filep);
  if(savemoni) close(monifd);
  if(savemoni) close(hitsfd);
  free(cyclic);
  return 0;
}


void showbuf(unsigned char *buf, int n) {
  int cpl=16;
  int nl = n/cpl+1;
  fprintf(stderr,"%d bytes: \n", n); 
  int il, ic;
  for(il=0; il<nl; il++) {
    for(ic=0; ic<cpl; ic++) {
      int iof = il*cpl + ic;
      if(iof < n) {
	fprintf(stderr,"%c", printable(buf[iof])); 
      } else {
	fprintf(stderr," ");
      }
    }

    fprintf(stderr,"  ");
    for(ic=0; ic<cpl; ic++) {
      int iof = il*cpl + ic;
      if(iof < n) {
        fprintf(stderr,"%02x ", buf[iof]);
      } else {
	break;
      }
    }
    fprintf(stderr,"\n"); 
  }
  fprintf(stderr,"\n");
  
}


void show_fpga(int icard) {
  /* In case of hardware timeout from the driver, show the DOR FPGA for the appropriate DOR
     card */
  char cmdbuf[1024];
  snprintf(cmdbuf,1024,"cat /proc/driver/domhub/card%d/fpga",icard);
  fprintf(stderr,"Showing FPGA registers: %s.\n",cmdbuf);
  system(cmdbuf);
}


int getBufSize(char * procFile) {
  int bufsiz;
  FILE *bs;
  bs = fopen(procFile, "r");
  if(bs == NULL) {
    fprintf(stderr, "Can't open bufsiz proc file.  Driver not loaded?\n");
    return -1;
  }
  fscanf(bs, "%d\n", &bufsiz);
  fclose(bs);
  return bufsiz;
}

int getDevFile(char * filename, int len, char *arg) {
  /* copy at most len characters into filename based on arg.
     If arg is of the form "00a" or "00A", file filename
     as "/dev/dhc0w0dA"; otherwise return a copy of arg. */

  int icard, ipair;
  char cdom;
  if(len < 13) return 1;
  if(arg[0] >= '0' && arg[0] <= '7') { /* 00a style */
    icard = arg[0]-'0';
    ipair = arg[1]-'0';
    cdom = arg[2];
    if(cdom == 'a') cdom = 'A';
    if(cdom == 'b') cdom = 'B';
    if(icard < 0 || icard > 7) return 1;
    if(ipair < 0 || ipair > 3) return 1;
    if(cdom != 'A' && cdom != 'B') return 1;
    snprintf(filename, len, "/dev/dhc%dw%dd%c", icard, ipair, cdom);
  } else {
    memcpy(filename, arg, strlen(arg)>len?len:strlen(arg));
  }
  return 0;
}


void drainMsgs(int filep, unsigned char * rdbuf, int bufsiz, int showIt, int timeOutTrials) {
  /* if timeOutTrials is set, use that as max # of retries to drain messages 
     otherwise, just wait to drain 1 message */
  struct pollfd  pfd;

  int nr;
  int i = 0;
  pfd.events = POLLIN;
  pfd.fd     = filep;
  while(1) {
    if(!poll(&pfd, 1, 100) || !(pfd.revents & POLLIN)) return;
    nr = read(filep, rdbuf, bufsiz);
    if(nr > 0) {
      if(showIt) showbuf(rdbuf, nr);
      if(!timeOutTrials) return;
      i = 0;
    } else {
      i++;
      if(timeOutTrials && i>=timeOutTrials) {
	return;
      }
      usleep(1000);
    }
  }
}

void fillEchoMessageData(DOMMSG *m, int max) {
  setMsgDataLen(m, max);
  int i;
  for(i=0; i<max; i++) m->data[i] = i & 0xFF;
}

int * getCycle(int efreq, int mfreq, int hfreq, int dfreq, int sfreq) {
  int n = efreq+mfreq+hfreq+dfreq+sfreq;
  int denom = n;
  int * a = malloc(n*sizeof(int));
  if(!a) return NULL;
  int i;
  for(i=0;i<n; i++) {
    double x = rand()/(RAND_MAX+1.0);
    double eint = (double) efreq / (double) denom;
    double mint = (double) (efreq+mfreq) / (double) denom;
    double hint = (double) (efreq+mfreq+hfreq) / (double) denom;
    double sint = (double) (efreq+mfreq+hfreq+dfreq) / (double) denom;
    if(x < eint) {
      a[i] = ECHO;
      efreq--;
    } else if(x < mint) {
      a[i] = MONI;
      mfreq--;
    } else if(x < hint) {
      a[i] = HITS;
      hfreq--;
    } else if(x < sint) {
      a[i] = SETDAC;
      dfreq--;
    } else {
      a[i] = SN;
      sfreq--;
    }
    denom--;    
  }
  return a;
}



int endRun(int filep, int bufsiz, int dopulser) {
  int r;

  if((r=domsg(filep, bufsiz, 1000,
              EXPERIMENT_CONTROL, EXPCONTROL_END_RUN, "")) != 0) {
    fprintf(stderr,"EXPCONTROL_END_RUN failed: %d\n", r);
    return 1;
  }

  if(dopulser) {
    fprintf(stderr,"Turning off front-end pulser... ");
    if((r=domsg(filep, bufsiz, 1000, DOM_SLOW_CONTROL, DSC_SET_PULSER_OFF, ""))) {
      fprintf(stderr,"DSC_SET_PULSER_OFF failed: %d\n", r);
      exit(-1);
    }
    fprintf(stderr,"OK.\n");
  }

  return 0;
}

int clearLC(int filep, int bufsiz) {
  int r;
  if((r=domsg(filep, bufsiz, 1000,
	      DOM_SLOW_CONTROL, DSC_SET_LOCAL_COIN_MODE, "-C", 0)) != 0) {
    fprintf(stderr,"DSC_SET_LOCAL_COIN_MODE failed: %d\n", r);
    return 1;
  }
  return 0;
}

int setUpSN(int filep, int bufsiz, int snmode, int sndeadt) {
  int r;
  if((r=domsg(filep, bufsiz, 1000,
              DOM_SLOW_CONTROL, DSC_ENABLE_SN, "-LC", sndeadt, snmode)) != 0) {
    fprintf(stderr,"DSC_ENABLE_SN failed: %d\n", r);
    return 1;
  }
  return 0;
}

int turnOffSN(int filep, int bufsiz) {
  int r;
  if((r=domsg(filep, bufsiz, 1000,
              DOM_SLOW_CONTROL, DSC_DISABLE_SN, "")) != 0) {
    fprintf(stderr,"DSC_ENABLE_SN failed: %d\n", r);
    return 1;
  }
  return 0;
}

int setUpLC(int filep, int bufsiz, int mode,
	    int pre_ns, int post_ns) {
  int r;
  if((r=domsg(filep, bufsiz, 1000,
              DOM_SLOW_CONTROL, DSC_SET_LOCAL_COIN_WINDOW, "-LL", 
	      pre_ns, post_ns)) != 0) {
    fprintf(stderr,"DSC_SET_LOCAL_COIN_WINDOW failed: %d\n", r);
    return 1;
  }
  if((r=domsg(filep, bufsiz, 1000,
	      DOM_SLOW_CONTROL, DSC_SET_LOCAL_COIN_MODE, "-C", mode)) != 0) {
    fprintf(stderr,"DSC_SET_LOCAL_COIN_MODE failed: %d\n", r);
    return 1;
  }
  return 0;
}

int turnOffLC(int filep, int bufsiz) {
   int r;
   if((r=domsg(filep, bufsiz, 1000,
	       DOM_SLOW_CONTROL, DSC_SET_LOCAL_COIN_MODE, "-C", 0)) != 0) {
     fprintf(stderr,"DSC_SET_LOCAL_COIN_MODE failed: %d\n", r);
     return 1;
   }
   return 0;
}

int beginFBRun(int filep, int bufsiz, unsigned short bright,
	       unsigned short win, short delay, unsigned short mask, unsigned short rate) {
  int r;
  fprintf(stderr,"Starting flasher run... ");
  if((r=domsg(filep, bufsiz, 1000,
              EXPERIMENT_CONTROL, EXPCONTROL_BEGIN_FB_RUN, "-SSSSS",
	      bright, win, delay, mask, rate)) != 0) {
    fprintf(stderr,"EXPCONTROL_BEGIN_FB_RUN failed: %d\n", r);
    return 1;
  }
  fprintf(stderr,"OK.\n");
  return 0;
}

int beginRun(int filep, int bufsiz, int dopulser) {
  int r;

  if(dopulser) {
    fprintf(stderr,"Turning on front-end pulser... ");
    if((r=domsg(filep, bufsiz, 1000, DOM_SLOW_CONTROL, DSC_SET_PULSER_ON, ""))) {
      fprintf(stderr,"DSC_SET_PULSER_ON failed: %d\n", r);
      exit(-1);
    }
    fprintf(stderr,"OK.\n");
  }

  fprintf(stderr,"Starting run... ");
  if((r=domsg(filep, bufsiz, 1000,
	      EXPERIMENT_CONTROL, EXPCONTROL_BEGIN_RUN, "")) != 0) {
    fprintf(stderr,"EXPCONTROL_BEGIN_RUN failed: %d\n", r);
    return 1;
  }
  fprintf(stderr,"OK.\n");

  return 0;
}

int testPedestalCollection(int filep, int bufsiz) {
  int targetATWD0 = 1000;
  int targetATWD1 = 1000;
  int targetFADC  = 2000;
  unsigned long nped0, nped1, nadc;

  int r;
  int itrial; for(itrial=0; itrial<100; itrial++) {
    fprintf(stderr,"Ped. run %d\n", itrial);
    if((r=domsg(filep, bufsiz, 1000,
                EXPERIMENT_CONTROL, EXPCONTROL_DO_PEDESTAL_COLLECTION, "-LLL",
                targetATWD0, targetATWD1, targetFADC)) != 0) {
      fprintf(stderr,"EXPCONTROL_DO_PEDESTAL_COLLECTION failed: %d\n", r);
      return 1;
    }

    if((r=domsg(filep, bufsiz, 1000,
                EXPERIMENT_CONTROL, EXPCONTROL_GET_NUM_PEDESTALS, "+LLL",
                &nped0, &nped1, &nadc)) != 0) {
      fprintf(stderr,"EXPCONTROL_GET_NUM_PEDESTALS failed: %d.\n", r);
      return 1;
    }

    if(nped0 < targetATWD0 || nped1 < targetATWD1 || nadc < targetFADC) {
      fprintf(stderr,"Pedestal sums (%ld,%ld,%ld) are below targets (%d, %d, %d)!\n", 
	      nped0, nped1, nadc, targetATWD0, targetATWD1, targetFADC);
      return 1;
    }
  }
  return 0;
}

int setUpPedsAndThresholds(int filep, int bufsiz, int dothresh, 
			   unsigned short atwdthresh[],
			   unsigned short fadc_thresh) {
  int targetATWD0 = 1000;
  int targetATWD1 = 1000;
  int targetFADC  = 2000;
  unsigned long nped0, nped1, nadc;

  int r;
  if((r=domsg(filep, bufsiz, 1000,
	      EXPERIMENT_CONTROL, EXPCONTROL_DO_PEDESTAL_COLLECTION, "-LLL",
	      targetATWD0, targetATWD1, targetFADC)) != 0) {
    fprintf(stderr,"EXPCONTROL_DO_PEDESTAL_COLLECTION failed: %d\n", r);
    return 1;
  }

  if((r=domsg(filep, bufsiz, 1000,
	      EXPERIMENT_CONTROL, EXPCONTROL_GET_NUM_PEDESTALS, "+LLL",
	      &nped0, &nped1, &nadc)) != 0) {
    fprintf(stderr,"EXPCONTROL_GET_NUM_PEDESTALS failed: %d.\n", r);
    return 1;
  }
  
  if(nped0 < targetATWD0 || nped1 < targetATWD1 || nadc < targetFADC) {
    fprintf(stderr,"Pedestal sums (%ld,%ld,%ld) are below targets (%d, %d, %d)!\n", 
	    nped0, nped1, nadc, targetATWD0, targetATWD1, targetFADC);
    //fprintf(stderr,"SKIPPING enforcement of this check for now...\n");
    return 1;
  }
  
  fprintf(stderr,"Collected %ld ATWD0, %ld ATWD1 and %ld FADC pedestals.\n", nped0, nped1, nadc);

  /* Read out the pedestal averages -- too complicated to use domsg()... */
  DOMMSG * pedAvgs  = newGetPedestalAveragesMsg();
  if(pedAvgs == NULL) return 1;
  DOMMSG * msgReply = (DOMMSG *) malloc(sizeof(DOMMSG));
  if(msgReply == NULL) { free(pedAvgs); return 1; }

  if(sendAndReceive(filep, bufsiz, pedAvgs, msgReply, 100)) {
    fprintf(stderr,"Send-and-receive getPedestalAverages failed.\n");
    free(pedAvgs);
    return 1;
  } 
  free(pedAvgs);

  memset(pedavg, 0, 2*4*ATWDCHSIZ*sizeof(unsigned short));
  memset(fadcavg, 0, FADCSIZ*sizeof(unsigned short));

  int ichip, ich, isamp;
  int of = 0;

  for(ichip=0; ichip<2; ichip++) {
    for(ich=0; ich<4; ich++) {
      fprintf(stderr,"ATWD%d ch%d: ", ichip, ich);
      for(isamp=0; isamp<ATWDCHSIZ; isamp++) {
	pedavg[ichip][ich][isamp] = unformatShort(msgReply->data+of);
	of += 2;
	fprintf(stderr,"%hu ", pedavg[ichip][ich][isamp]);
      }
      fprintf(stderr,"\n");
    }
  }
  fprintf(stderr,"FADC ");
  for(isamp=0; isamp<FADCSIZ; isamp++) {
    fadcavg[isamp] = unformatShort(msgReply->data+of);
    of += 2;
    fprintf(stderr,"%hu ", fadcavg[isamp]);
  }
  fprintf(stderr,"\n");

  free(msgReply);

  /* Set baseline (RoadGrader) thresholds */
  if(dothresh) {
    if((r=domsg(filep, bufsiz, 1000,
		DATA_ACCESS, DATA_ACC_SET_BASELINE_THRESHOLD, "-S SSSS SSSS",
		fadc_thresh,
		atwdthresh[0], atwdthresh[1], atwdthresh[2], atwdthresh[3],
		atwdthresh[0], atwdthresh[1], atwdthresh[2], atwdthresh[3])) != 0) {
      fprintf(stderr,"DATA_ACC_SET_BASELINE_THRESHOLD failed: %d.\n", r);
      return 1;
    }
  }

  if((r=domsg(filep, bufsiz, 1000,
	      DATA_ACCESS, DATA_ACC_GET_BASELINE_THRESHOLD, "+S SSSS SSSS",
	      &fadc_thresh,
	      &atwdthresh[0], &atwdthresh[1], &atwdthresh[2], &atwdthresh[3],
	      &atwdthresh[0], &atwdthresh[1], &atwdthresh[2], &atwdthresh[3])) != 0) {
    fprintf(stderr,"DATA_ACC_GET_BASELINE_THRESHOLD failed: %d.\n", r);
    return 1;
  }


  for(ich=0; ich<4; ich++) {
    fprintf(stderr,"ATWD ch%d: threshold=%d\n", ich, atwdthresh[ich]);
  }
  fprintf(stderr,"FADC threshold = %d\n", fadc_thresh);

  return 0;
}

int getRandInt(int min, int max) {
  if(min == max) return min;
  double x = rand()/(RAND_MAX+1.0);
  int n = max-min+1;
  return min + (int) (x*n);
}


int setPulserRate(int filep, int bufsiz, int rate) {
  int r;
  fprintf(stderr,"Setting pulser rate to %d Hz... ", rate);
  if((r=domsg(filep, bufsiz, 1000,
              DOM_SLOW_CONTROL, DSC_SET_PULSER_RATE, "-S", (unsigned short) rate)) != 0) {
    fprintf(stderr,"DSC_SET_PULSER_RATE failed: %d\n", r);
    return 1;
  } else {
    fprintf(stderr,"OK.\n");
  }
  return 0;
}

int setCompression(int filep, int bufsiz, int mode) {
  int r;
  fprintf(stderr,"Setting DOM Data compression type to %d... ", mode);
  if((r=domsg(filep, bufsiz, 1000,
	      DATA_ACCESS, DATA_ACC_SET_COMP_MODE, "-C", (unsigned char) mode)) != 0) {
    fprintf(stderr, "DATA_ACC_SET_COMP_MODE failed: %d\n", r);
    return 1;
  }
  unsigned char mget;
  if((r=domsg(filep, bufsiz, 1000,
              DATA_ACCESS, DATA_ACC_GET_COMP_MODE, "+C", &mget)) != 0) {
    fprintf(stderr, "DATA_ACC_GET_COMP_MODE failed: %d\n", r);
    return 1;
  }
  if(mget != (unsigned char) mode) {
    fprintf(stderr, "Compression mode: set (%d) != get (%d).\n",
	    (int) mode, (int) mget);
    return 1;
  }
  fprintf(stderr,"OK.\n");
  return 0;
}

int setDataFormat(int filep, int bufsiz, int fmt) {
  int r;
  fprintf(stderr,"Setting DOM Data format to %d... ", fmt);
  if((r=domsg(filep, bufsiz, 1000,
              DATA_ACCESS, DATA_ACC_SET_DATA_FORMAT, "-C", (unsigned char) fmt)) != 0) {
    fprintf(stderr, "DATA_ACC_SET_DATA_FORMAT failed: %d\n", r);
    return 1;
  }
  unsigned char mfmt;
  if((r=domsg(filep, bufsiz, 1000,
              DATA_ACCESS, DATA_ACC_GET_DATA_FORMAT, "+C", &mfmt)) != 0) {
    fprintf(stderr, "DATA_ACC_GET_DATA_FORMAT failed: %d\n", r);
    return 1;
  }
  if(mfmt != (unsigned char) fmt) {
    fprintf(stderr, "Set data format: set (%d) != get (%d).\n",
            (int) fmt, (int) mfmt);
    return 1;
  }
  fprintf(stderr,"OK.\n");
  return 0;
}

int setHighVoltage(int filep, int bufsiz, int hvdac) {
  int r;
#define MAXHV      2048 /* VOLTS */
#define MAXHVDELTA 50   /* Volts */
#define MAXTRIALS  15
#define SLEEPMS    300 
  if(hvdac > 2*MAXHV) {
    fprintf(stderr,"setHighVoltage: voltage too high (%d V, %d is maximum)!\n",
	   hvdac/2, MAXHV);
    return 1;
  }
  fprintf(stderr,"Enabling high voltage...\n");
  if((r=domsg(filep, bufsiz, 1000,
	      DOM_SLOW_CONTROL, DSC_ENABLE_PMT_HV, "")) != 0) {
    fprintf(stderr,"DSC_ENABLE_PMT_HV failed: %d\n", r);
    return 1;
  }

  fprintf(stderr,"Setting high voltage...\n");
  if((r=domsg(filep, bufsiz, 1000,
              DOM_SLOW_CONTROL, DSC_SET_PMT_HV, "-S", hvdac)) != 0) {
    fprintf(stderr,"DSC_SET_PMT_HV(%d DAC units) failed: %d\n", hvdac, r);
    return 1;
  }

  fprintf(stderr,"Waiting for HV to ramp up.... "); fflush(stdout);
  int ok=0, isec;
  unsigned short qadc,qdac,junk;
  for(isec=0;isec<MAXTRIALS;isec++) {
    if((r=domsg(filep, bufsiz, 1000,
		DOM_SLOW_CONTROL, DSC_QUERY_PMT_HV, "+SSS", &junk, &qadc, &qdac)) != 0) {
      fprintf(stderr,"DSC_QUERY_PMT_HV failed: %d\n", r);
      highVoltageOff(filep, bufsiz);
      return 1;
    }
    /* Check return DAC setting */
    if(qdac != hvdac) {
      fprintf(stderr,"ERROR: High voltage setting (%d DAC units) in DOM is wrong!  (Should be %d).\n",
	     qdac, hvdac);
      highVoltageOff(filep, bufsiz);
      return 1;
    }
    fprintf(stderr,"%d V... ", qadc/2); fflush(stdout);
    if(abs(((int) hvdac) - ((int) qadc)) < MAXHVDELTA*2) {
      ok = 1;
      break;
    }
    usleep(1000*SLEEPMS);
  }
  if(!ok) {
    fprintf(stderr,"HV (%d V) never reached target value (%d V)!\n", qadc/2, hvdac/2);
    highVoltageOff(filep, bufsiz);
    return 1;
  } else {
    fprintf(stderr,"OK.\n");
  }

  return 0;
}


int highVoltageOff(int filep, int bufsiz) {
  fprintf(stderr,"Turning off high voltage.\n");
  int r;
  if((r=domsg(filep, bufsiz, 1000,
              DOM_SLOW_CONTROL, DSC_SET_PMT_HV, "-S", (unsigned short) 0)) != 0) {
    fprintf(stderr,"DSC_SET_PMT_HV(0) failed: %d\n", r);
    return 1;
  }
  if((r=domsg(filep, bufsiz, 1000,
              DOM_SLOW_CONTROL, DSC_DISABLE_PMT_HV, "")) != 0) {
    fprintf(stderr,"DSC_DISABLE_PMT_HV failed: %d\n", r);
    return 1;
  }
  return 0;
}

void turnOffPeriodicMonitoring(int filep, int bufsiz) {
  fprintf(stderr,"Turning off periodic monitoring... ");
  int r;
  if((r=domsg(filep, bufsiz, 1000, DATA_ACCESS, DATA_ACC_SET_MONI_IVAL, "-LL", 0, 0)) != 0) {
    fprintf(stderr,"DATA_ACC_SET_MONI_IVAL failed: %d\n", r);
    exit(-1);
  }
  fprintf(stderr,"OK.\n");
}
