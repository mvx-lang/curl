# curl — HTTP client for MultiValue BASIC, via libcurl

Provides `HTTPGET(url)`, `HTTPGETFILE(url, path)` and
`HTTPPOST(url, ctype, body, respfile)` by calling **libcurl** from C. libcurl
handles TLS, redirects and binary bodies — the things a raw-socket client and
UniData's native HTTPS (`createSecureRequest`) do not: it will not reliably
reach github, and a release URL 302s to the CDN.

`provides: curl`, so a dependency on `curl` resolves to this package — or to
**curl-cmd**, which offers the same three functions by shelling out to the OS
`curl` command and needs no compiler. Both satisfy the same dependency; this one
needs `libcurl.so.4` and a build, and in exchange never shells out.

| system | binding | built as |
|---|---|---|
| udt | UniData CallC (`CURLGET`, `CURLGETFILE`, `CURLPOST`) | an object folded into `libu2callc.so` |
| jbase | jBASE DEFC (`JBCURLGET`, `JBCURLGETFILE`, `JBCURLPOST`) | a shared library, `lib/libjbcurl.so` |
| mvx | a native extension (`mvx_ext.h`) | a shared library, `LIB/libmvxext_curl.so` |

## On mvx it replaces a package that is already there

mvx ships its own `http` extension, and it exports the same three names with the
same arities. It is plain HTTP/1.1 over POSIX sockets — no TLS, and no external
dependency, which is the point of it: it builds and loads everywhere the runtime
does. Its own source says it is superseded where TLS is needed.

That is what this package is for on mvx. Nothing refuses the pair, though:
`install-pkgs.sh` concatenates each package's `EXPORTS` into the aggregate the
compiler reads, with no check for a name appearing twice. Install both and the
aggregate declares `HTTPGET` twice — and `mvx-basic` compiles a program against
that without a word, which is measured rather than supposed. Which of the two
libraries then answers is not documented anywhere, and a caller has no way to
ask for one.

That is why `tests/https-smoke.sh` deletes `libmvxext_http.*` from its copy of
the system account instead of trusting resolution order: a request answered by
the plain-HTTP client is not a test of this one.

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
