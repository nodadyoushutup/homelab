FROM node:22-alpine AS base

ENV PNPM_HOME="/pnpm"
ENV PATH="${PNPM_HOME}:${PATH}"
ENV NEXT_TELEMETRY_DISABLED=1

RUN corepack enable && corepack prepare pnpm@10.5.1 --activate

FROM base AS deps

WORKDIR /app

COPY package.json pnpm-lock.yaml ./

RUN pnpm install --frozen-lockfile

FROM base AS builder

# Production image defaults. Docker dev overrides these build args from
# docker/docker-compose.yml so dev chat stays paired with dev LangGraph.
ARG NEXT_PUBLIC_API_URL=https://langchain-agent-chat.nodadyoushutup.com/api
ARG NEXT_PUBLIC_ASSISTANT_ID=agent
ARG NEXT_PUBLIC_AUTH_SCHEME=
ARG LANGGRAPH_API_URL=https://langgraph.nodadyoushutup.com

ENV NEXT_PUBLIC_API_URL="${NEXT_PUBLIC_API_URL}"
ENV NEXT_PUBLIC_ASSISTANT_ID="${NEXT_PUBLIC_ASSISTANT_ID}"
ENV NEXT_PUBLIC_AUTH_SCHEME="${NEXT_PUBLIC_AUTH_SCHEME}"
ENV LANGGRAPH_API_URL="${LANGGRAPH_API_URL}"

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

RUN pnpm build

FROM node:22-alpine AS runner

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV HOSTNAME=0.0.0.0
ENV PORT=3000
ENV LANGGRAPH_API_URL=https://langgraph.nodadyoushutup.com

WORKDIR /app

COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

USER node

EXPOSE 3000

CMD ["node", "server.js"]
