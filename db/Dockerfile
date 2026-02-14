FROM mcr.microsoft.com/devcontainers/go:1.24

RUN apt-get update && apt-get install -y postgresql-client && rm -rf /var/lib/apt/lists/*

#COPY --from=builder /build/goose /usr/local/bin/goose
RUN go install github.com/pressly/goose/v3/cmd/goose@latest
RUN cp $GOPATH/bin/goose /usr/local/bin/goose
RUN chmod +x /usr/local/bin/goose

WORKDIR /db
ENTRYPOINT ["goose"]