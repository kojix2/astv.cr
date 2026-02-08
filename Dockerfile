FROM crystallang/crystal:1-alpine AS crystal-builder

WORKDIR /app

RUN apk add --no-cache --virtual .build-deps \
    gcc \
    g++ \
    make \
    libc-dev \
    openssl-dev \
    zlib-dev \
    pcre2-dev

COPY shard.yml shard.lock ./
RUN shards install --production

COPY src ./src
COPY src/views ./src/views

RUN shards build --release --no-debug -s

FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false update \
    && apt-get install -y --no-install-recommends \
    libgc1 \
    libssl3 \
    zlib1g \
    libpcre2-8-0 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /usr/sbin/nologin app

COPY --from=crystal-builder /app/bin/astv /app/astv
COPY --from=crystal-builder /app/src/views /app/src/views

RUN chown -R app:app /app

USER app

ENV PORT=3000
ENV KEMAL_ENV=production
EXPOSE 3000

CMD ["/app/astv"]
