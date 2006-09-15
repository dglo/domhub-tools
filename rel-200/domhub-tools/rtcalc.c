/* rtcalc.c.  compute round trip time, stdin contains:
 *
 * dorf domf dor_tx dor_rx dom_tx dom_rx
 *
 * round trip time is spit out...
 *  ( -(domtx -  domrx )/2 + (dorrx - dortx) - 2*47  + dorfid + domfid )*50
 */
#include <stdio.h>

int main(int argc, char *argv[]) {
   double dorf, domf;
   unsigned long long dor_tx, dor_rx, dom_tx, dom_rx;
   char line[4096];
   
   while (fgets(line, sizeof(line), stdin)!=NULL) {
      if (sscanf(line, "%lf %lf %Lu %Lu %Lu %Lu", &dorf, &domf,
                 &dor_tx, &dor_rx, &dom_tx, &dom_rx)!=6) {
         fprintf(stderr, "rtcalc: can't parse input, should be"
                 " dorf domf dor_tx dor_rx dom_tx dom_rx!\n");
         return 1;
      }

      {  unsigned long long domdt=(dom_tx - dom_rx)&0x0000ffffffffffffULL;
         unsigned long long dordt=(dor_rx - dor_tx)&0x0000ffffffffffffULL;

         printf("%.4f\n", (dordt - domdt/2.0 - 2*47 + dorf + domf)*50);
      }
   }
   
   return 0;
}
