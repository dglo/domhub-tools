/* domterm.c, convenience routine to talk to dom assuming
 * that you're on the same box...
 */
#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>

#include <sys/poll.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>
#include <termios.h>
#include <signal.h>

/* signal fds, 0 -> read, 1 -> write */
static int sfds[2];
static struct termios tiosave;  /* command tio */
static int tcSaved = 0;

static void sighand(int sig) { write(sfds[1], &sig, sizeof(sig)); }

/* exec a command, stdin/stdout on cmd are piped
 * through to rfd and wfd -- why piped and not
 * just passed?  well, the driver only takes
 * "packets" (not my idea!) and so we have to
 * ensure that we read the proper amount of
 * data and don't send too much in one crack...
 *
 * FIXME: switch terminal back to "normal" mode
 */
int cmdstatus; /* command status... */
static int docmd(int rfd, int wfd, const char *nm) {
   int rfds[2];
   int wfds[2];
   pid_t pid;
   int done = 0;
   int ret = 0;
   
   if (pipe(rfds)<0) return 1;
   if (pipe(wfds)<0) return 1;
   
   if ((pid=fork())<0) {
      close(rfds[0]); close(rfds[1]);
      close(wfds[0]); close(wfds[1]);
      return 1;
   }
   else if (pid==0) {
      close(0); dup(wfds[0]);
      close(1); dup(rfds[1]);

      /* toss pending data... */
      {
         struct pollfd fds[1];
         fds[0].fd = rfd;
         fds[0].events = POLLIN;
      
         while (poll(fds, 1, 0)>0) {
            char b[4092];
            if (read(rfd, b, sizeof(b))<0) { break; }
         }
      }
     
      {
         const char *env[] = { "BASH_ENV=~/.bashrc", NULL }; 
         if (execle("/bin/bash", "bash", "-c", nm, NULL, env)<0) return 1;
      }
   }

   /* process data... */
   while (!done) {
      struct pollfd fds[3];
      int nfds = 0;
      int i;

      if (rfd!=-1) {
         fds[nfds].fd = rfd;
         fds[nfds].events = POLLIN;
         nfds++;
      }
      if (rfds[0]!=-1) {
         fds[nfds].fd = rfds[0];
         fds[nfds].events = POLLIN;
         nfds++;
      }
      fds[nfds].fd = sfds[0];
      fds[nfds].events = POLLIN;
      nfds++;
      
      if (poll(fds, nfds, -1)<0) {
         /* FIXME: better error handling... */
         if (errno==EINTR) continue;
         perror("poll");
         break;
      }
      
      for (i=0; i<nfds; i++) {
         char buf[4092];
         
         if (fds[i].fd==rfd && (fds[i].revents & (POLLIN|POLLHUP|POLLERR))) {
            /* the dom is talking -- push it along... */
            int nr = read(rfd, buf, sizeof(buf));

            if (nr<=0) {
               /* dom closed! */
               close(rfd);
               rfd = -1;
            }
            else {
               /* forward data along to program... */
               write(wfds[1], buf, nr);
            }
         }
         else if (fds[i].fd==rfds[0] && (fds[i].revents & (POLLIN|POLLHUP))) {
            /* the program is talking... */
            int nr = read(rfds[0], buf, sizeof(buf));

            if (nr<=0) {
               if (nr<0) perror("read from program");
               
               /* program closed connection! */
               close(rfds[0]); rfds[0]=-1;
               close(rfds[1]); rfds[1]=-1;
               close(wfds[0]); wfds[0]=-1;
               close(wfds[1]); wfds[1]=-1;
            }
            else {
               /* forward data along to dom... */
               write(wfd, buf, nr);
            }
         }
         else if (fds[i].fd==sfds[0] && 
                  (fds[i].revents & (POLLIN|POLLHUP|POLLERR))) {
            int sig;
            const int nr = read(sfds[0], &sig, sizeof(sig));

            if (nr<=0) {
               fprintf(stderr, "domterm: error in signal pipe\n");
               ret=1;
               done=1;
            }
            
            if (sig!=SIGCHLD) ret = 1;
	    //fprintf(stderr, "rcved: %d\r\n", sig);  fflush(stderr);
            if (sig==SIGSTOP) { }
	    else done = 1;
         }
      }
   }

   if (waitpid(pid, &cmdstatus, 0)<0) {
      perror("domterm: command: waitpid");
      ret=1;
   }

   return ret;
}

/* use the dor api? */
static int newapi(void) {
   return access("/proc/dor", F_OK)==0;
}

int main(int argc, char *argv[]) {
   int rfd, wfd;
   int ret = 0;
   const char *err = NULL;
   pid_t ibpid = -1;
   int ai;
   int quiet = 0;
   int sfd=-1;  /* signal pipe... */

   for (ai=1; ai<argc; ai++) {
      if (strcmp(argv[ai], "-q")==0) quiet = 1;
      else if ( (strcmp(argv[ai], "-s")==0) && argc-ai>2) {
         sfd=atoi(argv[ai+1]);
         ai++;
      }
      else break;
   }
 
   if (argc-ai!=1 ||
       (strcmp(argv[ai], "sim")!=0 && (
       argv[ai][0]<'0' || argv[ai][0]>'7' ||
       argv[ai][1]<'0' || argv[ai][1]>'3' ||
       toupper(argv[ai][2])<'A' || toupper(argv[ai][2])>'B'))) {
      fprintf(stderr, 
              "usage: domterm CWD\n\twhere:\n"
              "\t\tC = card (0..7)\n"
              "\t\tW = wire pair (0..1)\n"
              "\t\tD = dom (A or B)\n");
      return 1;
   }

   /* signal pipe, make signals synchronous... */
   if (pipe(sfds)<0) {
      perror("pipe");
      return 1;
   }
   signal(SIGHUP, sighand);   signal(SIGINT, sighand);
   signal(SIGPIPE, sighand);  signal(SIGALRM, sighand);
   signal(SIGTERM, sighand);  signal(SIGUSR1, sighand);
   signal(SIGUSR2, sighand);  signal(SIGPOLL, sighand);
   signal(SIGPROF, sighand);  signal(SIGVTALRM, sighand);
   signal(SIGCHLD, sighand);

   if (!quiet) printf("connecting..."); fflush(stdout);
   if (strcmp(argv[ai], "sim")==0) {
      int prfds[2];
      int pwfds[2];
      pid_t pid;
      
      if (pipe(prfds)<0) {
         perror("sim pipe");
         return 1;
      }
      if (pipe(pwfds)<0) {
         perror("sim pipe");
         return 1;
      }

      if ((pid=fork())<0) {
         perror("sim fork");
         return 1;
      }
      else if (pid==0) {
         close(0); dup(pwfds[0]);
         close(1); dup(prfds[1]);
         
         if (execl("./Linux-i386/bin/iceboot", "iceboot", NULL)<0) {
            perror("exec iceboot");
            return 1;
         }
      }
      else ibpid = pid;

      /* setup our read and write fds... */
      rfd = prfds[0];
      wfd = pwfds[1];
   }
   else {
      char path[128];

      if (newapi()) {
         snprintf(path, sizeof(path), "/dev/dor/%c%c%c", 
                  argv[ai][0], argv[ai][1], toupper(argv[ai][2]));
      }
      else {
         int bfd = open("/proc/driver/domhub/blocking", O_WRONLY);
         if (bfd<0) {
            perror("open blocking proc file");
            return 1;
         }
         write(bfd, "1\n", 2);
         close(bfd);

         snprintf(path, sizeof(path), "/dev/dhc%cw%cd%c",
                  argv[ai][0], argv[ai][1], toupper(argv[ai][2]));
      }
 
      if ((rfd=wfd=open(path, O_RDWR))<0) {
         fprintf(stderr, "domterm: open %s: %s\n", path, strerror(errno));
         return 1;
      }
   }
   if (!quiet) printf(" OK\n");  fflush(stdout);

   if (isatty(1)) {
      struct termios tio;
      
      tcgetattr(1, &tiosave);
      tcSaved = 1;
      
      tio = tiosave;
      tio.c_lflag = ISIG;
      tio.c_iflag = INLCR;
      tcsetattr(1, TCSANOW, &tio);
   }
  
   /* close signal pipe, signals that we're ready... */
   if (sfd!=-1) {
      char c = 0x04;
      write(sfd, &c, 1);
      close(sfd);
   } 
 
   while (1) {
      char buf[4092];
      struct pollfd fds[3];
#define error(a) { fprintf(stderr, "\r\ndomterm: " a); err = strerror(errno); \
  ret = 1; break; }

      fds[0].fd = rfd;
      fds[0].events = POLLIN;
      fds[1].fd = 0;
      fds[1].events = POLLIN;
      fds[2].fd = sfds[1];
      fds[2].events = POLLIN;
      
      if (poll(fds, 3, -1)<0) {
         /* interrupts are handled below... */
         if (errno==EINTR) continue;
         error("poll");
      }

      /* read from dom... */
      if (fds[0].revents&(POLLIN|POLLERR|POLLHUP)) {
         int nr = read(rfd, buf, sizeof(buf));
         if (nr<0) {
            error("read dom");
         }
         else if (nr==0) {
            error("dom eof");
         }
         write(1, buf, nr);
      }
      
      /* read from standard in... */
      if (fds[1].revents&(POLLIN|POLLHUP)) {
         int nr = read(0, buf, sizeof(buf));
         if (nr<0) {
            perror("domterm: read stdin");
            ret = 1;
            break;
         }
         else if (nr==0) {
            /* all done -- wait a bit for any read data to finish... */
	    int ms = 0;
	    long long sms;
	    struct timeval start;
	    gettimeofday(&start, NULL);
	    sms = (long long) start.tv_sec*1000LL + (start.tv_usec/1000);
	    while (ms<100) {
	        if (poll(fds, 1, 100-ms)==1) {
	       	    int nr = read(rfd, buf, sizeof(buf));
		    if (nr>0) {
			write(1, buf, nr);
	  	    }
		}
		{  struct timeval tv;
		   gettimeofday(&tv, NULL);
		   ms = (int) 
			((long long) tv.tv_sec*1000LL + (tv.tv_usec/1000) - 
			 sms);
		}
	    }
            ret = 0;
            break;
         }

         /* process input buffer */
         {
            int np = 0;
         
            while (np<nr) {
               int n = nr - np;
               char *t = memchr(buf+np, 1, n);
            
               if (t!=NULL) {
                  n = t - buf;
               }

               if (n>0) {
                  int nw = write(wfd, buf + np, n);
                  if (nw<0) {
                     perror("domterm: write dom");
                     ret = 1;
                     break;
                  }
                  else if (nw==0) {
                     perror("domterm: dom eof!\n");
                     ret = 1;
                     break;
                  }
                  else if (nw!=n) {
                     fprintf(stderr, "domterm: dom partial write!\n");
                     ret = 1;
                     break;
                  }
                  np+=n;
               }

               if (t!=NULL) {
                  struct termios oldtio;

                  /* processing ctrl-A... */
                  np++;

                  /* save terminal settings... */
                  if (tcSaved) {
                     tcgetattr(1, &oldtio);
                     tcsetattr(1, TCSANOW, &tiosave);
                  }

                  while (1) {
                     const char str[] = "\ndomterm> ";
                     char line[1024];
                     int idx = 0;
                     int found = 0;

                     write(1, str, sizeof(str)-1);

                     while (idx<sizeof(line)-1) {
                        int nr = read(0, line+idx, sizeof(line)-1-idx);
                        char *t;
                        
                        if (nr<0) {
                           perror("read stdin");
                           ret = 1;
                           break;
                        }
                        else if (nr==0) {
                           /* fake a newline... */
                           line[idx] = '\n';
                           nr=1;
                        }
                        idx+=nr;
                        
                        if ((t=memchr(line, '\n', idx))!=NULL) {
                           *t = 0;
                           found = 1;
                           break;
                        }
                     }

                     if (strlen(line)==0) {
                        /* back to dom... */
                        break;
                     }
                     else if (strcmp(line, "status")==0) {
			char msg[12];
                        snprintf(msg, sizeof(msg), "%d", 
                                 WEXITSTATUS(cmdstatus));
                        write(1, msg, strlen(msg));
                     }
                     else if (strcmp(line, "q")==0 ||
                              strcmp(line, "qu")==0 ||
                              strcmp(line, "qui")==0 ||
                              strcmp(line, "quit")==0) {
                        /* exit program... */
                        int sig = SIGTERM;
                        write(sfds[1], &sig, sizeof(sig));
                        break;
                     }
                     else if (!found) {
                        fprintf(stderr, "\ndomterm: line too long\n");
                     }
                     else {
                        if (docmd(rfd, wfd, line)) {
                           fprintf(stderr, "can not exec command\n");
                        }
                     }
                  }

                  if (tcSaved) {
                     tcsetattr(1, TCSANOW, &oldtio);
                  }
               }
            }

            /* error... */
            if (ret!=0) break;
         }
      }

      /* deal with signals... */
      if (fds[2].revents & (POLLIN|POLLHUP)) {
         int sig;
         read(sfds[0], &sig, sizeof(sig));
         ret = 1;
	 if (sig==SIGCHLD) {
            int status;
            pid_t pid = wait(&status);
            if (pid==ibpid) { ibpid=-1; }
         }
         break;
      }
   }
   
   if (tcSaved) {
      /* restore terminal attributes... */
      tcsetattr(1, TCSANOW, &tiosave);
   }

   if (err!=NULL) {
      fprintf(stderr, ": %s\n", err);
   }
  
   /* make sure to kill iceboot -- if it was started...
    */
   if (ibpid!=-1) {
	kill(ibpid, SIGTERM);
	while (1) {
	   int status;
	   pid_t pid = wait(&status);
	   if (pid==ibpid) break;
        }
   }
 
   return ret;
}


