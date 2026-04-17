FROM hashicorp/terraform:1.14.8 AS terraform

FROM python:3.12-alpine

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN apk add --no-cache \
    bash \
    ca-certificates \
    catatonit \
    coreutils \
    curl \
    findutils \
    gawk \
    git \
    grep \
    wget

COPY --from=terraform /bin/terraform /usr/local/bin/terraform

COPY pyproject.toml README.md ./
COPY src ./src

RUN python -m pip install --upgrade pip \
  && python -m pip install .

COPY entrypoint.sh /usr/local/bin/mcp-bash-pipeline-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-bash-pipeline-entrypoint \
  && mkdir -p /tmp/mcp-bash-pipeline

EXPOSE 8107
ENTRYPOINT ["catatonit", "--", "/usr/local/bin/mcp-bash-pipeline-entrypoint"]
