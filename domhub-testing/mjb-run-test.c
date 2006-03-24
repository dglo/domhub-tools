/* mjb-run-test, run an mjb test...
 *
 * arguments: $1 command to run, $2 dom, $3 timeout
 *
 * exit codes: 
 *   101: timeout occured
 *   104: pipe creation error
 *   105: fork error
 *   106: unable to exec
 *   107: we were killed externally
 *   108: invalid read from pipe
 *   otherwise command exit code...
 * 
 */
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <time.h>
#include <errno.h>
#include <ctype.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/poll.h>
#include <unistd.h>
#include <dirent.h>
#include <fcntl.h>
#include <sched.h>

#include "mjb-util.h"

/* synchronize signals... */
static int pfds[2];
static void sighandler(int sig) {
   write(pfds[1], &sig, sizeof(sig));
}

/* find the parent of the process pid, or -1 if there is none... */
static pid_t parent(pid_t pid) {
   char path[128];
   char buffer[4096];
   int fd, nr;

   snprintf(path, sizeof(path), "/proc/%u/stat", pid);
   if ((fd=open(path, O_RDONLY))<0) return (pid_t) -1;

   if ((nr=read(fd, buffer, sizeof(buffer)))<0) {
      close(fd);
      return (pid_t) -1;
   }
   close(fd);

   if (nr<1 || buffer[nr-1]!='\n') return (pid_t) -1;

   buffer[nr-1]=0;
   
   {  char *t = strchr(buffer, ')');
      unsigned p;
      if (t==NULL) return (pid_t) -1;
      if (sscanf(t+1, "%*s %u\n", &p)!=1) {
         return (pid_t) -1;
      }
      return (pid_t) p;
   }
}

/* return a child of pid or (pid_t) -1 if there are none... */
static pid_t child(pid_t pid) {
   pid_t ret = (pid_t) -1;
   DIR *proc = opendir("/proc");
   struct dirent *de;
   while ((de=readdir(proc))!=NULL) {
      char path[128];
      int i;
      const int len = strlen(de->d_name);

      /* all digits? */
      for (i=0; i<len; i++) if (!isdigit(de->d_name[i])) continue;

      /* stat exists? */
      snprintf(path, sizeof(path), "/proc/%s/stat", de->d_name);
      if (access(path, R_OK)) continue;

      if (parent(atoi(de->d_name))==pid) {
         ret = (pid_t) atoi(de->d_name);
         break;
      }
   }

   closedir(proc);
   return ret;
}

/* the process can be dead or a zombie...
 */
static int isDead(pid_t pid) {
   char path[128];
   int fd;
   char line[4097];

   snprintf(path, sizeof(path), "/proc/%u/stat", (unsigned) pid);

   if ((fd = open(path, O_RDONLY))<0) {
      return 1;
   }

   memset(line, 0, sizeof(line));
   if (read(fd, line, sizeof(line)-1)>0) {
      char *t = strchr(line, ')');
      if (t==NULL || t[1]!=' ' || t[2]=='Z') {
         close(fd);
         return 1;
      }
   }
   close(fd);
   return 0;
}

/* send a signal to pid and all it's descendents,
 * we send to the leaves first, then move inward...
 */
static void massacre(pid_t pid) {
   pid_t ch;

   /* first stop this process... */
   kill(pid, SIGSTOP);

   /* descend... */
   while ((ch = child(pid)) != (pid_t) -1 && !isDead(ch)) massacre(ch);

   /* now we must kill this pid until it's all the way dead! */
   if (kill(pid, SIGKILL)<0) {
      perror("mjb-run-test: massacre: kill");
      return;
   }
   
   /* wait forever... */
   while (!isDead(pid)) sched_yield();
}

/* get the timeout for a test or -1 on error...
 */
static const struct TestStruct *getTest(const struct TestStruct *tests, 
                                        const char *tst) {
   while (tests!=NULL) {
      if (strcmp(tests->test, tst)==0) return tests;
      tests = tests->next;
   }
   return NULL;
}

static int runWithTimeout(const char *program, /* program to run      */
                          const char *dom,     /* dom is the argument */
                          int timeout,         /* in seconds          */
                          int signals,         /* signal pipe         */
                          int ignore           /* ignore standard out */) {
   pid_t pid = fork();
   
   if (pid<0) {
      perror("mjb-run-test: fork");
      return 105;
   }
   else if (pid==0) {
      /* child */
      if (ignore) {
         int fd = open("/dev/null", O_WRONLY);
         close(1);
         dup(fd);
         close(fd);
      }
      
      if (execlp(program, program, dom, NULL)<0) {
         perror("mjb-run-test: execlp");
         return 106;
      }
   }
   else {
      /* set alarm clock... */
      alarm(timeout);
      
      {  int sig;
         const int nr = read(pfds[0], &sig, sizeof(sig));
      
         if (nr<0) {
            perror("mjb-run-test: signal pipe: read");
            massacre(pid);
            return 108;
         }
         else if (nr==0) {
            fprintf(stderr, "mjb-run-test: signal pipe premature close\n");
            massacre(pid);
            return 108;
         }
         else if (nr!=sizeof(sig)) {
            fprintf(stderr, "mjb-run-test: signal pipe: partial read\n");
            massacre(pid);
            return 108;
         }
         else {
            if (sig==SIGCHLD) {
               int wstatus;
               wait(&wstatus);
               return WEXITSTATUS(wstatus);
            }
            else if (sig==SIGALRM) {
               /* timeout... */
               fprintf(stderr, "mjb-run-test: timeout: %s %s\n", program, dom);
               massacre(pid);
               return 101;
            }
            else {
               fprintf(stderr, 
                       "mjb-run-test: yikes!  unexpected signal: %d\n",
                       sig);
               massacre(pid);
               return 107;
            }
         }
      }
   }
   return 0;
}

int main(int argc, char *argv[]) {
   const struct TestStruct *tests, *test;
   const char *testName;
   const char *dom;

   if (argc!=3) {
      fprintf(stderr, "usage: mjb-run-test test dom\n");
      return 1;
   }

   testName = argv[1];
   dom = argv[2];
   if ((tests = parseTests("tests.txt"))==NULL) {
      fprintf(stderr, "mjb-run-test: unable to parse tests.txt\n");
      return 1;
   }

   if ((test=getTest(tests, testName))==NULL) {
      fprintf(stderr, "mjb-run-test: unable to find test '%s'\n", testName);
      return 1;
   }

   if (pipe(pfds)<0) {
      perror("mjb-run-test: pipe");
      return 104;
   }

   /* route interrupts through a pipe so they are synch... */
   signal(SIGALRM, sighandler);
   signal(SIGCHLD, sighandler);
   signal(SIGTERM, sighandler);

   /* run the mode setting program... */
   {  const int ret = runWithTimeout(test->mode, dom, 60, pfds[0], 1);
      if (ret!=0) {
         fprintf(stderr, "mjb-run-test: %s %s: %s failure: %d\n", 
                 test->test, dom, test->mode, ret);
         return ret;
      }
   }

   /* run the actual test script... */
   {  char testScript[128];
      int ret;

      snprintf(testScript, sizeof(testScript), "./%s-test.sh", test->test);
      ret = runWithTimeout(testScript, dom, test->timeout, pfds[0], 0);
      if (ret!=0) {
         fprintf(stderr, "mjb-run-test: test error: %d\n", ret);
      }
      return ret;
   }
}
