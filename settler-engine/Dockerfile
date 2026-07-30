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
	&& apt-get install -y --no-install-recommends libpq5 ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/bin/settler-engine /usr/local/bin/settler-engine

RUN useradd --system --no-create-home --shell /usr/sbin/nologin app \
	&& chown app:app /usr/local/bin/settler-engine

USER app

EXPOSE 8080

# Optional: DATABASE_URL, WS_BOOTSTRAP_SECRET — pass at runtime (do not bake .env into the image)
CMD ["/usr/local/bin/settler-engine"]
