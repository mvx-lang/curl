/*
 * curl — HTTP client for MultiValue BASIC via libcurl.
 * Copyright (C) 2026 Gordon Heydon.  SPDX-License-Identifier: GPL-2.0-only
 *
 * One libcurl core, three bindings:
 *   MVX   — the mvx_ext ABI (HTTPGET/HTTPGETFILE), built into LIB/.
 *   udt   — UniData CallC (CURLGET/CURLGETFILE), folded into libu2callc.so
 *           (compile with -DMVXCURL_UDT); the BASIC HTTPGET/HTTPGETFILE verbs
 *           CALLC these.
 *   jbase — jBASE DEFC (JBCURLGET/JBCURLGETFILE) in a shared library
 *           (-DMVXCURL_JBASE -shared); the BASIC verbs DEFC these.
 *
 * libcurl handles TLS (HTTPS), redirects (a github release URL 302s to the CDN),
 * and binary bodies — the things UniData's native HTTP client and a raw-socket
 * client do not.  HTTPGET(url) -> body on a 2xx status, else ""; HTTPGETFILE(
 * url, path) -> the HTTP status (-1 transport error, -2 cannot open path).
 */
#include <curl/curl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { char *p; size_t len, cap; } cbuf;

static size_t cbuf_cb(char *ptr, size_t sz, size_t nm, void *ud) {
    cbuf *b = ud;
    size_t n = sz * nm;
    if (b->len + n + 1 > b->cap) {
        size_t c = b->cap ? b->cap : 8192;
        while (c < b->len + n + 1) c *= 2;
        char *np = realloc(b->p, c);
        if (!np) return 0;                 /* signals write error to libcurl */
        b->p = np; b->cap = c;
    }
    memcpy(b->p + b->len, ptr, n);
    b->len += n;
    b->p[b->len] = '\0';
    return n;
}

static void curl_common(CURL *c, const char *url) {
    curl_easy_setopt(c, CURLOPT_URL, url);
    curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);   /* github 302 -> CDN */
    curl_easy_setopt(c, CURLOPT_MAXREDIRS, 10L);
    curl_easy_setopt(c, CURLOPT_USERAGENT, "mvpkg-curl/1.1");
}

/* GET url; body into *out (NUL-terminated, caller frees), *outlen its length.
   Returns the HTTP status, or -1 on a transport error. */
static long http_get_buf(const char *url, char **out, size_t *outlen) {
    *out = NULL; *outlen = 0;
    CURL *c = curl_easy_init();
    if (!c) return -1;
    cbuf b = {0, 0, 0};
    curl_common(c, url);
    curl_easy_setopt(c, CURLOPT_TIMEOUT, 120L);
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, cbuf_cb);
    curl_easy_setopt(c, CURLOPT_WRITEDATA, &b);
    CURLcode rc = curl_easy_perform(c);
    long code = 0;
    curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &code);
    curl_easy_cleanup(c);
    if (rc != CURLE_OK) { free(b.p); return -1; }
    *out = b.p; *outlen = b.len;
    return code;
}

/* GET url -> path (binary-safe, libcurl writes the body straight to the file).
   Returns the HTTP status, -1 on a transport error, -2 if path can't be opened. */
static long http_get_file(const char *url, const char *path) {
    FILE *f = fopen(path, "wb");
    if (!f) return -2;
    CURL *c = curl_easy_init();
    if (!c) { fclose(f); return -1; }
    curl_common(c, url);
    curl_easy_setopt(c, CURLOPT_TIMEOUT, 600L);
    curl_easy_setopt(c, CURLOPT_WRITEDATA, f);         /* default fwrite callback */
    CURLcode rc = curl_easy_perform(c);
    long code = 0;
    curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &code);
    curl_easy_cleanup(c);
    fclose(f);
    return rc == CURLE_OK ? code : -1;
}

#ifdef MVXCURL_UDT
/* ---- UniData CallC binding -----------------------------------------------
   CallC marshals string arguments and the return value with strlen, so return
   NUL-terminated buffers.  CURLGET holds the last body in a static (freed on the
   next call); CURLGETFILE returns the status as a string. */
static char *g_body = NULL;

char *CURLGET(char *url) {
    free(g_body); g_body = NULL;
    size_t n = 0;
    long code = http_get_buf(url, &g_body, &n);
    if (code < 200 || code >= 300) { free(g_body); g_body = NULL; return ""; }
    return g_body ? g_body : "";
}

char *CURLGETFILE(char *url, char *path) {
    static char code[24];
    snprintf(code, sizeof code, "%ld", http_get_file(url, path));
    return code;
}
#elif defined(MVXCURL_JBASE)
/* ---- jBASE DEFC binding ---------------------------------------------------
   jBASE reaches C with DEFC, which declares a FUNCTION rather than a subroutine
   and hands it the session:

       DEFC VAR JBCURLGET(VAR, VAR)
       ST = JBCURLGET(URL, BODY)

   An argument VAR written by the C side IS visible to the caller, so the body
   travels back through an ARGUMENT and the return value carries the HTTP status.
   That is better than the CallC arm above can manage: CallC marshals a char* and
   nothing else, so CURLGET has to answer the body itself and the status is lost
   -- a 404 and an empty 200 are the same empty string there.  Here they are not.

   The entry points are named JBCURL* rather than CURL* so the BASIC wrappers can
   keep the names HTTPGET/HTTPGETFILE that every caller already uses: DEFC
   declares a function, and a function cannot share a name with the BASIC
   FUNCTION that calls it. */
#include <jsystem.h>

/* jBASE passes the session as a leading DPSTRUCT* when its headers say so. */
#ifdef DPSTRUCT_DEF
#define JBASEDP DPSTRUCT *dp,
#else
#define JBASEDP
#endif

/* A VAR's bytes as a C string, and the reverse.  Both take `dp` BY THAT NAME:
   CONV_SFB and STORE_VBC are macros that expand to calls passing `dp`
   implicitly, so a helper whose parameter is called anything else does not
   compile -- and the error points into jsystem.h rather than at the helper. */
static const char *jb_sfb(DPSTRUCT *dp, VAR *v) {
    char *p = v ? (char *)CONV_SFB(v) : NULL;
    return p ? p : "";
}

VAR *JBCURLGET(VAR *Result, JBASEDP VAR *A0, VAR *Out) {
    char *body = NULL;
    size_t n = 0;
    long code = http_get_buf(jb_sfb(dp, A0), &body, &n);
    /* Same contract as every other arm: a body only on 2xx, "" otherwise -- so a
       404's error page never reads as content.  The status is the return value,
       which is the part the other arms cannot give back. */
    if (code < 200 || code >= 300) { free(body); body = NULL; }
    STORE_VBC(Out, body ? body : "");
    free(body);
    STORE_VBI(Result, code);
    return Result;
}

VAR *JBCURLGETFILE(VAR *Result, JBASEDP VAR *A0, VAR *A1) {
    long code = http_get_file(jb_sfb(dp, A0), jb_sfb(dp, A1));
    STORE_VBI(Result, code);
    return Result;
}

#else
/* ---- MVX mvx_ext binding -------------------------------------------------- */
#include "mvx_ext.h"

static int64_t arg_str(mv_value *v, char *dst, size_t cap) {
    char nb[40];
    const char *p;
    int64_t n = mv_val_chars(v, nb, sizeof nb, &p);
    if (n >= (int64_t)cap) n = (int64_t)cap - 1;
    memcpy(dst, p, (size_t)n);
    dst[n] = '\0';
    return n;
}

static void ext_httpget(mvx_ctx *ctx, mv_value *ret, int32_t argc, mv_value **argv) {
    (void)ctx; (void)argc;
    char url[2048];
    arg_str(argv[0], url, sizeof url);
    char *body; size_t blen;
    long code = http_get_buf(url, &body, &blen);
    if (code >= 200 && code < 300 && body) mv_set_str(ret, body, (int64_t)blen);
    else mv_set_str(ret, "", 0);
    free(body);
}

static void ext_httpgetfile(mvx_ctx *ctx, mv_value *ret, int32_t argc, mv_value **argv) {
    (void)ctx; (void)argc;
    char url[2048], path[2048], num[24];
    arg_str(argv[0], url, sizeof url);
    arg_str(argv[1], path, sizeof path);
    snprintf(num, sizeof num, "%ld", http_get_file(url, path));
    mv_set_str(ret, num, (int64_t)strlen(num));
}

static const mvx_extfn curl_fns[] = {
    {"HTTPGET", 1, 1, ext_httpget},
    {"HTTPGETFILE", 2, 2, ext_httpgetfile},
};
static const mvx_ext curl_ext = {"curl", 2, curl_fns};

const mvx_ext *mvx_ext_entry(int abi) {
    return abi == MVX_EXT_ABI ? &curl_ext : NULL;
}
#endif
