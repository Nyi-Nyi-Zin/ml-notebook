FROM rust:1-bookworm AS builder
WORKDIR /app
COPY backend ./backend
COPY data ./data
WORKDIR /app/backend
RUN cargo build --locked --release

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system draftroom && useradd --system --gid draftroom draftroom
COPY --from=builder /app/backend/target/release/draftroom-api /usr/local/bin/draftroom-api
COPY --from=builder /app/backend/target/release/import_catalog /usr/local/bin/import_catalog
USER draftroom
ENV PORT=8080
EXPOSE 8080
CMD ["draftroom-api"]
