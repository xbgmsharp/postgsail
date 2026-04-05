## Using with Apache

You should run PostgSail behind an Apache reverse proxy to enable HTTPS, apply rate-limiting per IP, and serve multiple services from a single domain.

First you have to set up a virtual host working on port 443.

### Enable necessary modules

```bash
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2enmod headers
sudo a2enmod rewrite
sudo a2enmod ratelimit
```

### Example: Subdomain-based routing

The following example routes three subdomains to PostgSail services. Create one VirtualHost block per subdomain:

**API (`api.example.com` → PostgREST port 3000):**

```apache
<VirtualHost *:443>
    ServerName api.example.com
    ServerAdmin webmaster@localhost
    ProxyPreserveHost On

    <IfModule mod_headers.c>
        RequestHeader set X-Forwarded-Proto "https"
    </IfModule>

    # Rate-limit to 100 requests/second per IP
    <Location "/">
        SetOutputFilter RATE_LIMIT
        SetEnv rate-limit 100
    </Location>

    ProxyPass / http://localhost:3000/
    ProxyPassReverse / http://localhost:3000/
</VirtualHost>
```

**Web frontend (`web.example.com` → Vue 3 port 8080):**

```apache
<VirtualHost *:443>
    ServerName web.example.com
    ServerAdmin webmaster@localhost
    ProxyPreserveHost On

    <IfModule mod_headers.c>
        RequestHeader set X-Forwarded-Proto "https"
    </IfModule>

    ProxyPass / http://localhost:8080/
    ProxyPassReverse / http://localhost:8080/
</VirtualHost>
```

**Grafana (`app.example.com` → Grafana port 3001):**

```apache
<VirtualHost *:443>
    ServerName app.example.com
    ServerAdmin webmaster@localhost
    ProxyPreserveHost On

    <IfModule mod_headers.c>
        RequestHeader set X-Forwarded-Proto "https"
    </IfModule>

    ProxyPass / http://localhost:3001/
    ProxyPassReverse / http://localhost:3001/
</VirtualHost>
```

### HTTP to HTTPS redirect

Add this for each domain to redirect plain HTTP:

```apache
<VirtualHost *:80>
    ServerName api.example.com
    Redirect permanent / https://api.example.com/
</VirtualHost>
```

### Check and restart

```bash
sudo apache2ctl configtest
sudo systemctl restart apache2
```
