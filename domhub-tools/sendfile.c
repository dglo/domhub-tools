/* send a file to a socket...
 *
 * we use this to send the intel hex file to the dom...
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sendfile.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/poll.h>

#include <fcntl.h>
#include <unistd.h>
#include <netdb.h>
#include <signal.h>

static void closeAlarm(int sig) {
   _exit(0);
}

int main(int argc, char *argv[]) {
   int fd, sfd, ai;
   ssize_t ts = 0;
   struct stat st;
   int nretries = 0;
   struct hostent *he;
   struct sockaddr_in serv_addr;
   int verbose=0;

   for (ai=1; ai<argc; ai++) {
      if (argv[ai][0]!='-') break;
      else if (strcmp(argv[ai], "-verbose")==0) verbose=1;
   }

   if (argc-ai!=3) {
      fprintf(stderr, "usage: sendfile [-verbose] file host port\n");
      return 1;
   }

   if ((fd=open(argv[ai], O_RDONLY))<0) {
      perror("open");
      fprintf(stderr, "sendfile: can't open '%s'\n", argv[ai]);
      return 1;
   }
   
   if (fstat(fd, &st)<0) {
      perror("fstat");
      return 1;
   }

#if 0
   if ((mem=(char *) mmap(NULL, st.st_size, PROT_READ,
			  MAP_SHARED, fd, 0))==MAP_FAILED) {
      perror("mmap");
      return 1;
   }
#endif

   if ((he=gethostbyname(argv[ai+1]))==NULL) {
      fprintf(stderr, "sendfile: can't lookup host: '%s'\n",  argv[ai+1]);
      return 1;
   }
   
   memset(&serv_addr, 0, sizeof(serv_addr));
   memcpy(&serv_addr.sin_addr.s_addr, *he->h_addr_list, 
	  sizeof(serv_addr.sin_addr.s_addr));
   serv_addr.sin_family      = AF_INET;
   serv_addr.sin_port        = htons(atoi(argv[ai+2]));
   
   if ((sfd = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
      perror("socket");
      return 1;
   }

   if (connect(sfd, (struct sockaddr *) &serv_addr, sizeof(serv_addr)) < 0) {
      perror("connect");
      return 1;
   }
   
   while (ts<st.st_size) {
      off_t offset = 0;
      ssize_t ns = sendfile(sfd, fd, &offset, st.st_size-ts);
      
      if (ns<0) {
	 perror("sendfile");
	 return 1;
      }
      else if (ns==0) {
	 sleep(1);
	 nretries++;
	 if (nretries==10) {
	    fprintf(stderr, "sendfile: error sending data!\n");
	    return 1;
	 }
      }
      else ts+=ns;
   }

   /* the famous lingering_close...
    *
    * we shutdown our side, and wait for the
    * other side to shutdown before closing up
    * shop...
    *
    * this code is necessary so that we're sure
    * everything gets cleanup up on the other
    * side...
    */
   printf("shutdown...\n");
   shutdown(sfd, 1);

   /* wait for other side to close...
    */
   signal(SIGALRM, closeAlarm);
   alarm(60);

   while (1) {
      struct pollfd fds[1];
      int ret;
      
      fds[0].fd = sfd;
      fds[0].events = POLLIN;
      
      if ((ret=poll(fds, 1, 2000))<0) {
	 perror("poll");
	 return 1;
      }

      if (ret==1 && fds[0].revents&POLLIN) {
	 char buf[1024];
	 int nr = read(sfd, buf, sizeof(buf));
	 if (nr<=0) break;
         if (verbose) write(1, buf, nr);
      }
   }

   printf("closing...\n");
   close(sfd);
   
   return 0;
}

