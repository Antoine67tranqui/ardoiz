FROM node:22-alpine AS build
# Prisma a besoin d'OpenSSL pour detecter la plateforme (Alpine ne l'inclut pas).
RUN apk add --no-cache openssl
WORKDIR /app
COPY package*.json ./
COPY prisma ./prisma
RUN npm ci
COPY . .
RUN npm run prisma:generate && npm run build

# Etape de migration : seule a contenir le CLI Prisma (absent de l'image finale, plus petite
# et sans outil d'administration de la base). Lancee une fois a chaque mise a jour.
FROM build AS migrate
ENV NODE_ENV=production
CMD ["npx", "prisma", "migrate", "deploy"]

FROM node:22-alpine AS runtime
RUN apk add --no-cache openssl
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --omit=dev
# Client Prisma genere (et son moteur) a l'etape de build : le CLI n'est pas installe ici.
COPY --from=build /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=build /app/dist ./dist
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:${PORT:-3000}/api/v1/health || exit 1
USER node
CMD ["node", "dist/main.js"]
