/* echo-test.c, supports:
 *
 *   1) full speed stuffing echo mode test (throughput test) -- default
 *   2) throttled read test (test retx in dor/dom) -- -t
 *
 * we assume the doms are already in echo-mode...
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>

#include <sys/time.h>
#include <sys/types.h>
#include <sys/poll.h>
#include <fcntl.h>
#include <unistd.h>

#define MAXDOMS 64

struct DomBuf {
   int dom;
   const char *data;
   int ndata;
   struct DomBuf *next;
};

static struct DomBuf *dbTop = NULL, *dbLast = NULL;

static const char *cpBuf(const char *buf, int n) {
   char *t = (char *) malloc(n);
   if (t==NULL) {
      fprintf(stderr, "echo-test: internal error, unable to cp buf\n");
      exit(1);
   }
   memcpy(t, buf, n);
   return t;
}

static void fill(char *buf, int n) {
   int i;
   for (i=0; i<n; i++) buf[i] = random();
}

static void reg(int dom, const char *buf, int nbuf, int *wm, int *rm) {
   struct DomBuf *db = (struct DomBuf *) malloc(sizeof(struct DomBuf));
   if (db==NULL) {
      fprintf(stderr, "echo-test: internal error, unable to malloc dom buf\n");
      exit(1);
   }
   db->dom = dom;
   db->data = cpBuf(buf, nbuf);
   db->ndata = nbuf;
   db->next = NULL;
   if (dbLast!=NULL) dbLast->next = db;
   else dbTop = db;
   dbLast = db;
   wm[dom]=wm[dom] - 1;
   rm[dom]=rm[dom] + 1;

#if 0
   printf("reg: dom=%d, nbuf=%d, rm=%d, wm=%d\n", dom, nbuf, rm[dom], wm[dom]); 
#endif
}

static int unreg(int dom, const char *buf, int nbuf, int *wm, int *rm) {
   struct DomBuf *db, *pdb;
   for (db=dbTop, pdb=NULL; db!=NULL; pdb=db, db=db->next) {
      if (db->dom==dom) {
         int ret = 
            (db->ndata==nbuf && memcmp(buf, db->data, nbuf)==0) ? 0 : 1;
         free((char *) db->data);
         if (pdb!=NULL) pdb->next = db->next;
         if (db->next==NULL) dbLast = pdb;
         if (db==dbTop) dbTop = db->next;
         free(db);
         rm[dom]--;
#if 0
   	 printf("unreg: dom=%d, nbuf=%d, rm=%d, wm=%d\n", 
		dom, nbuf, rm[dom], wm[dom]);
#endif
         return ret;
      }
   }
   fprintf(stderr, "echo-test: no message found\n");
   return 1;
}

/* t2 - t1 in s */
static double diffsec(const struct timeval *t1, const struct timeval *t2) {
   long long usec1 = t1->tv_usec + t1->tv_sec * 1000000LL;
   long long usec2 = t2->tv_usec + t2->tv_sec * 1000000LL;
   return (double) (usec2 - usec1) * 1e-6;
}

/* should we read throttle? */
static int readThrottle(int rate, unsigned long long bytes, double sec) {
   if (rate<=0 || sec==0) return 0;
   return bytes/sec > rate; 
}

static int test(int *dfds, const char **doms, int ndoms, int nmsgs, int rdt) {
   struct pollfd fds[MAXDOMS];
   int dord = 1;
   int rmsgs[MAXDOMS];
   int wmsgs[MAXDOMS];
   int errs[MAXDOMS];
   struct timeval stv;
   struct timeval etv[MAXDOMS];
   unsigned long long bytes[MAXDOMS];
   int i;
   int tmout = (rdt>0) ? 100 : -1;  /* recalc 10x a sec if read throttling */
   
   for (i=0; i<ndoms; i++) {
      rmsgs[i] = 0;
      wmsgs[i] = nmsgs;
      errs[i] = 0;
      bytes[i] = 0ULL;
   }

   /* clear pending msgs... */
   for (i=0; i<ndoms; i++) {
	fds[i].fd = dfds[i];
	fds[i].events = POLLIN;
   }
   while (poll(fds, ndoms, 200)>0) {
	char buf[4092];
        int i;
        for (i=0; i<ndoms; i++) {
	   if (fds[i].revents&POLLIN) read(fds[i].fd, buf, sizeof(buf));
	}
   }
	
   /* go! */
   gettimeofday(&stv, NULL);

   while (1) {
      int nfds=0;
      int i;
      int pret;
      struct timeval ctv;
      int nrem = 0;

      gettimeofday(&ctv, NULL);

      for (i=0; i<ndoms; i++) {
	 /* number of messages remaining to send/rcv */
         nrem += rmsgs[i] + wmsgs[i];

         if (dfds[i]!=-1) {
            /* FIXME: read throttling? */
            const int throttle = 
               readThrottle(rdt, bytes[i], diffsec(&stv, &ctv));
            if ((!throttle && dord && rmsgs[i]>0) || wmsgs[i]>0) {
               fds[nfds].fd = dfds[i];
               fds[nfds].events = 0;
               if (!throttle && dord && rmsgs[i]>0) fds[nfds].events |= POLLIN;
               if (wmsgs[i]>0) fds[nfds].events |= POLLOUT;

#if 0
		printf("setup: dom=%d, rmsgs=%d, wmsgs=%d, in=%d out=%d\n",
		i, rmsgs[i], wmsgs[i], fds[nfds].events&POLLIN, 
		fds[nfds].events&POLLOUT);
#endif
               nfds++;
            }

            /* no more msgs to read or write for this dom... */
            if (wmsgs[i]==0 && rmsgs[i]==0) {
               gettimeofday(etv+i, NULL);
               close(dfds[i]);
               dfds[i] = -1;
            }
         }
      }

      /* all done? */
      if (nrem==0) break;

      if ((pret=poll(fds, nfds, tmout))<0) {
         perror("echo-test: poll");
         return 1;
      }
      else if (pret==0) {
         /* timeout -- we can read again... */
         dord = 1;
      }

      for (i=0; i<nfds; i++) {
         if (fds[i].revents&(POLLIN|POLLOUT|POLLHUP)) {
            int j;
         
            for (j=0; j<ndoms; j++) {
               if (dfds[j]==fds[i].fd) {
                  char buf[4092];
                  
                  if ( (fds[i].revents&POLLOUT) && wmsgs[j]>0) {
                     /* do write... */
                     const int nw = (random()%4091)+1;
                     int ret;
                     
                     fill(buf, nw);
                     if ((ret=write(dfds[j], buf, nw))!=nw) {
                        if (ret<0) {
                           fprintf(stderr, "echo-test: write to %s: %s\n",
                                   doms[j], strerror(errno));
                        }
                        else if (ret==0) {
                           fprintf(stderr, "echo-test: eof on write to %s\n",
                                   doms[j]);
                        }
                        else {
                           fprintf(stderr, "echo-test: partial write on %s\n",
                                   doms[j]);
                           bytes[j]= bytes[j] + ret;
                           reg(j, buf, ret, wmsgs, rmsgs);
                        }
                     }
                     else {
                        /* write succeeded */
                        bytes[j]= bytes[j] + nw;
                        reg(j, buf, nw, wmsgs, rmsgs);
                     }
                  }
                  if (fds[i].revents&POLLIN) {
                     /* do read, verify... */
                     const int nr = read(dfds[j], buf, sizeof(buf));
                     if (nr<0) {
                        fprintf(stderr, "echo-test: read from %s: %s\n",
                                doms[j], strerror(errno));
                     }
                     else if (nr==0) {
                        fprintf(stderr, "echo-test: eof on read from %s\n",
                                doms[j]);
                     }
                     else {
                        bytes[j] = bytes[j] + nr;
                        if (unreg(j, buf, nr, wmsgs, rmsgs)) {
                           fprintf(stderr, 
                                   "echo-test: mismatch on read from %s\n",
                                   doms[j]);
                        }
                     }
                  }
                  if (fds[i].revents&POLLHUP) {
                     /* deal with error... */
                     fprintf(stderr, 
                             "echo-test: error on read from %s -- closing\n",
                             doms[j]);
                     /* close this guy... */
                     close(dfds[j]);
                     dfds[j]=-1;
                  }
               }
            }
         }
      }
   }

   for (i=0; i<ndoms; i++) {
      /*    dom   nbytes time errs */
      printf("%s %llu %f %d\n",
      doms[i], bytes[i], diffsec(&stv, etv+i), errs[i]);
   }
   
   return 0;
}

static void usage(void) {
   fprintf(stderr, "usage: echo-test [-t rate|-n nmsgs] doms...\n");
}

int main(int argc, char *argv[]) {
   int ai;
   int ndoms = 0;
   int fds[MAXDOMS];
   int nmsgs=1000;
   const char *doms[MAXDOMS];
   int rdthrottle = -1; /* read throttle data rate in bytes/sec */

   for (ai=1; ai<argc; ai++) {
      if (strcmp(argv[ai], "-t")==0 && ai<argc-1) {
         rdthrottle = atoi(argv[ai+1]);
         ai++;
      }
      else if (strcmp(argv[ai], "-n")==0 && ai<argc-1) {
         nmsgs = atoi(argv[ai+1]);
         ai++;
      }
      else if (strlen(argv[ai])==3) {
         /* open dom... */
         char path[128];
         char dom[4];

         strcpy(dom, argv[ai]);  
         dom[2] = toupper(dom[2]);
         snprintf(path, sizeof(path), "/dev/dhc%cw%cd%c", dom[0], dom[1], 
            dom[2]);
         if ((fds[ndoms]=open(path, O_RDWR))<0) {
            fprintf(stderr, "echo-test: open '%s': %s\n", path, 
                    strerror(errno));
            return 1;
         }
         doms[ndoms] = strdup(dom);
         ndoms++;
      }
      else {
         usage();
         return 1;
      }
   }

   if (ndoms==0) {
      usage();
      return 1;
   }
   
   if (test(fds, doms, ndoms, nmsgs, rdthrottle)) {
      fprintf(stderr, "echo-test: unable to complete test\n");
      return 1;
   }

   return 0;
}






