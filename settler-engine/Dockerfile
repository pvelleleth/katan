# Build
FROM crystallang/crystal:1.18 AS builder

RUN apt-get update \
	&& apt-get install -y --no-install-recommends libpq-dev \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY shard.yml shard.lock ./
RUN shards install --production

COPY . .
RUN shards build --release --no-debug

# Run
FROM debian:bookworm-slim

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		libgc1 \
		libpcre2-8-0 \
		libpq5 \
		libssl3 \
		zlib1g \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/bin/settler-engine /usr/local/bin/settler-engine

RUN useradd --system --no-create-home --shell /usr/sbin/nologin app \
	&& chown app:app /usr/local/bin/settler-engine

USER app

ENV HOST=0.0.0.0
ENV PORT=8080
EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=3 \
	CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1

# DATABASE_URL and WS_BOOTSTRAP_SECRET are passed at runtime. Do not bake .env into the image.
CMD ["/usr/local/bin/settler-engine"]
