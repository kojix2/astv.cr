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

FROM alpine:3.20

WORKDIR /app

RUN apk add --no-cache \
    libgcc \
    libstdc++ \
    libssl3 \
    zlib \
    pcre2 \
    && adduser -D -H app

COPY --from=crystal-builder /app/bin/astv /app/astv
COPY --from=crystal-builder /app/src/views /app/src/views

RUN chown -R app:app /app

USER app

ENV PORT=3000
ENV KEMAL_ENV=production
EXPOSE 3000

CMD ["/app/astv"]
