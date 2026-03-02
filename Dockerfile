# NanoClaw Orchestrator - GKE Deployment Image
# Runs the main Node.js process that routes messages and spawns agent containers

FROM node:22-slim

# Install Docker CLI (for spawning agent containers via DinD sidecar)
RUN apt-get update && apt-get install -y \
    docker.io \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy package files for dependency caching
COPY package*.json ./

# Install production dependencies only
RUN npm ci --omit=dev

# Copy compiled TypeScript output
COPY dist/ ./dist/

# Copy container assets (Dockerfile, skills, agent-runner for building agent image)
COPY container/ ./container/

# Copy group templates if any
COPY groups/ ./groups/

# Create state directories
RUN mkdir -p store data/sessions data/ipc

# Non-root user
USER node

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s \
  CMD curl -f http://localhost:3100/healthz || exit 1

EXPOSE 3100

CMD ["node", "dist/index.js"]
