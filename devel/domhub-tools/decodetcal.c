/* decodeeng.c : C program to decode/test engineering format data from DOM
 *
 * hacked out of decodemoni.c from:
 * John Jacobsen, jacobsen@npxdesigns.com, for LBNL/IceCube
 *  $Id: decodetcal.c,v 1.2 2005-03-17 18:41:23 arthur Exp $
 *
 * Decode engineering format data to make sure it makes sense
 */

#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <getopt.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/mman.h>

#define DEFAULTFILE "file.eng"

static inline unsigned short get16(int le, const unsigned char *buf) {
   return (le) ? (buf[0]|(buf[1]<<8)) : (buf[1]|(buf[0]<<8));
}

static inline unsigned get32(int le, const unsigned char *buf) {
   return (le) ?
      (get16(1, buf)|(get16(1, buf+2)<<16)) : 
      (get16(0, buf+2)|(get16(0, buf)<<16));
}

static inline unsigned long long get64(int le, const unsigned char *buf) {
   return (le) ? 
      (get32(1, buf)|((unsigned long long)get32(1, buf+4)<<32)) : 
      (get32(0, buf+4)|((unsigned long long)get32(0, buf)<<32));
}

int usage(void) {
  fprintf(stderr, 
	  "Usage: decodetcal [-c] <file>\n"
	  " Option: -c    Assume testdaq/datacollector format\n");
  return -1;
}

int main(int argc, char *argv[]) {
   int fd;
   const unsigned char *buf;
   struct stat st;
   int option_index = 0;
   static struct option long_options[] = {
     {"help",    0,0,0},
     {"datacollector", 0,0,0},
     {"verbose", 0,0,0},
     {0,         0,0,0}
   };
   int wrapped=0, verbose=0;

   while(1) {
     char c = getopt_long (argc, argv, "hcv", long_options, &option_index);
     if (c == -1) break;
     switch(c) {
     case 'v': verbose = 1; break;
     case 'c': wrapped = 1; break;
     case 'h':
     default: exit(usage());
     }
   }

   int argcount = argc-optind;
   char * fname = DEFAULTFILE;
   if(argcount >= 1) {
     fname = argv[optind];
   }

   if((fd = open(fname, O_RDONLY)) < 0) {
      fprintf(stderr,"Couldn't open file %s for input.\n", fname);
      return -1;
   }

   if ((fstat(fd, &st))<0) {
      perror("decodeeng: fstat");
      return 1;
   }

   if ((buf=(const unsigned char *) mmap(0, st.st_size, 
                                         PROT_READ, MAP_PRIVATE, 
                                         fd, 0))==MAP_FAILED) {
      perror("decodeeng: mmap");
      return 1;
   }
   
   {
      off_t idx = 0;
      unsigned num = 0;
      
      while (idx<st.st_size) {
         int le = 1;

         if (st.st_size - idx < 292) {
            fprintf(stderr, "decodeeng: partial record\n");
            return 1;
         }

	 if(wrapped){ printf("DOM id: 0x%llx\n", get64(le, buf+idx)); idx+=8; }

         /* skip header */
         idx+=4;
         
         {
            unsigned long long dor_t0;
            unsigned long long dor_t3;
            unsigned short dorwf[64];
            unsigned long long dom_t1;
            unsigned long long dom_t2;
            unsigned short domwf[64];
            int i;
         
            dor_t0 = get64(le, buf+idx); idx+=8;
            dor_t3 = get64(le, buf+idx); idx+=8;
            for (i=0; i<64; i++) { dorwf[i] = get16(le, buf+idx); idx+=2; }
            
            dom_t1 = get64(le, buf+idx); idx+=8;
            dom_t2 = get64(le, buf+idx); idx+=8;
            for (i=0; i<64; i++) { domwf[i] = get16(le, buf+idx); idx+=2; }
               
            printf("cal(%d) dor_tx(0x%llx) dor_rx(0x%llx) dom_rx(0x%llx) "
                   "dom_tx(0x%llx)\n", num, dor_t0, dor_t3, dom_t1, dom_t2);

            printf("dor_wf(");
            for (i=0; i<63; i++) printf("%hd, ", dorwf[i]);
            printf("%hd)\n", dorwf[63]);

            printf("dom_wf(");
            for (i=0; i<63; i++) printf("%hd, ", domwf[i]);
            printf("%hd)\n", domwf[63]);

            printf("\n");
         }
         
         num++;
      }
   }

   close(fd);

   return 0;
}





