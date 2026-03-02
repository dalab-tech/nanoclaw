# NanoClaw Control Plane API
# Deployed on Cloud Run for managing tenant lifecycle

FROM node:22-slim

# Install kubectl and gcloud CLI
RUN apt-get update && apt-get install -y curl gnupg && \
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list && \
    apt-get update && apt-get install -y google-cloud-cli kubectl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY dist/ ./dist/

USER node

EXPOSE 8080

CMD ["node", "dist/index.js"]
