FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src

WORKDIR /app

COPY applications/rag-worker/requirements.txt /tmp/requirements.txt

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        tesseract-ocr \
        tesseract-ocr-eng \
    && pip install --no-cache-dir -r /tmp/requirements.txt \
    && apt-get purge -y build-essential \
    && apt-get autoremove -y --purge \
    && rm -rf /var/lib/apt/lists/*

COPY applications/rag-worker/src /app/src

EXPOSE 8080

RUN printf '%s\n' '#!/usr/bin/env bash' 'exec python -m rag_worker.healthcheck' > /usr/local/bin/rag-worker-healthcheck \
    && chmod +x /usr/local/bin/rag-worker-healthcheck

CMD ["uvicorn", "rag_worker.server:app", "--host", "0.0.0.0", "--port", "8080"]
