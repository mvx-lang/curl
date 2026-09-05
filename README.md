# curl — HTTP client for MultiValue BASIC, via libcurl

Provides `HTTPGET(url)` and `HTTPGETFILE(url, path)` by calling **libcurl** from
C. libcurl handles TLS, redirects and binary bodies — the things a raw-socket
client and UniData's native HTTPS (`createSecureRequest`) do not: it will not
reliably reach github, and a release URL 302s to the CDN.

`provides: curl`, so a dependency on `curl` resolves to this package — or to
**curl-cmd**, which offers the same two functions by shelling out to the OS
`curl` command and needs no compiler. Both satisfy the same dependency; this one
needs `libcurl.so.4` and a build, and in exchange never shells out.

| system | binding | built as |
|---|---|---|
| udt | UniData CallC (`CURLGET`/`CURLGETFILE`) | an object folded into `libu2callc.so` |
| jbase | jBASE DEFC (`JBCURLGET`/`JBCURLGETFILE`) | a shared library, `lib/libjbcurl.so` |
| mvx | built into the runtime | — (mvx needs no package) |

## jBASE needs the library preloaded

This is jBASE's behaviour for `DEFC` generally, not something this package does:
**a CATALOGed subroutine cannot resolve a DEFC function unless the library is
forced into the process.** `LD_LIBRARY_PATH` is not enough — the symbol resolves
at load time against the cataloged object, and you get

```
jBASE: /home/you/lib/lib0.so.NNN: undefined symbol: JBCURLGETFILE
```

which names the *other* function, because the loader resolves them all at once.
So a session that calls `HTTPGET` must have:

```sh
LD_PRELOAD=<account>/lib/libjbcurl.so
```

Reproduced with five lines of C and no package at all — see mv_git#114, which
documents the same constraint for the git engine.

## The jBASE binding returns the status

`DEFC` declares a function, and an argument VAR written by the C side is visible
to the caller — so the body comes back through an **argument** and the return
value carries the HTTP status:

```basic
DEFC VAR JBCURLGET(VAR, VAR)
ST = JBCURLGET(URL, RESP)      ;* ST = 200, RESP = the body
```

UniData's CallC cannot do that: it marshals a `char *` and nothing else, so
`CURLGET` has to answer the body itself and the status is lost — a 404 and an
empty 200 are the same empty string there. Both arms agree on the contract the
BASIC wrappers present (`HTTPGET` -> body on 2xx else `""`), but jBASE keeps the
status underneath it.
