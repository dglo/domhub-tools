/*
   decodesn.c - jacobsen@npxdesigns.com
   Simple decompressor for supernova data
   May, 2005
*/

#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

int usage(void) {
  fprintf(stderr,
"Usage: decodesn <filename>\n"
          );
  return -1;
}

unsigned short swapShort(unsigned short x) {
  return (((x>>8)&0xFF)|((x&0xFF)<<8));
}

unsigned long long getTimeStamp(unsigned char * buf) {
  unsigned long long t = 0;
  int i; for(i=0;i<6;i++) {
    t <<= 8;
    t |= buf[i];
  }
  return t;
}

int main(int argc, char *argv[]) {
#define BUFS 4096
  if(argc != 2) return usage();
  char *filen = argv[1];
  printf("%s:\n", filen);
  int fd = open(filen, O_RDONLY, 0);
  if(fd < 0) {
    fprintf(stderr,"Couldn't open file %s for input (%s).\n",
            filen,strerror(errno));
    return -1;
  }

  while(1) {
    unsigned short hlen;
    unsigned char tsbuf[6];
    int p = 0;
    int nr = read(fd, &hlen, sizeof(hlen));
    if(nr == 0) break; // EOF
    if(nr != sizeof(hlen)) {
      fprintf(stderr,"Couldn't read %d bytes for block header!\n", sizeof(hlen));
      exit(-1);
    }
    unsigned short len = swapShort(hlen);
    p += nr;
    nr = read(fd, tsbuf, 6);
    if(nr != 6) {
      fprintf(stderr,"Couldn't read 6 bytes for timestamp!\n");
      exit(-1);
    }
    p += nr;
    unsigned long long t = getTimeStamp(tsbuf);
    int nbins = len-p;
 
    if(nbins > BUFS) {
      fprintf(stderr, "Corrupt nbins, len=%d bytes, nbins=%d > MAX(%dB).\n", len, nbins, BUFS);
      exit(-1);
    }
    printf("HDR(len=%huB t=%lld nbins=%d)\n", len, t, nbins);
    int ibin; for(ibin=0; ibin<nbins; ibin++) {
      unsigned char ccounts = 0;
      nr = read(fd, &ccounts, 1);
      if(nr != 1) {
	fprintf(stderr, "Short read of count data at bin %d!\n", ibin);
	exit(-1);
      }
      unsigned count = (int) ccounts;
      printf("\t%u counts\n", count);
    }
  }
  close(fd);
  return 1;
}
