# Reverse Proxies

PostgSail can run without a reverse proxy.
Hosting PostgSail behind a reverse proxy can help with security, scalability, and flexibility.

Doing so has a few downsides:

- PostgSail does not support HTTPS connections natively (TLS termination must be handled by the proxy).
- PostgREST does not check `HOST` headers — it serves on a port regardless of the hostname used.
  A reverse proxy lets you enforce correct hostname routing.
- PostgREST only supports simple in-memory caching.
  If you need more advanced caching, use a reverse proxy like [Nginx](https://nginx.org/), [Varnish](https://varnish-cache.org/), or [Apache](https://httpd.apache.org/) with custom rules.
- You may need to host multiple services (API, frontend, Grafana) under a single domain or set of subdomains.