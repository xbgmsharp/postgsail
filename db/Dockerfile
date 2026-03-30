FROM mcr.microsoft.com/devcontainers/go:1.24

RUN apt-get update && apt-get install --no-install-recommends -y postgresql-client && rm -rf /var/lib/apt/lists/*

#COPY --from=builder /build/goose /usr/local/bin/goose
#RUN go install github.com/pressly/goose/v3/cmd/goose@latest
RUN go install github.com/pressly/goose/v3/cmd/goose@v3.26.0
RUN cp $GOPATH/bin/goose /usr/local/bin/goose
RUN chmod +x /usr/local/bin/goose

WORKDIR /db
ENTRYPOINT ["goose"]

LABEL maintainer="PostgSail - https://github.com/xbgmsharp/PostgSail"
LABEL org.opencontainers.image.description="PostgSail - An open source PostgreSQL-based marine vessel tracking and monitoring platform."
LABEL org.opencontainers.image.source="https://github.com/xbgmsharp/PostgSail"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.title="PostgSail Goose database migrator"
LABEL org.opencontainers.image.url="https://github.com/xbgmsharp/PostgSail"
LABEL org.opencontainers.image.vendor="Francois Lacroix"
LABEL org.opencontainers.image.version="latest"
