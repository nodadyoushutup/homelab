FROM python:3.14.5-alpine3.22

WORKDIR /app

COPY server.py .
COPY ui/ ./ui/

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=5 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/', timeout=5).read(1)"

CMD ["python3", "/app/server.py"]
