FROM python:3.12.11-alpine3.22

WORKDIR /srv/cloud-image-repository

COPY server.py .
COPY ui/ ./ui/

ENV CLOUD_IMAGE_REPOSITORY_DATA_ROOT=/srv/cloud-image-repository/data \
    CLOUD_IMAGE_REPOSITORY_UI_ROOT=/srv/cloud-image-repository/ui \
    CLOUD_IMAGE_REPOSITORY_PORT=8080

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=5 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/', timeout=5).read(1)"

CMD ["python3", "/srv/cloud-image-repository/server.py"]
