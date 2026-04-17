FROM python:3.12-alpine

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN apk add --no-cache catatonit

COPY pyproject.toml README.md ./
COPY src ./src

RUN python -m pip install --upgrade pip \
  && python -m pip install .

COPY entrypoint.sh /usr/local/bin/mcp-redis-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-redis-entrypoint

EXPOSE 8101
ENTRYPOINT ["catatonit", "--", "/usr/local/bin/mcp-redis-entrypoint"]
