# Build stage: compile goose
FROM golang:1.24-alpine AS builder
ENV CGO_ENABLED=0
RUN go install github.com/pressly/goose/v3/cmd/goose@v3.26.0

# Final stage: minimal image with only postgresql-client + goose binary
FROM alpine:3.21
RUN apk add --no-cache postgresql-client curl
COPY --from=builder /go/bin/goose /usr/local/bin/goose

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
