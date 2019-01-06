class Ndisc6 < Formula
  desc "Small collection of useful tools for IPv6 networking"
  homepage "https://www.remlab.net/ndisc6/"
  url "https://www.remlab.net/files/ndisc6/ndisc6-1.0.4.tar.bz2"
  sha256 "abb1da4a98d94e5abe1dd7b1c975de540306b0581cbbd36aff035118b2f25c1f"

  # Patches needed to fix compilation errors on macOS.
  patch :DATA

  def install
    system "./configure", "--disable-dependency-tracking",
                          "--disable-silent-rules",
                          "--prefix=#{prefix}"
    system "make", "install"
  end

  test do
    system "#{bin}/addr2name", "--version"
    system "#{bin}/name2addr", "--version"
    system "#{bin}/ndisc6", "--version"
    system "#{bin}/rdisc6", "--version"
    system "#{bin}/rltraceroute6", "--version"
    system "#{bin}/tcpspray", "--version"
    system "#{bin}/tcpspray6", "--version"
    system "#{bin}/tcptraceroute6", "--version"
    system "#{bin}/tracert6", "--version"
    system "#{sbin}/rdnssd", "--version"
  end
end

__END__
diff --new-file --exclude='*~' --recursive --unified ndisc6-1.0.4-orig/rdnss/rdnssd.c ndisc6-1.0.4-patched/rdnss/rdnssd.c
--- ndisc6-1.0.4-orig/rdnss/rdnssd.c	2016-12-07 11:00:02.000000000 -0800
+++ ndisc6-1.0.4-patched/rdnss/rdnssd.c	2019-01-06 14:14:41.000000000 -0800
@@ -694,7 +694,7 @@
 		 && (lockf (fd, F_TLOCK, 0) == 0)
 		 && (ftruncate (fd, 0) == 0)
 		 && (write (fd, buf, len) == (ssize_t)len)
-		 && (fdatasync (fd) == 0))
+		 && (fsync (fd) == 0))
 			return fd;
 
 		if (errno == 0) /* !S_ISREG */
diff --new-file --exclude='*~' --recursive --unified ndisc6-1.0.4-orig/rdnss/rdnssd.h ndisc6-1.0.4-patched/rdnss/rdnssd.h
--- ndisc6-1.0.4-orig/rdnss/rdnssd.h	2016-12-07 10:11:55.000000000 -0800
+++ ndisc6-1.0.4-patched/rdnss/rdnssd.h	2019-01-06 14:14:54.000000000 -0800
@@ -32,24 +32,6 @@
 #define ND_OPT_RDNSS 25
 #define ND_OPT_DNSSL 31
 
-struct nd_opt_rdnss
-{
-	uint8_t nd_opt_rdnss_type;
-	uint8_t nd_opt_rdnss_len;
-	uint16_t nd_opt_rdnss_reserved;
-	uint32_t nd_opt_rdnss_lifetime;
-	/* followed by one or more IPv6 addresses */
-};
-
-struct nd_opt_dnssl
-{
-	uint8_t nd_opt_dnssl_type;
-	uint8_t nd_opt_dnssl_len;
-	uint16_t nd_opt_dnssl_reserved;
-	uint32_t nd_opt_dnssl_lifetime;
-	/* followed by one or more domain names */
-};
-
 # ifdef __cplusplus
 extern "C" {
 # endif
diff --new-file --exclude='*~' --recursive --unified ndisc6-1.0.4-orig/src/gettime.h ndisc6-1.0.4-patched/src/gettime.h
--- ndisc6-1.0.4-orig/src/gettime.h	2016-12-07 11:34:33.000000000 -0800
+++ ndisc6-1.0.4-patched/src/gettime.h	2019-01-06 14:13:31.000000000 -0800
@@ -20,6 +20,8 @@
 #include <unistd.h>
 #include <errno.h>
 
+#include "timing_mach.h"
+
 static inline int mono_gettime (struct timespec *ts)
 {
 	int rc;
@@ -48,7 +50,7 @@
 	if (rc == EINVAL)
 #endif
 #if (_POSIX_MONOTONIC_CLOCK <= 0)
-		rc = clock_nanosleep (CLOCK_REALTIME, 0, ts, NULL);
+		rc = clock_nanosleep_abstime (ts);
 #endif
 	return rc;
 }
diff --new-file --exclude='*~' --recursive --unified ndisc6-1.0.4-orig/src/timing_mach.c ndisc6-1.0.4-patched/src/timing_mach.c
--- ndisc6-1.0.4-orig/src/timing_mach.c	1969-12-31 16:00:00.000000000 -0800
+++ ndisc6-1.0.4-patched/src/timing_mach.c	2019-01-06 14:10:55.000000000 -0800
@@ -0,0 +1,146 @@
+/* Source: https://github.com/ChisholmKyle/PosixMachTiming
+ *
+ * Copyright (c) 2015, Kyle Chisholm <>
+ *
+ * Permission to use, copy, modify, and/or distribute this software
+ * for any purpose with or without fee is hereby granted, provided
+ * that the above copyright notice and this permission notice appear
+ * in all copies.
+ *
+ * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
+ * WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
+ * WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
+ * AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR
+ * CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
+ * OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
+ * NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
+ * CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
+*/
+
+#define _POSIX_C_SOURCE 200809L
+#include <unistd.h>
+
+#include <time.h>
+
+#if RO_MACH_BEFORE_10_12
+/* ******** */
+/* __MACH__ */
+
+#include <mach/mach_time.h>
+#include <mach/mach.h>
+#include <mach/clock.h>
+
+/* __MACH__ */
+/* ******** */
+#endif
+
+#include "timing_mach.h"
+
+extern double timespec2secd(const struct timespec *ts_in);
+extern void secd2timespec(struct timespec *ts_out, const double sec_d);
+extern void timespec_monodiff_lmr(struct timespec *ts_out,
+                                  const struct timespec *ts_in);
+extern void timespec_monodiff_rml(struct timespec *ts_out,
+                                  const struct timespec *ts_in);
+extern void timespec_monoadd(struct timespec *ts_out,
+                             const struct timespec *ts_in);
+
+#ifdef __MACH__
+/* ******** */
+/* __MACH__ */
+
+    /* clock_nanosleep for CLOCK_MONOTONIC and TIMER_ABSTIME */
+    extern int clock_nanosleep_abstime (const struct timespec *req);
+
+/* __MACH__ */
+/* ******** */
+#endif
+
+
+#if RO_MACH_BEFORE_10_12
+/* ******** */
+/* __MACH__ */
+
+    /* timing struct for osx */
+    typedef struct RoTimingMach {
+        mach_timebase_info_data_t timebase;
+        clock_serv_t cclock;
+    } RoTimingMach;
+
+    /* internal timing struct for osx */
+    static RoTimingMach ro_timing_mach_g;
+
+    /* mach clock port */
+    extern mach_port_t clock_port;
+
+    /* emulate posix clock_gettime */
+    int clock_gettime (clockid_t id, struct timespec *tspec)
+    {
+        int retval = -1;
+        mach_timespec_t mts;
+        if (id == CLOCK_REALTIME) {
+            retval = clock_get_time (ro_timing_mach_g.cclock, &mts);
+            if (retval == 0) {
+                tspec->tv_sec = mts.tv_sec;
+                tspec->tv_nsec = mts.tv_nsec;
+            }
+        } else if (id == CLOCK_MONOTONIC) {
+            retval = clock_get_time (clock_port, &mts);
+            if (retval == 0) {
+                tspec->tv_sec = mts.tv_sec;
+                tspec->tv_nsec = mts.tv_nsec;
+            }
+        } else {}
+        return retval;
+    }
+
+    /* emulate posix clock_getres */
+    int clock_getres (clockid_t id, struct timespec *res)
+    {
+
+        (void)id;
+        res->tv_sec = 0;
+        res->tv_nsec = ro_timing_mach_g.timebase.numer / ro_timing_mach_g.timebase.denom;
+        return 0;
+
+    }
+
+    /* initialize */
+    int timing_mach_init (void) {
+        static int call_count = 0;
+        call_count++;
+        int retval = -2;
+        if (call_count == 1) {
+            retval = mach_timebase_info (&ro_timing_mach_g.timebase);
+            if (retval == 0) {
+                retval = host_get_clock_service (mach_host_self (),
+                                                 CALENDAR_CLOCK, &ro_timing_mach_g.cclock);
+            }
+        } else {
+            /* don't overflow, reset call count */
+            call_count = 1;
+        }
+        return retval;
+    }
+
+/* __MACH__ */
+/* ******** */
+#endif
+
+int itimer_start (struct timespec *ts_target, const struct timespec *ts_step) {
+    int retval = clock_gettime(CLOCK_MONOTONIC, ts_target);
+    if (retval == 0) {
+        /* add step size to current monotonic time */
+        timespec_monoadd(ts_target, ts_step);
+    }
+    return retval;
+}
+
+int itimer_step (struct timespec *ts_target, const struct timespec *ts_step) {
+    int retval = clock_nanosleep_abstime(ts_target);
+    if (retval == 0) {
+        /* move target along */
+        timespec_monoadd(ts_target, ts_step);
+    }
+    return retval;
+}
diff --new-file --exclude='*~' --recursive --unified ndisc6-1.0.4-orig/src/timing_mach.h ndisc6-1.0.4-patched/src/timing_mach.h
--- ndisc6-1.0.4-orig/src/timing_mach.h	1969-12-31 16:00:00.000000000 -0800
+++ ndisc6-1.0.4-patched/src/timing_mach.h	2019-01-06 14:10:55.000000000 -0800
@@ -0,0 +1,186 @@
+/* Source: https://github.com/ChisholmKyle/PosixMachTiming
+ *
+ * Copyright (c) 2015, Kyle Chisholm <>
+ *
+ * Permission to use, copy, modify, and/or distribute this software
+ * for any purpose with or without fee is hereby granted, provided
+ * that the above copyright notice and this permission notice appear
+ * in all copies.
+ *
+ * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
+ * WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
+ * WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
+ * AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR
+ * CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
+ * OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
+ * NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
+ * CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
+*/
+
+#ifndef TIMING_MACH_H
+#define TIMING_MACH_H
+/* ************* */
+/* TIMING_MACH_H */
+
+#include <time.h>
+
+/* OSX before 10.12 (MacOS Sierra) */
+#define TIMING_MACH_BEFORE_10_12 (__MACH__ && __MAC_OS_X_VERSION_MIN_REQUIRED < 101200)
+
+/* scale factors */
+#define TIMING_GIGA (1000000000)
+#define TIMING_NANO (1e-9)
+
+/*  Before OSX 10.12, the following are emulated here:
+        CLOCK_REALTIME
+        CLOCK_MONOTONIC
+        clockid_t
+        clock_gettime
+        clock_getres
+*/
+#if (TIMING_MACH_BEFORE_10_12)
+/* **** */
+/* MACH */
+
+    /* clockid_t - emulate POSIX */
+    typedef int clockid_t;
+
+    /* CLOCK_REALTIME - emulate POSIX */
+    #ifndef CLOCK_REALTIME
+    # define CLOCK_REALTIME 0
+    #endif
+
+    /* CLOCK_MONOTONIC - emulate POSIX */
+    #ifndef CLOCK_MONOTONIC
+    # define CLOCK_MONOTONIC 1
+    #endif
+
+    /* clock_gettime - emulate POSIX */
+    int clock_gettime ( const clockid_t id, struct timespec *tspec );
+
+    /* clock_getres - emulate POSIX */
+    int clock_getres (clockid_t id, struct timespec *res);
+
+    /* initialize timing */
+    int timing_mach_init (void);
+
+/* MACH */
+/* **** */
+#else
+
+    /* initialize mach timing is a no-op */
+    #define timing_mach_init() 0
+
+#endif
+
+/* timespec to double */
+inline double timespec2secd(const struct timespec *ts_in) {
+    return ((double) ts_in->tv_sec) + ((double) ts_in->tv_nsec ) * TIMING_NANO;
+}
+
+/* double sec to timespec */
+inline void secd2timespec(struct timespec *ts_out, const double sec_d) {
+    ts_out->tv_sec = (time_t) (sec_d);
+    ts_out->tv_nsec = (long) ((sec_d - (double) ts_out->tv_sec) * TIMING_GIGA);
+}
+
+/* timespec difference (monotonic) left - right */
+inline void timespec_monodiff_lmr(struct timespec *ts_out,
+                                    const struct timespec *ts_in) {
+    /* out = out - in,
+       where out > in
+     */
+    ts_out->tv_sec = ts_out->tv_sec - ts_in->tv_sec;
+    ts_out->tv_nsec = ts_out->tv_nsec - ts_in->tv_nsec;
+    if (ts_out->tv_sec < 0) {
+        ts_out->tv_sec = 0;
+        ts_out->tv_nsec = 0;
+    } else if (ts_out->tv_nsec < 0) {
+        if (ts_out->tv_sec == 0) {
+            ts_out->tv_sec = 0;
+            ts_out->tv_nsec = 0;
+        } else {
+            ts_out->tv_sec = ts_out->tv_sec - 1;
+            ts_out->tv_nsec = ts_out->tv_nsec + TIMING_GIGA;
+        }
+    } else {}
+}
+
+/* timespec difference (monotonic) right - left */
+inline void timespec_monodiff_rml(struct timespec *ts_out,
+                                    const struct timespec *ts_in) {
+    /* out = in - out,
+       where in > out
+     */
+    ts_out->tv_sec = ts_in->tv_sec - ts_out->tv_sec;
+    ts_out->tv_nsec = ts_in->tv_nsec - ts_out->tv_nsec;
+    if (ts_out->tv_sec < 0) {
+        ts_out->tv_sec = 0;
+        ts_out->tv_nsec = 0;
+    } else if (ts_out->tv_nsec < 0) {
+        if (ts_out->tv_sec == 0) {
+            ts_out->tv_sec = 0;
+            ts_out->tv_nsec = 0;
+        } else {
+            ts_out->tv_sec = ts_out->tv_sec - 1;
+            ts_out->tv_nsec = ts_out->tv_nsec + TIMING_GIGA;
+        }
+    } else {}
+}
+
+/* timespec addition (monotonic) */
+inline void timespec_monoadd(struct timespec *ts_out,
+                             const struct timespec *ts_in) {
+    /* out = in + out */
+    ts_out->tv_sec = ts_out->tv_sec + ts_in->tv_sec;
+    ts_out->tv_nsec = ts_out->tv_nsec + ts_in->tv_nsec;
+    if (ts_out->tv_nsec >= TIMING_GIGA) {
+        ts_out->tv_sec = ts_out->tv_sec + 1;
+        ts_out->tv_nsec = ts_out->tv_nsec - TIMING_GIGA;
+    }
+}
+
+#ifdef __MACH__
+/* **** */
+/* MACH */
+
+    /* emulate clock_nanosleep for CLOCK_MONOTONIC and TIMER_ABSTIME */
+    inline int clock_nanosleep_abstime ( const struct timespec *req )
+    {
+        struct timespec ts_delta;
+        int retval = clock_gettime ( CLOCK_MONOTONIC, &ts_delta );
+        if (retval == 0) {
+            timespec_monodiff_rml ( &ts_delta, req );
+            retval = nanosleep ( &ts_delta, NULL );
+        }
+        return retval;
+    }
+
+/* MACH */
+/* **** */
+#else
+/* ***** */
+/* POSIX */
+
+    /* clock_nanosleep for CLOCK_MONOTONIC and TIMER_ABSTIME */
+    #define clock_nanosleep_abstime( req ) \
+        clock_nanosleep ( CLOCK_MONOTONIC, TIMER_ABSTIME, (req), NULL )
+
+/* POSIX */
+/* ***** */
+#endif
+
+/* timer functions that make use of clock_nanosleep_abstime
+   For POSIX systems, it is recommended to use POSIX timers and signals.
+   For Mac OSX (mach), there are no POSIX timers so these functions are very helpful.
+*/
+
+/* Sets absolute time ts_target to ts_step after current time */
+int itimer_start (struct timespec *ts_target, const struct timespec *ts_step);
+
+/* Nanosleeps to ts_target then adds ts_step to ts_target for next iteration */
+int itimer_step (struct timespec *ts_target, const struct timespec *ts_step);
+
+/* TIMING_MACH_H */
+/* ************* */
+#endif
