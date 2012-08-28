/* se.c, send/expect over domterm...
 */
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <stdlib.h>
#include <signal.h>

#include <sys/termios.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/poll.h>
#include <unistd.h>
#include <pty.h>
#include <regex.h>

/* get the expect string... */
static int getString(const char *line, char *s, int szs) {
   int i=0;
   
   memset(s, 0, szs);
   
   /* wait for " */
   while (*line && *line!='"') line++;

   /* skip it... */
   if (*line=='"') line++;

   /* everything except \" */
   while ( *line && i<szs-1 && *line != '"' ) {
      if (*line=='\\') {
         if (*(line+1)=='"') { 
            s[i] = '"'; 
            line++; 
         }
         else if (*(line+1)=='r') {
            s[i] = '\r';
            line++;
         }
         else if (*(line+1)=='n') {
            s[i] = '\n';
            line++;
         }
         else {
            s[i] = *line;
         }
      }
      else s[i] = *line;
      line++;
      i++;
   }
   s[i]=0;
   return i;
}

static int parseString(const char *line, char *s, int szs) {
   int n=0;
   
   memset(s, 0, szs);
   
   while (*line && *line!='"') line++;
   
   if (*line!='"') return -1;

   line++;
   
   while (*line && *line!='"' && n<szs) {
      if (*line=='\\') {
         if (line[1]=='r') {
            *s = '\r';
         }
         else if (line[1]=='n') {
            *s = '\n';
         }
         else if (line[1]=='"') {
            *s = '"';
         }
	 else if (line[1]=='$') {
	    *s = '$';
	 }
         else if (line[1]=='^') {
            *s = '^';
         }
         else {
            fprintf(stderr, "se: unknown escape character \\%c\n", line[1]);
            return -1;
         }
         line++;
      }
      else if (*line=='^') {
         if (line[1]=='A') {
            *s = 1;
         }
         else {
            fprintf(stderr, "se: unknown control character \\%c\n", line[1]);
            return -1;
         }
         line++;
      }
      else *s = *line;

      n++;
      s++;
      line++;
   }

   return n;
}

static int parseInt(const char *line) {
   while (isspace(*line)) line++;
   return atoi(line);
}

static int cleaningUp;
static pid_t domterm = (pid_t) -1;

static void sigchld(int sig) {
   domterm = (pid_t) -1;
   if (cleaningUp == 0) {
      fprintf(stderr, "se: domterm died, exiting...\n");
      exit(1);
   }
}

static void sigterm(int sig) {
   /* received a sigterm -- kill domterm... */
   if (domterm != (pid_t) -1) {
      kill(domterm, SIGTERM);
      domterm = (pid_t) -1;
   }
   exit(1);
}

static void flushInput(int master, int timeout) {
   /* wait a bit for any new data (and print it)...
    */
  struct pollfd fds[1];
  fds[0].fd = master;
  fds[0].events=POLLIN;
  while (poll(fds, 1, timeout)==1) {
    char rd[1024];
    int nr = read(master, rd, sizeof(rd));
    if (nr<=0) break;
    write(1, rd, nr);
  }
}

int main(int argc, char *argv[]) {
   int ai=1;
   char line[1024];
   int master, slave;
   pid_t pid;
   int sdtfd[2];

   /* exit handler... */
   signal(SIGTERM, sigterm);

   if (argc-ai != 1) {
      fprintf(stderr, "usage: se CWD\n"
                      "  where: C=card, W=wire pair, D=dom A or B\n"
	              "   e.g.: 00A is card 0, pair 0, dom A\n");
      return 1;
   }

   /* allocate a psuedo-tty */
   if (openpty(&master, &slave, NULL, NULL, NULL)<0) {
      perror("se: openpty");
      return 1;
   }

   /* prepare for fork... */
   signal(SIGCHLD, sigchld);
  
   /* signal pipe... */
   if (pipe(sdtfd)<0) {
      perror("se: pipe");
      return 1;
   }
 
   /* telnet host port */
   if ((pid=fork())<0) {
      perror("se: fork");
      return 1;
   }
   else if (pid==0) {
      char sfd[12];
      snprintf(sfd, sizeof(sfd), "%d", sdtfd[1]);
      close(0); dup(slave);
      close(1); dup(slave);
      close(slave);
      close(master);
      if (execlp("domterm", "domterm", "-q", "-s", sfd, argv[ai], NULL)<0) {
         perror("se: execl");
         return 1;
      }
   }
   else {
      domterm = pid;
      close(slave);
   }

   /* wait for domterm to be ready -- FIXME: check for 0x04!!! 
    *   since domterm messes with the terminal we have to wait
    * until it is done messing before sending data along or
    * data may be corrupt.  we sent along the write side of
    * the pipe on startup, here we just wait for the data (0x04) to
    * appear on the read side...
    */
   {  char c; read(sdtfd[0], &c, 1); }
   close(sdtfd[0]);
 
   /* main loop */
   while (fgets(line, sizeof(line), stdin)!=NULL) {
      if (strncmp(line, "send", sizeof("send")-1)==0) {
         char s[1024];
         int n = parseString(line + sizeof("send"), s, sizeof(s));
	 flushInput(master, 0);
         write(master, s, n);
      }
      else if (strncmp(line, "expect", sizeof("expect")-1)==0) {
         char s[1024];
         regex_t preg;
         char rd[4096];
         int ofs = 0;
         int err;
         
         getString(line + sizeof("expect"), s, sizeof(s));

         if ((err=regcomp(&preg, s, REG_EXTENDED|REG_NEWLINE))!=0) {
            char errbuf[1024];
            regerror(err, &preg, errbuf, sizeof(errbuf));
            fprintf(stderr, "se: regcomp: %s\n", errbuf);
            return 1;
         }
         
         /* read until we've received the expected string... */
         do {
            ofs=0;
            memset(rd, 0, sizeof(rd));
         
            while (ofs<sizeof(rd)-1) {
               regmatch_t pmatch[1];
               int nr = read(master, rd + ofs, sizeof(rd)-ofs-1);
               if (nr<0) {
                  perror("se: read master");
                  return 1;
               }
               else if (nr==0) {
                  fprintf(stderr, "se: master closed!\n");
                  return 1;
               }
               else {
                  write(1, rd+ofs, nr);
                  ofs+=nr;
                  if ( regexec(&preg, rd, 1, pmatch, 0)==0 ) break;
               }
            }
         } while (ofs==sizeof(rd)-1);

         regfree(&preg);
      }
      else if (strncmp(line, "sleep", sizeof("sleep")-1)==0) {
	 int secs = parseInt(line + sizeof("sleep"));
         sleep(secs);
      }
      else {
         /* hmmm... */
      }
   }

   /* wait a bit for input to flush... */
   flushInput(master, 1000);

   /* finish up domterm... */
   cleaningUp = 1;
   close(master);
   {
      int status;
      if (waitpid(pid, &status, 0)<0) {
	 perror("wait for domterm");
	 return 1;
      }
      return WEXITSTATUS(status);
   }
}










