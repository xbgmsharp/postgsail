
## Connect to the server
```bash
% ssh root@my.server.com
```

# Clone the git repo
```bash
% git clone https://github.com/xbgmsharp/postgsail
Cloning into 'postgsail'...
...
```

## Edit the configuration
```bash
% cd postgsail
% cp .env.example .env
% cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w 42 | head -n 1
..
% nano .env
```

## Install Docker
From https://docs.docker.com/engine/install/ubuntu/
```bash
% apt-get update
...
% apt-get install -y ca-certificates curl
...
% install -m 0755 -d /etc/apt/keyrings
% curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
% chmod a+r /etc/apt/keyrings/docker.asc
% echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
% apt-get update
...
% apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
...
```

## Init the database
```bash
% docker compose up db
...
Gracefully stopping... (press Ctrl+C again to force)
[+] Stopping 1/1
 ✔ Container db  Stopped
```

## Start the db with the api
```bash
% docker compose pull api
...
% docker compose up -d db api
```

## Checks
Making sure it works.
```bash
% telnet localhost 5432
...
telnet> quit
Connection closed.
% curl localhost:3000
...
% docker ps
...
% docker logs api
...
```

# Run the web instance
```bash
% docker compose -f docker-compose.yml -f docker-compose.dev.yml build web (be patient)
...

% docker compose -f docker-compose.yml -f docker-compose.dev.yml up web (be patient)
...
web | 
web  |   ➜  Local:   http://localhost:8080/
web  |   ➜  Network: http://172.18.0.4:8080/
```