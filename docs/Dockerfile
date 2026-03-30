#FROM node:lts
FROM mcr.microsoft.com/devcontainers/javascript-node:22

ENV DEBIAN_FRONTEND=noninteractive
# Install and update the system
RUN apt-get -q update && apt-get -qy upgrade && apt-get -qy install curl postgresql-client golang-go

# Install Rust
RUN curl --proto '=https' --tlsv1.2 https://sh.rustup.rs -sSf | sh -s -- --profile minimal --default-toolchain stable -y
# Enable rust
#RUN export PATH="$HOME/.cargo/bin:$PATH"
# Install mdBook and plugins
RUN $HOME/.cargo/bin/cargo install mdbook \
    mdbook-mermaid \
    mdbook-toc \
    mdbook-katex \
    mdbook-alerts \
    mdbook-toc \
    mdbook-linkcheck

# Install tbls
#RUN source <(curl https://raw.githubusercontent.com/k1LoW/tbls/main/use)
ENV TBLS_VERSION=1.92.3
# detect architecture and download appropriate deb package
RUN ARCH=$(dpkg --print-architecture) curl -o tbls.deb -L https://github.com/k1LoW/tbls/releases/download/v$TBLS_VERSION/tbls_$TBLS_VERSION-1_$(dpkg --print-architecture).deb
RUN dpkg -i tbls.deb

# Install schemalint
RUN npm install -g schemalint 

# Clean up APT when done.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /book
VOLUME /book

ENTRYPOINT ["mdbook"]

LABEL maintainer="PostgSail - https://github.com/xbgmsharp/PostgSail"
LABEL org.opencontainers.image.description="PostgSail - An open source PostgreSQL-based marine vessel tracking and monitoring platform."
LABEL org.opencontainers.image.source="https://github.com/xbgmsharp/PostgSail"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.title="PostgSail Documentation"
LABEL org.opencontainers.image.url="https://github.com/xbgmsharp/PostgSail"
LABEL org.opencontainers.image.vendor="Francois Lacroix"
LABEL org.opencontainers.image.version="latest"
