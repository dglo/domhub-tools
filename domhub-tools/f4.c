#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <pty.h>
#include <unistd.h>
#include <fcntl.h>

/* f4.c, control the watlow series f4 temperature
 * controller...
 */
#define POLYNOMIAL 0xA001

static unsigned short calc_crc(unsigned char *p, int n) {
   unsigned short crc = 0xffff;
   int i;

   for (i=0; i<n; i++) {
      int j;

      crc ^= (unsigned short ) p[i];
      for (j=0; j<8; j++) {
         if (crc & 0x0001) {
            crc>>=1;
            crc^=POLYNOMIAL;
         }
         else crc >>= 1;
      }
   }

   return crc;
}

/* read multiple registers... */
static int mbReadMultiple(unsigned char *pkt, unsigned short addr, 
                          unsigned short first, unsigned short n) {
   pkt[0] = addr;
   pkt[1] = 0x03;
   pkt[2] = first>>8;
   pkt[3] = first&0xff;
   pkt[4] = n>>8;
   pkt[5] = n&0xff;
   {  unsigned short crc = calc_crc(pkt, 6);
      pkt[6] = crc&0xff;
      pkt[7] = crc>>8;
   }
   return 8;
}

/* create loop back packet... */
static int mbLoopBack(unsigned char *pkt, unsigned short addr,
                      unsigned short data) {
   pkt[0] = addr;
   pkt[1] = 0x08;
   pkt[2] = 0;
   pkt[3] = 0;
   pkt[4] = data>>8;
   pkt[5] = data;
   {  unsigned short crc = calc_crc(pkt, 6);
      pkt[6] = crc&0xff;
      pkt[7] = crc>>8;
   }
   return 8;
}

static int mbWrite(unsigned char *pkt, unsigned short addr,
                   unsigned short reg,  unsigned short data) {
   pkt[0] = addr;
   pkt[1] = 0x06;
   pkt[2] = reg>>8;
   pkt[3] = reg&0xff;
   pkt[4] = data>>8;
   pkt[5] = data&0xff;
   {  unsigned short crc = calc_crc(pkt, 6);
      pkt[6] = crc&0xff;
      pkt[7] = crc>>8;
   }
   return 8;
}

#if 0
static void mbDump(unsigned char *pkt, int n) {
   printf("pkt:");
   {  int i;
      for (i=0; i<n; i++) printf(" %02x", pkt[i]);
   }
   printf("\n");
}
#endif

static int openSerial(int port) {
   char dev[32];
   struct termios buf;
   int fd;

   sprintf(dev, "/dev/ttyS%d", port);
   if ((fd=open(dev, O_RDWR))<0) {
      perror("can't open serial device");
      return 1;
   }

   /* setup termio parameters
    */
   buf.c_lflag = 0;
   buf.c_iflag = IGNBRK | IGNPAR;
   buf.c_cflag = B9600 | CS8 | CREAD | CLOCAL /* | CRTSXOFF | CRTSCTS */;
   buf.c_oflag = 0;
   buf.c_cc[VMIN] = 1;
   buf.c_cc[VTIME] = 0;

   cfsetispeed(&buf, B9600);
   cfsetospeed(&buf, B9600);

   if (tcsetattr(fd, TCSAFLUSH, &buf)<0) {
      fprintf(stderr, "can't set termios: %s\n", dev);
      return 1;
   }

   /* FIXME: clean out any old crap... */
   return fd;
}

static void usage(void) {
   fprintf(stderr, "usage: f4 [a addr]|[r start n]|[w reg val]|[l val]\n");
}

#if 0
static void serialDump(int fd) {
   printf("srd:");
   while (1) {
      char c = 0;
      {  read(fd, &c, 1);
         printf(" %02x", (unsigned char) c);
         fflush(stdout);
      }
   } 
   printf("\n");
}
#endif

/* read a message, returns:
 *
 * number of bytes in message
 *  or:
 * 0  CRC error
 * <0 error
 */
static int mbReadMsg(int fd, unsigned char *pkt, int max) {
   int idx = 0;
   int pktsz = max;

   if (max<5) {
      fprintf(stderr, "mbReadMsg: invalid max in pkt buffer\n");
      return -1;
   }
   
   while (idx<pktsz) {
      int nr = read(fd, pkt+idx, pktsz-idx);

#if 0
      printf("read succeded: nr=%d:", nr);
      {
         int j;
         for (j=0; j<nr; j++) printf(" %02x", pkt[idx+j]);
      }
      printf("\n");
#endif
      
      if (nr<0) {
         perror("mbReadMsg: read");
         return -1;
      }
      else if (nr==0) {
         fprintf(stderr, "mbReadMsg: unexpected eof\n");
         return -1;
      }
      else {
         int i;
         for (i=0; i<nr; i++, idx++) {
            if (idx==2) {
               if (pkt[1]==0x03 || pkt[1]==0x04) {
                  pktsz = pkt[2]+5;
               }
               else if (pkt[1]==0x06) {
                  pktsz = 8;
               }
               else if (pkt[1]==0x08) {
                  pktsz = 8;
               }
               else if (pkt[1]>=0x80) {
                  pktsz = 5;
               }
               else {
                  fprintf(stderr, "mbReadMsg: unrecognized cmd (%02x)\n",
                          pkt[1]);
                  return -1;
               }
               
               if (pktsz>max) {
                  fprintf(stderr, 
                          "mbReadMsg: "
                          "packet size (%d) is too big for buffer (%d)\n",
                          pktsz, max);
                  return 1;
               }
            }
         }
      }
   }

   /* make sure crc is ok... */
   {  unsigned short crc = calc_crc(pkt, pktsz-2);
      if ( (crc&0xff) == pkt[pktsz-2] && (crc>>8) == pkt[pktsz-1]) return idx;
      else return 0;
   }
}

/* deal with a read multiple result...
 */
static int mbReadMultipleReply(unsigned char *pkt, int n) {
   if (n<=0) {
      fprintf(stderr, "mbReadMultipleReply: invalid packet length\n");
      return 1;
   }

   /* FIXME: deal with exceptions... */
   
   if (pkt[1]!=0x03 && pkt[1]!=0x04) {
      fprintf(stderr, "mbParseReadMultiple: invalid command (%d)\n", pkt[1]);
      return 1;
   }
   
   {  int nvals = pkt[2]/2, i;
      for (i=0; i<nvals; i++) {
         unsigned short v = (pkt[3+2*i]<<8)|pkt[3+2*i+1];
         printf("%hu", v);
         if (i<nvals-1) printf(" ");
      }
      printf("\n");
   }
   
   return 0;
}

int main(int argc, char *argv[]) {
   int addr = 0;
   int fd = openSerial(1);
   int ai = 0;
  
   if (argc==0) {
      usage();
      return 1;
   }

   for (ai=1; ai<argc; ai++) {
      unsigned char pkt[256];

      if (strcmp(argv[ai], "a")==0 && ai+1<argc) {
         addr = atoi(argv[ai+1]);
         ai++;
      }
      else if (strcmp(argv[ai], "r")==0 && ai+2<argc) {
         int np = mbReadMultiple(pkt, addr,
                                 atoi(argv[ai+1]), atoi(argv[ai+2]));

         /* mbDump(pkt, np); */
         if (write(fd, pkt, np)!=np) {
            fprintf(stderr, "f4: unable to write!\n");
            return 1;
         }

         if ((np = mbReadMsg(fd, pkt, sizeof(pkt))) <= 0) {
            fprintf(stderr, "f4: unable to read message\n");
            return 1;
         }

         /* mbDump(pkt, np); */
         if (mbReadMultipleReply(pkt, np)) {
            fprintf(stderr, "f4: unable to parse read multiple reply\n");
            return 1;
         }
    
         ai+=2;
       }
       else if (strcmp(argv[ai], "w")==0 && ai+2<argc) {
          unsigned char rpkt[256];
          
          int np = mbWrite(pkt, addr, atoi(argv[ai+1]), atoi(argv[ai+2]));
          int nr;
          
          if (write(fd, pkt, np)!=np) {
             fprintf(stderr, "f4: unable to write pkt\n");
             return 1;
          }

          if ((nr=mbReadMsg(fd, rpkt, sizeof(rpkt))) <= 0) {
             fprintf(stderr, "f4: unable to read message\n");
             return 1;
          }

          if (nr!=np || memcmp(pkt, rpkt, np)!=0) {
             fprintf(stderr, "f4: unable to verify write packet\n");
             return 1;
          }

          ai+=2;
       }
       else if (strcmp(argv[ai], "l")==0 && ai+1<argc) {
          int np = mbLoopBack(pkt, addr, atoi(argv[ai+1]));
          unsigned char rpkt[256];
          int nr;

          if (write(fd, pkt, np)!=np) {
             fprintf(stderr, "f4: unable to write!\n");
             return 1;
          }

          if ((nr=mbReadMsg(fd, rpkt, sizeof(rpkt))) <= 0) {
             fprintf(stderr, "f4: unable to read message\n");
             return 1;
          }

          if (nr!=np || memcmp(pkt, rpkt, np)!=0) {
             fprintf(stderr, "f4: unable to verify loopback packet\n");
             return 1;
          }

          ai++;
       }
       else {
          usage();
          return 1;
       }
   }
   return 0;
}
