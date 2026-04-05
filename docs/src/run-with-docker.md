# Deploying on a Linux Server

This guide covers provisioning a fresh Linux server and installing Docker before following the [Docker Compose deployment guide](run-with-docker-compose.md).

## Connect to the server

```bash
ssh root@my.server.com
```

## Clone the repository

```bash
git clone https://github.com/xbgmsharp/postgsail
cd postgsail
```

## Install Docker

From [docs.docker.com/engine/install/ubuntu](https://docs.docker.com/engine/install/ubuntu/):

```bash
apt-get update
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Once Docker is installed, follow the **[Docker Compose guide](run-with-docker-compose.md)** for configuration, building images, and starting the stack.
