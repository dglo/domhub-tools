/* xovr.c, crossover fiducial calculation...
 *
 * from bob s:
 *
 * 1.  determine the baseline from the first n samples (nis about 19, if I
 *     recall correctly.
 * 2.  find the peak sample, and, thereby, the start of the downgoing
 *     portion of the waveform.
 * 3.  find the sample value (a) just above and the sample value (b) just
 *     below the baseline value
 * 4.  by linear interpolation find the fractional sample number where the
 *     linear interpolation crosses the baseline.
 * 5.  do the same procedure using the sample value above (a) and below (b).
 * 6.  take a weighted average of the two crossover values, weighting  4.
 *     twice as much as 5.
 *
 * I believe that earlier studies I did said the weighted average gave
 * better results than a single interpolation using just (a) and (b).  But
 * that study could be redone with more current data, and maybe the simpler
 * version would work as well.  Or maybe one could complicate things a bit
 * more by introducing a test saying that the waveform is "OK" provided the
 * difference of the two crossovers  are within some prescribed range.
 * Infinite possibilities.  I suggest, for now, just implementing what
 * we've been using.
 */
#include <stdio.h>
#include <stdlib.h>

/* number of samples in baseline calculation... */
#define NBASELINE 19

/* number of samples in a waveform... */
#define NSAMPLES  48

/* given y1 at x1=0 and y2 at x2=1, find
 * the x where the line through (x1, y1), (x2, y2)
 * intercepts the y value c
 *
 * point slope: y - y1 = (y2 - y1) / (x2 - x1) * (x - x1)
 * 
 *   where y=c =>
 *
 * c - y1 = (y2 - y1)/(x2 - x1) * (x - x1)
 *  =>
 * (c - y1) * (x2 - x1)/(y2 - y1) = x - x1
 *  =>
 * x = (c - y1) * [ (x2 - x1)/(y2 - y1) ] + x1
 */
static inline double interp(const double y1, const double y2, 
                            const double x1, const double x2,
                            const double c) {
   return (c-y1) * ( (x2-x1)/(y2-y1) ) + x1;
}

/* take an array and return crossover sample location
 * as double precision...
 *
 * returns:
 *   -1 if invalid number of samples
 *   -2 if no xover was found
 *   
 */
static double xovr(const double *values, int n) {
   int i, mxi, cxi;
   double sum, baseline, mx;

   if (n<NBASELINE+4) return -1;

   /* 1. calculate baseline... */
   for (sum=0, i=0; i<NBASELINE; i++) sum+=values[i];
   baseline=sum/NBASELINE;

   /* 2. find peak sample location past baseline... */
   mx=values[NBASELINE]; mxi=NBASELINE;
   for (i=NBASELINE+1; i<n; i++) {
      if (values[i]>mx) {
         mx=values[i];
         mxi=i;
      }
   }

   /* 3. find sample just before and after baseline value... */
   for (i=mxi, cxi=-1; i<n; i++) {
      if (values[i-1]>=baseline && values[i]<=baseline) {
         cxi=i;
         break;
      }
   }

   if (cxi==-1) return -2;

   {
      /* 4. by linear interpolation, find the first xover point... */
      double xovr1 = interp(values[cxi-1], values[cxi], 0, 1, baseline);
      /* 5. by linear interpolation, find the second xover point... */
      double xovr2 = interp(values[cxi-2], values[cxi+1], -1, 2, baseline);

      /* 6. take a weighted average of the two, weighting xovr1 twice
       *    that of xovr2...
       *
       * we want:  a + 2a = 1, => a=1/3, 2a=2/3
       */
      return (cxi-1) + (2*xovr1)/3 + xovr2/3;
   }
}

int main(int argc, char *argv[]) {
   char line[128]; 
   int n=0;
   double ar[NSAMPLES];
   const int nar = sizeof(ar)/sizeof(ar[0]);

   while (fgets(line, sizeof(line), stdin)!=NULL && n<nar) {
      ar[n]=atof(line);
      n++;
      if (n==NSAMPLES) {
         printf("%f\n", xovr(ar, n));
         n=0;
      }
   }

   if (n!=0) {
      fprintf(stderr, "xovr: partial read [%d]\n", n);
      return 1;
   }
   
   return 0;
}









