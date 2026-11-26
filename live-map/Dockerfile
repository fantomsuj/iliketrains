# The live server, for an always-on host (Railway, Fly.io, Render, any VM). Build from live-map/:
#   docker build -t trains-server .   &&   docker run -p 8787:8787 trains-server
# Timetables (static GTFS) are downloaded at build time, so redeploy weekly to pick up schedule changes.
FROM node:22-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends curl unzip ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY tiles/style tiles/style
COPY server/package.json server/package-lock.json server/
RUN cd server && npm ci --omit=dev --no-audit --no-fund
COPY server server
RUN cd server && ./scripts/fetch-gtfs.sh
ENV NODE_ENV=production PORT=8787 HOST=0.0.0.0 TRAINS_DATA_DIR=/data
EXPOSE 8787
WORKDIR /app/server
CMD ["node", "--disable-warning=ExperimentalWarning", "src/server.ts"]
