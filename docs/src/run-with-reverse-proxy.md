# Reverse Proxies

PostgSail can run without a reverse proxy.
Hosting PostgSail behind a reverse proxy can help with security, scalability, and flexibility.

Doing so has a few downsides:

- PostgSail does not support HTTPS connections (TLS termination).
- We do not check `HOST`-headers - we just serve on a port.
  This means anybody can point their dns record to your server and serve to all requests going to the port Martin is running on.
  Using a reverse proxy makes this abuse obvious.
- Martin only supports a simple in-memory caching.
  If you need more advanced caching options, you can use a reverse proxy like [Nginx](https://nginx.org/), [Varnish](https://varnish-cache.org/), or [Apache](https://httpd.apache.org/) with custom rules.
  For example, you may choose to only cache zoom 0..10.
- You may need to host more than just tiles at a single domain name.