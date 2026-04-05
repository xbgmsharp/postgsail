## Using with NGINX

You should run PostgSail behind an NGINX reverse proxy to enable HTTPS and serve multiple services from a single domain. Here is an example configuration that proxies the PostgSail API, web frontend, and Grafana dashboard.

### Example: Subdomain-based routing

The following `nginx.conf` example routes traffic for three subdomains:
- `api.example.com` → PostgREST API (port 3000)
- `web.example.com` → Vue 3 frontend (port 8080)
- `app.example.com` → Grafana (port 3001)

```nginx
server {
    listen 443 ssl;
    server_name api.example.com;

    ssl_certificate     /etc/ssl/certs/api.example.com.crt;
    ssl_certificate_key /etc/ssl/private/api.example.com.key;

    location / {
        proxy_pass         http://localhost:3000/;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }
}

server {
    listen 443 ssl;
    server_name web.example.com;

    ssl_certificate     /etc/ssl/certs/web.example.com.crt;
    ssl_certificate_key /etc/ssl/private/web.example.com.key;

    location / {
        proxy_pass         http://localhost:8080/;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }
}

server {
    listen 443 ssl;
    server_name app.example.com;

    ssl_certificate     /etc/ssl/certs/app.example.com.crt;
    ssl_certificate_key /etc/ssl/private/app.example.com.key;

    location / {
        proxy_pass         http://localhost:3001/;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }
}
```

### HTTP to HTTPS redirect

Add this block for each domain to redirect HTTP traffic to HTTPS:

```nginx
server {
    listen 80;
    server_name api.example.com web.example.com app.example.com;
    return 301 https://$host$request_uri;
}
```

### Apply and reload

```bash
sudo nginx -t          # Test configuration
sudo systemctl reload nginx
```

### With Docker Compose

Add NGINX as a service in your `docker-compose.yml`:

```yml
services:
  nginx:
    image: nginx:alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./certs:/etc/ssl:ro
    depends_on:
      - api
      - web
      - app
```

For automated TLS certificate management, see [Certbot](https://certbot.eff.org/) or use the [Kubernetes deployment](run-with-kubernetes.md) with cert-manager.
