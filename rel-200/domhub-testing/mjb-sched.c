/* mjb-sched.c, schedule mjb tests to be run...
 *
 * argv[1]=number of seconds to run tests...
 * argv[2-]=doms to run them on...
 */
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <time.h>
#include <errno.h>

#include <sys/types.h>
#include <sys/wait.h>
#include <sys/poll.h>
#include <unistd.h>

#include "mjb-util.h"

static int pfds[2];

/* synchronize signals... */
static void sighandler(int sig) { write(pfds[1], &sig, sizeof(sig)); }

struct RunInfo {
   const char *dom;
   const struct TestStruct *test; /* test info... */
   pid_t pid; /* pid running... */
   int output;
};

static void reschedule(const struct TestStruct *tests, struct RunInfo *ri) {
   int i, n=0;
   const struct TestStruct *ts;
   int pfds[2];

   for (ts=tests; ts!=NULL; ts=ts->next) n++;
   const int test = random()%n;
   for (i=0, ts=tests; i<test; i++) ts = ts->next;
   ri->test = ts;

   if (pipe(pfds)<0) {
      perror("mjb-sched: pipe");
      return;
   }
   
   if ((ri->pid=fork())<0) {
      perror("mjb-sched: fork");
      return;
   }
   else if (ri->pid == 0) {
      /* child... */
      close(pfds[0]);
      close(1);
      dup(pfds[1]);
      close(pfds[1]);
      if (execl("./mjb-run-test", 
                "./mjb-run-test", ri->test->test, ri->dom, NULL)<0) {
         perror("mjb-sched: execl");
         return;
      }
   }
   else {
      /* parent... */
      ri->output = pfds[0];
      close(pfds[1]);
   }
}

static struct RunInfo *lookupRunByPID(struct RunInfo *ri, int n, pid_t pid) {
   int i;
   for (i=0; i<n; i++) {
      if (ri[i].pid==pid) return ri + i;
   }
   return NULL;
}

static struct RunInfo *lookupRunByFD(struct RunInfo *ri, int n, int fd) {
   int i;
   for (i=0; i<n; i++) {
      if (ri[i].output==fd) return ri + i;
   }
   return NULL;
}

/* return number of children processed... */
static int processChildren(struct RunInfo *ri, int ndoms) {
   int ret = 0;

   while (1) {
      int exitstatus;
      pid_t chld = wait3(&exitstatus, WNOHANG, NULL);
      
      if (chld<0) {
         if (errno==ECHILD) break;
         perror("mjb-sched: wait3");
         return -1;
      }
      else if (chld==0) {
         break;
      }
      else {  
         const int status = WEXITSTATUS(exitstatus);
         struct RunInfo *run = lookupRunByPID(ri, ndoms, chld);
         
         if (status!=0) {
            fprintf(stderr, 
                    "mjb-sched: '%s' exited with status: "
                    "%d [%08x]\n",
                    run->test->test, status, exitstatus);
         }
         
         if (run==NULL) {
            fprintf(stderr, "mjb-sched: cool! invalid child\n");
            return -1;
         }
         
         if (status==100) {
            /* duplicate test ignore... */
         }
         else if (status==101) {
            /* timeout */
            printf("%s %lu %s ERROR: TIMEOUT\n", 
                   run->test->test, time(NULL), run->dom);
         }
         else if (status == 102 ) {
            /* test not found */
            printf("%s %lu %s ERROR: TEST NOT FOUND\n",
                   run->test->test, time(NULL), run->dom);
         }
         else if (status == 103 ) {
            printf("%s %lu %s ERROR: USAGE\n", 
                   run->test->test, time(NULL), run->dom);
         }
         else if ( status > 0 ) {
            printf("%s %lu %s ERROR: failed %d\n",
                   run->test->test, time(NULL), run->dom, status);
         }
         
         /* make sure we flush error data... */
         fflush(stdout);
         
         if (run->output!=-1) {
            /* it would seem to me that the zero read on the pipe
             * should come first, but this does not appear to be
             * the case...
             */
            close(run->output);
            run->output = -1;
         }
         run->pid = (pid_t) -1;
         
         return status;
      }
   }

   return ret;
}

int main(int argc, char *argv[]) {
   if (argc<3) {
      fprintf(stderr, "mjb-sched nseconds doms...\n");
      return 1;
   }

   if (pipe(pfds)<0) {
      perror("mjb-sched: pipe");
      return 1;
   }

   /* make signals synchronous... */
   signal(SIGCHLD, sighandler);
   signal(SIGTERM, sighandler);

   {  const struct TestStruct *tests = parseTests("tests.txt");
      const int nsecs = atoi(argv[1]);
      const int di = 2;
      const int ndoms = argc - di;
      struct RunInfo *ri = 
         (struct RunInfo *) calloc(ndoms, sizeof(struct RunInfo));
      time_t start_time = time(NULL);
      int i;
      struct pollfd *fds = 
         (struct pollfd *) calloc(ndoms, sizeof(struct pollfd));

      if (ri==NULL || fds==NULL) {
         fprintf(stderr, "mjb-sched: unable to calloc %d runs\n", ndoms);
         return 1;
      }

      for (i=0; i<ndoms; i++) {
         ri[i].test = NULL;
         ri[i].pid = (pid_t) -1;
         ri[i].dom = argv[di+i];
         ri[i].output = -1;
      }

      /* start tests... */
      for (i=0; i<ndoms; i++) reschedule(tests, ri+i);

      while (1) {
         int ret;
         int i;
         int nfds = 0;

         /* add signal pipe to list... */
         fds[nfds].fd = pfds[0];
         fds[nfds].events = POLLIN | POLLHUP;
         nfds++;

         for (i=0; i<ndoms; i++) {
            /* add output channels... */
            if (ri[i].output != -1) {
               fds[nfds].fd = ri[i].output;
               fds[nfds].events = (POLLIN | POLLHUP);
               nfds++;
            }
         }

         /* make sure there are no children waiting...
          */
         processChildren(ri, ndoms);
         
         if ((ret = poll(fds, nfds, -1))<0) {
            if (errno!=EINTR) {
               perror("mjb-sched: poll");
               return 1;
            }
         }
         else if (ret>0) {
            if (fds[0].revents&(POLLIN|POLLHUP)) {
               int sig;
               int ret = read(pfds[0], &sig, sizeof(sig));
               
               if (ret<0) {
                  perror("mjb-sched: read");
                  return 1;
               }
               else if (ret!=sizeof(sig)) {
                  fprintf(stderr, "mjb-sched: partial read!\n");
                  return 1;
               }
               
               if (sig==SIGCHLD) {
                  processChildren(ri, ndoms);
               }
               else if (sig==SIGTERM) {
                  /* FIXME: clean up... */
                  return 1;
               }
            }
            else {
               int i;

               /* start with first pipe fd (1) */
               for (i=1; i<nfds; i++) {
                  if (fds[i].revents&(POLLIN|POLLHUP)) {
                     char b[4096];
                     struct RunInfo *run = lookupRunByFD(ri, ndoms, fds[i].fd);
                     const int nr = read(run->output, b, sizeof(b));
                     
                     if (nr<0) {
                        perror("pipe output: read");
                        close(run->output);
                        run->output = -1;
                     }
                     else if (nr==0) {
                        /* pipe is closed...
                         */
                        close(run->output);
                        run->output = -1;
                     }
                     else if (nr>0) {
                        char bb[128];
                        const int n= 
                           snprintf(bb, sizeof(bb), " %lu ", time(NULL));

                        /* here, we assume that we get the whole line
                         * in one read, this is probably safe...
                         */
                        write(1, run->test->test, strlen(run->test->test));
                        write(1, bb, n);
                        write(1, b, nr);
                     }
                  }
               }
            }
         }

         /* reschedule -- if necessary... */
         if (time(NULL) - start_time < nsecs) {
            int i;
            for (i=0; i<ndoms; i++) {
               if (ri[i].pid == (pid_t) -1) {
                  /* need reschedule... */
                  reschedule(tests, ri+i);
               }
            }
         }
         else {
            /* are we done? */
            int i, done = 1;
            for (i=0; i<ndoms && done; i++) {
               if (ri[i].pid!=(pid_t) -1) done=0;
            }
            if (done) break;
         }
      }
   }
   return 0;
}
