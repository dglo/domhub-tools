/* domserv.c, open a network accessible pseudo-tty for
 * iceboot-sim or iceboot-dor or a ttyS? for iceboot on 
 * the serial port.  this gives us a consistent view of
 * iceboot from the outside, we then route this view through
  * a tcp socket (ports):
 *
 *   2000 serial telnet
 *   3000 serial raw
 *   4000 DOR telnet
 *   4500 DOR raw
 *   5000 SIM telnet
 *   5500 SIM raw
 *
 * FIXME: need much better logging.
 * FIXME: nsims should be adjustable.
 * FIXME: all fds should be set to non-blocking
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <errno.h>
#include <ctype.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netdb.h>
#include <netinet/in.h>
#include <inttypes.h>
#include <unistd.h>
#include <pty.h>
#include <poll.h>

#define MAXPKTSIZE 4092

/* port definitions... */
#define SERIAL_PORT     2000
#define SERIAL_PORT_RAW 3000
#define DOR_PORT        4000
#define DOR_PORT_RAW    4500
#define SIM_PORT        5000
#define SIM_PORT_RAW    5500

static int servSerial = 1;
static int servDOR = 1;
static int servSim = 1;

/* are we in dh mode? */
static int dhmode = 0;
static int dhReqOutput = 0;

/* return number of devices we support...
 */
static int nserial(void) { return (servSerial) ? 2 : 0; }

static int isDORCard(int i) {
   char path[128];
   sprintf(path, "/proc/driver/domhub/card%d", i);
   return access(path, R_OK|X_OK)==0;
}

static int ndors(void) {
   static int nd = -1;
   
   if (nd==-1) {
      int ncards = 0, i;
      for (i=0; i<16; i++) if (isDORCard(i)) ncards++;
      nd = ncards*8;
   }
   return (servDOR) ? nd : 0;
}

static int nsims(void) {
   /* FIXME: make this adjustable... */
   return (servSim) ? 64 : 0;
}

static int ndevs(void) {
   static int n = -1;
   if (n==-1) {
      n = nserial() + ndors() + nsims();
   }
   return n;
}

struct DOMListStruct;
typedef struct DOMListStruct DOMList;

struct DOMListStruct {
   const char *type;     /* "serial", "DOR", "sim" */
   pid_t slv;            /* slave pid */
   int sfd;              /* telnet listen socket fd... */
   int rsfd;             /* raw listen socket fd... */
   int efd;              /* external descriptor (telnet/raw socket) */
   int ifd;              /* internal descriptor (master side of (p)tty) */
   int port;             /* telnet socket port */
   int rawport;          /* raw socket port */
   int (*start)(DOMList *); /* startup routine... */
   int isRaw;            /* is this a raw or telnet connection? */
};

static void initDOMList(DOMList *dl) {
   dl->slv = (pid_t) -1;
   dl->sfd = dl->rsfd = -1;
   dl->efd = -1;
   dl->ifd = -1;
   dl->start = NULL;
}

static int sockListener(int port) {
   struct sockaddr_in server;
   int one = 1;
   int sock = socket(AF_INET, SOCK_STREAM, 0);
   if (sock<0) {
      perror("opening stream socket");
      return -1;
   }

   setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(int));
  
   server.sin_family      = AF_INET;
   server.sin_addr.s_addr = INADDR_ANY;
   server.sin_port        = ntohs(port);
   if (bind(sock, (struct sockaddr *) &server, sizeof server)<0) {
      if (!dhmode) perror("bind socket");
      close(sock);
      return -1;
   }
  
   /* listen on new client socket...
    */
   if (listen(sock, 1)<0) {
      if (!dhmode) perror("listen");
      close(sock);
      return -1;
   }

   return sock;
}

static int openListeners(DOMList *dl) {
   if (dl->sfd==-1 && dl->rsfd==-1 && dl->efd==-1) {
      dl->sfd = sockListener(dl->port);
      dl->rsfd = sockListener(dl->rawport);

      /* both ports are quiet, open listeners... */
      if (!dhmode || dhReqOutput) {
	 if (dl->sfd>=0 && dl->rsfd>=0) {
	    printf("open %d %d\n", dl->port, dl->rawport);
	 }
	 else {
	    printf("failed '%s'\n", strerror(errno)); 
	    if (dl->sfd>=0) close(dl->sfd);
	    if (dl->rsfd>=0) close(dl->rsfd);
	 }
	 fflush(stdout);
	 dhReqOutput = 0;
      }
   }
   return 0;
}

static void closeListeners(DOMList *dl) {
   if (dl->sfd!=-1) {
      if (shutdown(dl->sfd, SHUT_RDWR)<0) {
	 perror("shutdown");
      }
      close(dl->sfd);
      dl->sfd = -1;
   }
   if (dl->rsfd!=-1) {
      if (shutdown(dl->rsfd, SHUT_RDWR)<0) {
	 perror("shutdown");
      }
      close(dl->rsfd);
      dl->rsfd = -1;
   }
}

static void icebootTerm(struct termios *buf) {
   /* setup iceboot terminal.
    *
    * FIXME: what about raw?!?
    */
   buf->c_lflag = 0;
   buf->c_iflag = IGNPAR | IGNBRK;
   buf->c_oflag = 0;
   buf->c_cflag = CLOCAL | CS8;
   buf->c_cc[VMIN] = 1;
   buf->c_cc[VTIME] = 0;
}

static int startSerial(DOMList *dl) {
   /* open tty... */
   char dev[32];
   struct termios buf;
   int fd;

   sprintf(dev, "/dev/ttyS%d", dl->port-SERIAL_PORT-1);
   if ((fd=open(dev, O_RDWR|O_NONBLOCK))<0) {
      perror("can't open serial device");
      return 1;
   }
   
   /* setup termio parameters
    */
   buf.c_lflag = 0;
   buf.c_iflag = IGNBRK | IGNPAR;
   buf.c_cflag = B115200 | CS8 | CREAD | CLOCAL /* | CRTSXOFF | CRTSCTS */;
   buf.c_oflag = 0;
   buf.c_cc[VMIN] = 1;
   buf.c_cc[VTIME] = 0;

   cfsetispeed(&buf, B115200);
   cfsetospeed(&buf, B115200);
   
   if (tcsetattr(fd, TCSAFLUSH, &buf)<0) {
      fprintf(stderr, "can't set termios: %s\n", dev);
      return 1;
   }

#if 0
   /* blocking mode...
    */
   if (fcntl(fd, F_SETFL, O_RDWR)<0) {
      perror("fcntl");
      return 1;
   }
#endif

   dl->ifd = fd;

   return 0;
}

static int forkDOM(DOMList *dl, const char *prog) {
   char name[64];
   pid_t pid;
   int mfd;
   struct termios buf;
   
   icebootTerm(&buf);

   if ((pid=forkpty(&mfd, name, &buf, NULL))<0) {
      perror("forkpty");
      return 1;
   }
   else if (pid==0) {
      /* child... */
      if (execl(prog, prog, NULL)<0) {
	 perror("execl");
	 return 1;
      }
   }
   
   dl->slv = pid;
   dl->ifd = mfd;
   return 0;
}

static int startDOR(DOMList *dl) {
   /* attempt to open dor...
    */
   char name[64];
   const int dom = dl->port - DOR_PORT - 1;
   const int card = dom/8;
   const int wire = (dom/2)%4;
   const int ab = dom%2;
   int fd;

   if (!dhmode) 
      printf("dom(%d) card wire ab: %d %d %d\n", dom, card, wire, ab);
   
   sprintf(name, "/dev/dhc%dw%dd%c", card, wire, (ab==0) ? 'A' : 'B');
   if ((fd=open(name, O_RDWR))<0) {
      perror("open");
      return 1;
   }

   dl->ifd = fd;

   return 0;
}

static int startSim(DOMList *dl) {
   return forkDOM(dl, "./Linux-i386/bin/iceboot");
}

/* negotiate telnet parameters...
 */
static void telnetNeg(DOMList *dl) {
   int fd = dl->efd;
   unsigned char buf[3];
   buf[0] = 255;
   buf[1] = 251;
   buf[2] = 1; /* iac will echo ... */
   write(fd, buf, 3);

   buf[0] = 255;
   buf[1] = 251;
   buf[2] = 3; /* suppress go ahead... */
   write(fd, buf, 3);
}

/* startup the slave if necessary...
 */
static int openSlave(DOMList *dl) {
   if ( (dl->efd!=-1) && dl->slv==(pid_t) -1 && dl->ifd==-1) {
      if (dl->start(dl)) {
	 fprintf(stderr, "domserv: unable to start %s\n", dl->type);
	 return 1;
      }
   }
   
   return 0;
}

/* clean up after slave error...
 */
static void closeSlave(DOMList *dl) {
   if (dl->slv!=(pid_t) -1) kill(dl->slv, SIGTERM);
   if (dl->efd!=-1) { close(dl->efd); dl->efd = -1; }
   if (dl->ifd!=-1) { close(dl->ifd); dl->ifd = -1; }
   if (dl->slv!=(pid_t) -1) {
      int status;
      
      if (!dhmode) {
	 printf("domserv: closeSlave: waiting for %d to die...\n",
		dl->slv);
      }
      
      waitpid(dl->slv, &status, 0);
	
      if (!dhmode) {
	 printf("domserv: closeSlave: %d died with status %d...\n",
		dl->slv, status);
      }
      
      dl->slv = (pid_t) -1;
   }
}

static int scanTelnet(unsigned char *buffer, int len) {
   int i;
   static int iac = 0;
		     
   i = 0;
   while (i<len) {
      if (iac) {
	 if (buffer[i]==0xff) {
	    iac=0;
	    i++;
	 }
	 else {
	    iac++;
	    memmove(buffer+i, buffer+i+1, len-i);
	    len--;
	    if (iac==3) iac=0;
	 }
      }
      else {
	 if (buffer[i]==0xff) {
	    iac = 1;
	    if (i<len-1) {
	       memmove(buffer+i, buffer+i+1, len-i);
	       len--;
	    }
	 }
	 else if (buffer[i]==0) {
	    /* remove nop... */
	    memmove(buffer+i, buffer+i+1, len-i);
	    len--;
	 }
	 else i++;
      }
   }
   return len;
}

static DOMList *newDOMList(void) {
   const int n = ndevs();
   int i, di;
   
   DOMList *dl = (DOMList *) calloc(n, sizeof(DOMList));
   if (dl==NULL) {
      fprintf(stderr, "domserv: can't allocate %d DOMs\n", n);
      return NULL;
   }
   
   for (i=di=0; i<nserial(); i++, di++) {
      initDOMList(dl + di);
      dl[di].type = "serial";
      dl[di].port = SERIAL_PORT + 1 + i;
      dl[di].rawport = SERIAL_PORT_RAW + 1 + i;
      dl[di].start = startSerial;
   }

   for (i=0; i<8; i++) {
      int j;
      if (isDORCard(i)) {
	 for (j=0; j<8; j++, di++) {
	    initDOMList(dl+di);
	    dl[di].type = "DOR";
	    dl[di].port = DOR_PORT + 1 + i*8+j;
	    dl[di].rawport = DOR_PORT_RAW + 1 + i*8+j;
	    dl[di].start = startDOR;
	 }
      }
   }

   for (i=0; i<nsims(); i++, di++) {
      initDOMList(dl + di);
      dl[di].type = "sim";
      dl[di].port = SIM_PORT + 1 + i;
      dl[di].rawport = SIM_PORT_RAW + 1 + i;
      dl[di].start = startSim;
   }
   
   return dl;
}

static int linetoidx(const char *line, DOMList *dl) {
   const int n = ndevs();
   const char *type;
   int port, i;

   /* parse line:
    *
    * dom card pair dom
    * serial port
    * sim instance
    *
    * responses:
    *
    * ports 1024 1524 (telnet raw)
    * failed msg...
    */
   if (strncmp(line, "dom ", 4)==0) {
      line += 4;
      type = "DOR";
      port = DOR_PORT;
   }
   else if (strncmp(line, "serial ", 7)==0) {
      line += 7;
      type = "serial";
      port = SERIAL_PORT;
   }
   else if (strncmp(line, "sim ", 4)==0) {
      line += 4;
      type = "sim";
      port = SIM_PORT;
   }
   else {
      printf("failed invalid command (dom|serial|sim)\n");
      return -1;
   }

   if (strcmp(type, "DOR")==0) {
      /* card pair dom */
      if (strlen(line)<3 || 
	  !isdigit(line[0]) ||
	  !isdigit(line[1]) ||
	  !(line[2]=='A' || line[2]=='B')) {
	 printf("failed invalid command (card pair dom)\n");
	 return -1;
      }

      port += 1 + (line[0]-'0')*8 + (line[1]-'0')*2 + (line[2]-'A') ;
   }
   else if (strcmp(type, "serial")==0) {
      /* port (1-2) */
      if (!isdigit(line[0])) {
	 printf("failed invalid command (1|2)\n");
	 return -1;
      }
      
      port += 1 + (line[0]-'1');
   }
   else if (strcmp(type, "sim")==0) {
      /* sim (1-64) */
      char b[8];
      int i;
      memset(b, 0, sizeof(b));
      for (i=0; i<sizeof(b)-1 && isdigit(line[i]); i++) b[i] = line[i];
      port += atoi(b);
   }

   for (i=0; i<n; i++) {
      if (strcmp(dl[i].type, type)==0) {
	 if (dl[i].port==port) return i;
      }
   }

   printf("failed can not find device for port (%d)\n", port);
   return -1;
}

int main(int argc, char *argv[]) {
   DOMList *dl = NULL;
   struct pollfd *fds = NULL;
   int i, ai;
   char *dhe = NULL;
   int chkStdin = 0;

   if ((dl=newDOMList()) == NULL) {
      fprintf(stderr, "domserv: can't get DOR list...\n");
      return 1;
   }

   if ((fds=(struct pollfd *)
	calloc(1+ndevs()*3, sizeof(struct pollfd)))==NULL) {
      fprintf(stderr, "domserv: can't allocate pollfds\n");
      return 1;
   }

   /* process options...
    */
   for (ai=1; ai<argc; ai++) {
      if (strcmp(argv[ai], "-dh")==0) {
	 dhmode = 1;
	 chkStdin = 1;
      }
      else {
	 fprintf(stderr, "usage: domserv [-dh]\n");
	 return 1;
      }
   }

   /* open dh mode flags... */
   if (dhmode) {
      if ((dhe = (char *) calloc(ndevs(), 1)) == NULL) {
	 fprintf(stderr, "unable to calloc\n");
	 return 1;
      }
   }

   /* FIXME: daemonize
   if (daemon(1, 1)<0) {
      perror("daemon");
      return 1;
   }
   */

   /* event loop...
    */
   while (1) {
      int nfds = 0;
      int ret, j;
      int ld = 0;
      int lfd = 0;

      if (chkStdin) {
	 fds[nfds].fd = 0;
	 fds[nfds].events = POLLIN;
	 nfds++;
      }
      
      for (i=0; i<ndevs(); i++) {
	 /* if this dom is not enabled, don't do anything... */
	 if (dhmode && dhe[i]==0) continue;

	 if (openSlave(dl + i)) {
	    fprintf(stderr, "can't start slave for DOM %d\n", i);
	    return 1;
	 }

	 /* do we need to start listeners... */
	 if (openListeners(dl + i)) {
	    fprintf(stderr, "can't open sockets for DOM %d\n", i);
	    return 1;
	 }
      }
      
      /* setup fd list... */
      for (i=0; i<ndevs(); i++) {
	 if (dl[i].sfd!=-1) {
	    fds[nfds].fd = dl[i].sfd;
	    fds[nfds].events = POLLIN;
	    nfds++;
	 }
	 if (dl[i].rsfd!=-1) {
	    fds[nfds].fd = dl[i].rsfd;
	    fds[nfds].events = POLLIN;
	    nfds++;
	 }
	 if (dl[i].efd!=-1) {
	    fds[nfds].fd = dl[i].efd;
	    fds[nfds].events = POLLIN;
	    nfds++;
	 }
	 if (dl[i].ifd!=-1) {
	    fds[nfds].fd = dl[i].ifd;
	    fds[nfds].events = POLLIN;
	    nfds++;
	 }
      }

      /* wait for events... */
      if ((ret=poll(fds, nfds, -1))<0) {
	 if (errno==EINTR) {
	    /* ignore interrupts... */
	 }
	 else {
	    perror("poll");
	    return 1;
	 }
      }

      /* check for stdin... */
      if (chkStdin && (fds[0].revents&POLLIN)) {
	 char line[128];
	 int idx = -1, en = -1, nr;

	 /* deal with input... */
	 memset(line, 0, sizeof(line));
	 
	 if ((nr=read(0, line, sizeof(line)-1))<0) {
	    perror("read from stdin");
	    return 0;
	 }
	 else if (nr==0) {
	    /* stdin is closed! */
	    chkStdin = 0;
	 }
	 else {
	    if (strncmp(line, "open ", 5)==0) {
	       idx=linetoidx(line + 5, dl);
	       en = 1;
	    }
	    else if (strncmp(line, "close ", 6)==0) {
	       idx=linetoidx(line + 6, dl);
	       en = 0;
	    }
	    else {
	       printf("failed invalid command (open|close)\n");
	    }
	 }
	
	 if (idx!=-1 && en!=-1) {
	    /* found one! */
	    dhe[idx] = en;

	    /* close input... */
	    if (en==0) {
	       /* cleanup port... */
	       closeSlave(dl+idx);
	       closeListeners(dl+idx);
               printf("close %d %d\n", dl[idx].port, dl[idx].rawport);
               fflush(stdout);
	       dhReqOutput = 0;
	    }
	    else dhReqOutput = 1;
	 }
      }

      /* FIXME: fd -> DOMList map would be nice if
       * there are too many fds here...
       */
      for (j=0; j<ret; j++) {
	 for (i=lfd; i<nfds; i++) {
	    if (fds[i].revents) {
	       int k;

	       /* find the device... */
	       for (k=ld; k<ndevs(); k++) {
		  /* buffer must _not_ be more than 4096 */
		  unsigned char buffer[MAXPKTSIZE];

		  if (dl[k].sfd==fds[i].fd) {
		     if (!dhmode) printf("accept: %d\n", dl[k].port);
		     if ((dl[k].efd = accept(dl[k].sfd, NULL, NULL))<0) {
			perror("accept");
		     }
		     closeListeners(dl+k);
		     telnetNeg(dl+k);
		     dl[k].isRaw = 0;
		     ld = k + 1;
		     break;
		  }
		  else if (dl[k].rsfd==fds[i].fd) {
		     if (!dhmode) printf("accept: %d\n", dl[k].rawport);
		     if ((dl[k].efd = accept(dl[k].rsfd, NULL, NULL))<0) {
			perror("accept");
		     }
		     closeListeners(dl+k);
		     dl[k].isRaw = 1;
		     ld = k + 1;
		     break;
		  }
		  else if (dl[k].efd==fds[i].fd) {
		     /* data coming in on telnet... */
		     int ret = read(fds[i].fd, buffer, sizeof(buffer));
		     int pp;

		     if (!dhmode) {
			printf("read %d from %s: ", ret, 
			       dl[k].isRaw ? "raw" : "telnet");
		     
			for (pp=0; pp<10 && pp<ret; pp++)
			   printf("0x%02x ", buffer[pp]);
			if (pp<ret) printf("...");
			printf("\n");
		     }
		     
		     if (ret<0) {
			/* FIXME: eintr?!?!? */
			perror("read");
			close(dl[k].efd);
			dl[k].efd = -1;
		     }
		     else if (ret==0) {
			/* socket closed... */
			close(dl[k].efd);
			dl[k].efd = -1;
		     }
		     else {
			/* FIXME: should we put writes in the poll
			 * loop too?
			 */
			if (!dl[k].isRaw) ret = scanTelnet(buffer, ret);
			
			if (dl[k].ifd!=-1) {
			   int nw = 0;
			   int nretries = 0;
			   
			   while (nw<ret) {
			      int n = write(dl[k].ifd, buffer + nw, ret - nw);
			      if (n<0) {
				 if (errno==EAGAIN && nretries<10) {
				    /* pause a bit... */
				    poll(NULL, 0, 100);
				    nretries++;
				 }
				 else {
				    perror("write");
				    closeSlave(dl + k);
				    break;
				 }
			      }
			      else if (n==0) {
				 closeSlave(dl+k);
				 break;
			      }
			      else {
				 nw+=n;
				 nretries = 0;
			      }
			   }
			}
		     }
		     ld = k + 1;
		     break;
		  }
		  else if (dl[k].ifd==fds[i].fd) {
		     /* data coming in on terminal -- push it along... */
		     int ret = read(fds[i].fd, buffer, sizeof(buffer));
		     int pp;

		     if (!dhmode) {
			printf("read %d from pty: ", ret);
			for (pp=0; pp<10 && pp<ret; pp++)
			   printf("0x%02x ", buffer[pp]);
			if (pp<ret) printf("...");
			printf("\n");
		     }
		     
		     if (ret<0) {
			/* FIXME: eintr?!?!? */
                        if (errno!=EAGAIN) {
                           perror("read");
                           closeSlave(dl+k);
                        }
		     }
		     else if (ret==0) {
			/* terminal closed -- close sockets
			 * as well... 
			 */
			closeSlave(dl+k);
		     }
		     else {
			int nw = 0;

			if (dl[k].efd>0) {
			   int nretries = 0;
			   while (nw<ret) {
			      int n = write(dl[k].efd, buffer + nw, ret - nw);
			      if (n<0) {
				 if (errno==EAGAIN && nretries<10) {
				    poll(NULL, 0, 100);
				    nretries++;
				 }
				 else {
				    close(dl[k].efd);
				    dl[k].efd = -1;
				    perror("write");
				    break;
				 }
			      }
			      else if (n==0) {
				 close(dl[k].efd);
				 dl[k].efd = -1;
				 break;
			      }
			      else {
				 nw+=n;
				 nretries=0;
			      }
			   }
			}
		     }
		     ld = k + 1;
		     break;
		  }
	       }
	       lfd = i + 1;
	       break;
	    }
	 }
      }
   }

   /* FIXME: wait for children before exiting...
    */
   return 0;
}
