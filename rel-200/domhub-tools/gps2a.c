/* gps2a.c, convert gps timestring formatted by kalle in DOR-API,
 * "GPS Time String Buffering" to ascii
 */
#include <stdio.h>

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

int main(int argc, char *argv[]) {
   int ai=1;
   
   if (sizeof(struct GPSStruct)!=22) {
      fprintf(stderr, "gps2a: sizeof(gps)!=22, rather %u\n", 
              sizeof(struct GPSStruct));
      return 1;
   }

   if (argc<2) {
      fprintf(stderr, "usage: gps2a [options] file\n");
      return 1;
   }
   
   {
      FILE *fptr;

      if ((fptr=fopen(argv[ai], "r"))==NULL) {
         fprintf(stderr, "chkgps: can not open '%s' for reading\n", argv[ai]);
         return 1;
      }

      while (1) {
         struct GPSStruct gps;
         
         if (fread(&gps, sizeof(gps), 1, fptr)!=1) break;
         
         fwrite(gps.day, 1, 3, stdout);
         fwrite(&gps.colon0, 1, 1, stdout);
         fwrite(gps.hour, 1, 2, stdout);
         fwrite(&gps.colon1, 1, 1, stdout);
         fwrite(gps.minute, 1, 2, stdout);
         fwrite(&gps.colon2, 1, 1, stdout);
         fwrite(gps.second, 1, 2, stdout);
         fwrite(&gps.quality, 1, 1, stdout);

         fprintf(stdout, " ");
         {  int j;
         
            for (j=0; j<8; j++) {
               char hex[16] = "0123456789abcdef";
               fprintf(stdout, "%c%c", hex[(gps.clock[j]>>4)&0xf],
                      hex[gps.clock[j]&0xf]);
            }
            fprintf(stdout, "\n");
         }
      }
   
      fclose(fptr);
   }

   return 0;
}
