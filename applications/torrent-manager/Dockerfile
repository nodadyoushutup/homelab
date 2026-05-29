FROM python:3.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY requirements.txt /tmp/requirements.txt

RUN pip install --upgrade pip \
    && pip install \
        --retries 10 \
        --default-timeout 120 \
        --no-cache-dir \
        -r /tmp/requirements.txt

COPY src /app/src
COPY config/config.yaml /etc/torrent-manager/config.yaml
COPY entrypoint.sh /usr/local/bin/torrent-manager-entrypoint

ENV TORRENT_MANAGER_CONFIG_PATH=/etc/torrent-manager/config.yaml

RUN chmod +x /usr/local/bin/torrent-manager-entrypoint \
    && mkdir -p /data /etc/torrent-manager

EXPOSE 8080

ENTRYPOINT ["torrent-manager-entrypoint"]
CMD ["serve"]
