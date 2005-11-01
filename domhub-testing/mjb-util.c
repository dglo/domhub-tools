#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mjb-util.h"

struct TestStruct *parseTests(const char *fname) {
   FILE *fptr = fopen(fname, "r");
   char test[128], mode[128];
   int timeout;
   struct TestStruct *ret = NULL, *last = NULL;

   while (fscanf(fptr, "%s %d %s\n", test, &timeout, mode)==3) {
      struct TestStruct *t = 
         (struct TestStruct *) malloc(sizeof(struct TestStruct));
      t->mode = strdup(mode);
      t->test = strdup(test);
      t->timeout = timeout;
      t->next = NULL;
      if (ret==NULL) ret = t;
      if (last!=NULL) last->next = t;
      last = t;
   }
   fclose(fptr);
   return ret;
}

