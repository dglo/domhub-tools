/* open-test.c, open and close the driver...
 */
#include <stdio.h>
#include <string.h>
#include <ctype.h>

#include <sys/time.h>
#include <fcntl.h>
#include <unistd.h>

/* t2 - t1 in s */
static double diffsec(const struct timeval *t1, const struct timeval *t2) {
   long long usec1 = t1->tv_usec + t1->tv_sec * 1000000LL;
   long long usec2 = t2->tv_usec + t2->tv_sec * 1000000LL;
   return (double) (usec2 - usec1) * 1e-6;
}

static double timeOpen(const char *path) {
   struct timeval start, done;
   int fd;

   gettimeofday(&start, NULL);
   if ((fd=open(path, O_RDWR))<0) {
      perror("open-test: open");
      return -1;
   }
   gettimeofday(&done, NULL);
   close(fd); 
   return diffsec(&start, &done);
}

static inline int newapi(void) {
   return access("/proc/dor", F_OK)==0;
}

int main(int argc, char *argv[]) {
   char path[128];

   if (argc!=2 || strlen(argv[1])!=3) {
      fprintf(stderr, "usage: open-test CWD\n");
      return 1;
   }

   {  int ms, i;
      const int cnt = 100;
      double sum = 0;

      if (newapi()) {
         snprintf(path, sizeof(path), "/dev/dor/%c%c%c", argv[1][0],
                  argv[1][1], toupper(argv[1][2]));
      }
      else {
         snprintf(path, sizeof(path), "/dev/dhc%cw%cd%c", argv[1][0],
 	          argv[1][1], argv[1][2]);
      }

      ms = (int) (timeOpen(path)*1000);

      for (i=0; i<cnt; i++) {
         const double v = timeOpen(path);
         if (v<0) return 1;
         sum+=v; 
      }
      sum*=1000;
      printf("%s %d %d %d\n", argv[1], ms, (int) sum, cnt);
   }

   return 0;
}

