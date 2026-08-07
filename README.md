# curl — HTTP client for UniData (curl seam)

Provides `HTTPGET(url)` and `HTTPGETFILE(url, path)` for UniData by shelling out
to `curl`. It is the udt HTTP transport the package manager (mvpkg) uses to fetch
packages: UniData's native HTTPS (`createSecureRequest`) doesn't reliably reach
github or follow redirects, and curl handles TLS, redirects, and binary bodies
correctly. `curl` must be on the host (mvpkg's `install.sh` preflights it).

`provides: http`, so a dependency on `http` resolves to this package on udt
(the native `http` extension serves mvx).
