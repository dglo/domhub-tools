#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>

#include <sys/poll.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

static void usage(void) {
   fprintf(stderr, "usage: tcalcycle [-iter n] CWD\n");
   fprintf(stderr, "  where CWD is card, wirepair, dom\n");
}

int main(int argc, char *argv[]) {
   int ai, i;
   int niter = 100;
   char fname[128];

   for (ai=1; ai<argc; ai++) {
      if (argv[ai][0]!='-') break;
      
      if ( (strcmp(argv[ai], "-iter")==0 || strcmp(argv[ai], "-n")==0) && 
	   ai+1<argc) {
         niter = atoi(argv[ai+1]);
         ai++;
      }
      else {
         usage();
         return 1;
      }
   }

   if (argc-ai!=1 || strlen(argv[ai])!=3) {
      usage();
      return 1;
   }

   snprintf(fname, sizeof(fname),
            "/proc/driver/domhub/card%c/pair%c/dom%c/tcalib",
            argv[ai][0], argv[ai][1], argv[ai][2]);

   for (i=0; i<niter; i++) {
      const char *cmd = "single\n";
      int fd, j;
      struct {
         unsigned hdr;
         unsigned long long dor_t0;
         unsigned long long dor_t3;
         unsigned short dorwf[64];
         unsigned long long dom_t1;
         unsigned long long dom_t2;
         unsigned short domwf[64];
      } tcbuf;

      if ((fd=open(fname, O_RDWR))<0) {
         perror("open procfile");
         return 1;
      }
      
      if (write(fd, cmd, strlen(cmd))!=strlen(cmd)) {
         fprintf(stderr, "can't write single cmd to proc file...\n");
         return 1;
      }
      
      {  int ntries;
         for (ntries=0; ntries<1000; ntries++) {
            poll(NULL, 0, 10);

            if (read(fd, &tcbuf, sizeof(tcbuf))==sizeof(tcbuf)) break;
         }
         if (ntries==1000) {
            fprintf(stderr, "can't read tcal info from proc file\n");
            return 1;
         }
      }
      
      printf("DOM_%c%c_TCAL_round_trip_%06d\n",
	     argv[ai][1], tolower(argv[ai][2]), i+1);
      printf("dor_tx_time %llu\n", tcbuf.dor_t0);
      printf("dor_rx_time %llu\n", tcbuf.dor_t3);
      for (j=0; j<48; j++) printf("dor_%02d %d\n", j, tcbuf.dorwf[j]);

      printf("dom_tx_time %llu\n", tcbuf.dom_t2);
      printf("dom_rx_time %llu\n", tcbuf.dom_t1);
      for (j=0; j<48; j++) printf("dom_%02d %d\n", j, tcbuf.domwf[j]);
      
      close(fd);
    }

   return 0;
}
