#include <stdio.h>
#include <ctype.h>

struct GPSStruct {
   char soh;     /* must be 0x01 */
   char day[3];  /* julian day (ascii)... */
   char colon0;  /* must be ':' */
   char hour[2]; /* hour (ascii) */
   char colon1;  /* must be ':' */
   char minute[2]; /* minute */
   char colon2;  /* must be ':' */
   char second[2]; /* second */
   char quality; /* quality */
   unsigned char clock[8]; /* clock */
};

static unsigned long long be2ull(const unsigned char *s) {
   unsigned long long ret = 0;
   int i;
   for (i=0; i<8; i++) {
      ret<<=8;
      ret |= s[i];
   }
   return ret;
}

static unsigned ascii2u(const char *ascii, int len) {
   unsigned ret = 0;
   int i;
   
   for (i=0; i<len; i++) {
      ret *= 10;
      ret += ascii[i]-'0';
   }

   return ret;
}

static int allDigits(const char *s, int len) {
   int i;
   for (i=0; i<len; i++) if (!isdigit(s[i])) return 0;
   return 1;
}

/* return seconds or -1 on error... */
static int julianSeconds(const struct GPSStruct *gps) {
   unsigned day, hour, minute, sec;
   
   if (!allDigits(gps->day, 3)) return -1;
   day = ascii2u(gps->day, 3);
   
   if (!allDigits(gps->hour, 2)) return -2;
   hour = ascii2u(gps->hour, 2);
   if (hour > 24) return -3;
   
   if (!allDigits(gps->minute, 2)) return -4;
   minute = ascii2u(gps->minute, 2);
   if (minute > 59) return -5;
   
   if (!allDigits(gps->second, 2)) return -6;
   sec = ascii2u(gps->second, 2);
   if (sec > 59) return -7;
   
   return sec + minute*60 + hour * 60 * 60 + day * 24 * 60 * 60;
}

int main(int argc, char *argv[]) {
   int ai=1;
   int strict_quality = 0;
   
   if (sizeof(struct GPSStruct)!=22) {
      fprintf(stderr, "chkgps: sizeof(gps)!=22, rather %u\n", 
              sizeof(struct GPSStruct));
      return 1;
   }

   if (argc<2) {
      fprintf(stderr, "usage: chkgps [options] file\n");
      return 1;
   }
   
   for (; ai<argc; ai++) {
      FILE *fptr;
      int record = 0;
      struct GPSStruct last_gps;

      if ((fptr=fopen(argv[ai], "r"))==NULL) {
         fprintf(stderr, "chkgps: can not open '%s' for reading\n", argv[ai]);
         return 1;
      }

      while (1) {
         struct GPSStruct gps;
         
         if (fread(&gps, sizeof(gps), 1, fptr)!=1) break;
         
         record++;
         
         if (gps.soh!=1) {
            fprintf(stderr, "chkgps: %s: record %u: bad soh (0x%02x)\n",
                    argv[ai], record, gps.soh);
         }
         
         if (gps.colon0!=':' || gps.colon1!=':' || gps.colon2!=':') {
            fprintf(stderr, "chkgps: %s: record %u: "
                    "one or more invalid colons\n", argv[ai], record);
         }

         if (gps.quality!=' ') {
            if (gps.quality=='.') {
               if (strict_quality) {
                  fprintf(stderr, "chkgps: %s: record %u: quality is 10us\n",
                          argv[ai], record);
               }
            }
            else if (gps.quality=='*') {
               if (strict_quality) {
                  fprintf(stderr, "chkgps: %s: record %u: quality is 100us\n",
                          argv[ai], record);
               }
            }
            else if (gps.quality=='#') {
               if (strict_quality) {
                  fprintf(stderr, "chkgps: %s: record %u: quality is 1ms\n",
                          argv[ai], record);
               }
            }
            else if (gps.quality=='?') {
               if (strict_quality) {
                  fprintf(stderr, 
                          "chkgps: %s: record %u: quality is unknown\n",
                          argv[ai], record);
               }
            }
            else {
               fprintf(stderr, 
                       "chkgps: %s: record %u: "
                       "invalid quality char '%c' (0x%02x), \n",
                       argv[ai], record, gps.quality, gps.quality);
            }
         }
         
         if (record>20) {
            {  const unsigned long long dt = 
                  be2ull(gps.clock) - be2ull(last_gps.clock);
            
               if (dt!=20000000) {
                  fprintf(stderr, "chkgps: %s: record %u: "
                          "invalid clock difference: %llu\n", 
                          argv[ai], record, dt);

#if 0
                  fprintf(stderr, 
                          "  details: %llu [%llx] -> %llu [%llx]\n",
                          be2ull(last_gps.clock), be2ull(last_gps.clock),
                          be2ull(gps.clock), be2ull(gps.clock));
                  fprintf(stderr, 
                          "  details: ");
                  {  int j;
               
                     for (j=0; j<8; j++) {
                        char hex[16] = "0123456789abcdef";
                        printf("%c%c", hex[(last_gps.clock[j]>>4)&0xf],
                               hex[last_gps.clock[j]&0xf]);
                     }
                     printf(" -> ");
                     
                     for (j=0; j<8; j++) {
                        char hex[16] = "0123456789abcdef";
                        printf("%c%c", hex[(gps.clock[j]>>4)&0xf],
                               hex[gps.clock[j]&0xf]);
                     }
                     printf("\n");
                  }
#endif
               }
            }
            
            {  const int gps_seconds = julianSeconds(&gps);
               const int last_seconds = julianSeconds(&last_gps);
               
               if (gps_seconds<0) {
                  fprintf(stderr, 
                          "chkgps: %s: record %u: "
                          "one or more invalid times in timestring (%d)\n",
                          argv[ai], record, gps_seconds);
               }

               if (last_seconds>=0) {
                  if (last_seconds + 1 != gps_seconds) {
                     fprintf(stderr, 
                             "chkgps: %s: record %u: "
                             "invalid timestring difference: %d\n",
                             argv[ai], record, gps_seconds - last_seconds);
                  }
               }
            }
         }
         
         last_gps = gps;
      }
   
      fclose(fptr);
   }

   return 0;
}
