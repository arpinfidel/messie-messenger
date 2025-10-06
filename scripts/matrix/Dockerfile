FROM node:22-bookworm-slim

WORKDIR /app

# Cache deps
COPY package.json package-lock.json* tsconfig.json ./
COPY src ./src

RUN npm install --no-audit --no-fund \
 && npm run build --silent

ENTRYPOINT ["node", "/app/dist/verify_peer.js"]
