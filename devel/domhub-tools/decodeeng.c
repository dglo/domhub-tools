/* decodeeng.c : C program to decode/test engineering format data from DOM
 *
 * hacked out of decodemoni.c from:
 * John Jacobsen, jacobsen@npxdesigns.com, for LBNL/IceCube
 *  $Id: decodeeng.c,v 1.2 2005-03-17 18:41:23 arthur Exp $
 *
 * Decode engineering format data to make sure it makes sense
 *
 * engineering file format is a bit strange, the wrapped
 * version is bigendian in the wrapper and little endian
 * in the contents
 */

#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <getopt.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/mman.h>

#define DEFAULTFILE "hits.out"

#include "bele.h"

static inline unsigned short get16(int le, const unsigned char *buf) {
   return (le) ? le16(buf) : be16(buf);
}

static unsigned long long get48(int le, const unsigned char *buf) {
   return (le) ? le48(buf) : be48(buf);
}

static const char *atwdFormat(int v) {
   if ( (v&1) == 0 ) return "ATWD not present";
   
   {
      static char ret[128];
      int np[] = { 32, 64, 16, 128 };
      
      snprintf(ret, sizeof(ret),
               "%s data, %d samples", 
               (v&2) ? "Short" : "Byte",
               np[((v&0xc)>>2)]);
      return ret;
   }
}


static const char *eventTrigType(int v) {
   if (v==0) {
      return "Test Pattern";
   }
   else if (v==1) {
      return "CPU Trigger";
   }
   else if (v==2) {
      return "Discriminator Trigger";
   }
   else if (v==3) {
      return "Flasher Trigger";
   }
   else return "Unknown trigger";
}

int usage(void) {
  fprintf(stderr, 
	  "Usage: decodeeng [-c] <file>\n"
	  " Option: -c    Assume testdaq/datacollector format\n");
  return -1;
}

int main(int argc, char *argv[]) {
   FILE *fptr;
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

   if (strcmp(fname, "-")==0) {
      fptr = stdin;
   }
   else if((fptr = fopen(fname, "r"))==NULL) {
      fprintf(stderr,"Couldn't open file %s for input.\n", fname);
      return -1;
   }
   
   {
      unsigned long long lastts = 0ULL;
      
      while (!feof(fptr)) {
         unsigned char buf[4096];

         if(wrapped) {
            if (fread(buf, 1, 32, fptr)!=32) {
               fprintf(stderr, 
                       "decodeeng: partial record getting wrapped header\n");
               return 1;
            }

            {  unsigned long long domid = be64(buf+8);
               unsigned long long tcal = be64(buf+24);
               printf("\nDOM %llx [%llx]\n", domid, tcal);
            }
         }
         
         if (fread(buf, 1, 4, fptr)!=4) {
            fprintf(stderr, "decodeeng: partial read getting len/format\n");
            return 1;
         }
         
         int format;
         int le;
         unsigned short rawformat = get16(1, buf+2);
         unsigned short len;
         int flen = 0;
         unsigned char atwd[4];
         int i;
         
         switch(rawformat) {
	    case 0x0100: le = 0; format = 1; break;
	    case 0x0200: le = 0; format = 2; break;
	    case 0x0001: format = 1; break;
	    case 0x0002: format = 2; break;
	    default:
               fprintf(stderr, "decodeeng: invalid format (0x%04hx) expecting "
                       "0x0100, 0x0200, 0x0001 or 0x0002\n", rawformat);
               return 1;
               break;
         }
         
         len = get16(le, buf);
         
         if (len<4 || len>sizeof(buf)) {
            fprintf(stderr, "decodeeng: invalid record size (%hu)\n", len);
            return 1;
         }
         
         if (fread(buf, 1, len-4, fptr)!=len-4) {
            fprintf(stderr, "decodeeng: partial read getting record\n");
            return 1;
         }
         
#define BOFFSET 4
         printf("\nEvent: \n\tlen=%hd\tendian=%s\n", len,le?"LITTLE":"BIG");
         printf("\tatwd=%d\n", buf[4-BOFFSET]&1);
         flen = buf[5-BOFFSET];
         printf("\tnumber of fadc samples=%d\n", buf[5-BOFFSET]);
         
         atwd[0] = buf[6-BOFFSET]&0xf;
         atwd[1] = buf[6-BOFFSET]>>4;
         atwd[2] = buf[7-BOFFSET]&0xf;
         atwd[3] = buf[7-BOFFSET]>>4;
         
         printf("\tatwd channel 0 format='%s'\n", atwdFormat(atwd[0]));
         printf("\tatwd channel 1 format='%s'\n", atwdFormat(atwd[1]));
         printf("\tatwd channel 2 format='%s'\n", atwdFormat(atwd[2]));
         printf("\tatwd channel 3 format='%s'\n", atwdFormat(atwd[3]));
         char tbyte   = buf[8-BOFFSET];
         char ttype   = tbyte & 0x0F;
         int  isUnk   = tbyte & (1<<7);
         int  LCupEna = tbyte & (1<<6);
         int  LCdnEna = tbyte & (1<<5);
         int  FBRun   = tbyte & (1<<4);
         printf("\ttrigger type='%s' flags=<",eventTrigType(ttype));
         int  p = 0;
         if(isUnk||LCupEna||LCdnEna||FBRun) {
            if(isUnk)   { if(p) printf(", "); printf("UNKNOWN_TRIG"); p=1; }
            if(LCupEna) { if(p) printf(", "); printf("LC_UP_ENA"); p=1; }
            if(LCdnEna) { if(p) printf(", "); printf("LC_DN_ENA"); p=1; }
            if(FBRun)   { if(p) printf(", "); printf("FB_RUN"); p=1; }
         } else {
            printf("none");
         }
         printf("> [%02x]\n", tbyte);
	 
         printf("\tspare=0x%02x\n", buf[9-BOFFSET]);
         {
            unsigned long long ts = get48(le, buf+10-BOFFSET);
            printf("\ttime stamp=0x%012llx ", ts);
            printf("(%.2fs), ", (double) ts/40e6);
            printf("dt=%.6fms\n", (double)(ts-lastts)/40e3);
            lastts = ts;
         }
         
         /* point idx to data... */
         {
            int idx = 16-BOFFSET;
         
            /* FIXME: get fadc data... */
            if (flen>0) printf("\n\tfadc data\n");
            for (i=0; i<flen; i++) {
               if ( (i%10)==0 ) printf("\n\t");
               else printf(" ");
               printf("%04x", get16(le, buf + idx)); idx+=2;
            }
            if (flen>0) printf("\n");
            
            /* FIXME: get atwd data... */
            for (i=0; i<4; i++) {
               int j;
               int np[] = { 32, 64, 16, 128 };
               const int n = np[ (atwd[i]&0xc)>>2 ];
               
               if ( (atwd[i]&1) == 0) continue;
               
               printf("\n\tatwd channel %d\n", i);
               if (atwd[i]&2) {
                  /* short ... */
                  for (j=0; j<n; j++) {
                     if ( (j%10) == 0 ) printf("\n\t");
                     else printf(" ");
                     printf("%04x", get16(le, buf+idx)); idx+=2;
                  } 
               }
               else {
                  /* unsigned char ... */
                  for (j=0; j<n; j++) {
                     if ( (j%20) == 0 ) printf("\n\t");
                     else printf(" ");
                     printf("%02x", buf[idx]); idx++;
                  }
               }
               printf("\n");
            }
         }
      }
   }
   
   if (strcmp(fname, "-")!=0) fclose(fptr);

   return 0;
}







