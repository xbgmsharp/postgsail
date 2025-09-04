#FROM node:lts
FROM mcr.microsoft.com/devcontainers/javascript-node:22

ENV DEBIAN_FRONTEND=noninteractive
# Install and update the system
RUN apt-get -q update && apt-get -qy upgrade && apt-get -qy install postgresql-client
# Clean up APT when done.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
