#ifndef MJBUTILHEADER
#define MJBUTILHEADER

struct TestStruct {
   const char *test;
   int timeout;
   const char *mode;
   struct TestStruct *next;
};

struct TestStruct *parseTests(const char *fname);

#endif
