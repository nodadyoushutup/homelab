FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/app

RUN apt-get update \
  && apt-get install -y --no-install-recommends git netcat-traditional ca-certificates \
  && rm -rf /var/lib/apt/lists/*

ARG FTG_MCP_REF=3193a7b75413db9f95f038a7f8d1c0c26cba98f4
RUN pip install --no-cache-dir \
    "mcp==1.13.0" \
    "fastmcp==2.11.3" \
    "httpx>=0.24.0" \
    "pydantic>=2.0.0" \
    "fastapi>=0.104.0" \
    "uvicorn[standard]>=0.24.0" \
    "asgiref>=3.7.0"
RUN pip install --no-cache-dir --no-deps "git+https://github.com/juststank/ftg_mcp.git@${FTG_MCP_REF}"
RUN python - <<'PY'
from pathlib import Path

site_packages = Path("/usr/local/lib/python3.11/site-packages")
(site_packages / "sitecustomize.py").unlink(missing_ok=True)

init_path = site_packages / "src/fortigate_mcp/__init__.py"
init_path.write_text(
    "\"\"\"FortiGate MCP package metadata.\"\"\"\n"
    "__version__ = \"1.0.0\"\n"
    "__author__ = \"FortiGate MCP Team\"\n"
    "__email__ = \"support@fortimcp.dev\"\n\n"
    "from .server_http import FortiGateMCPHTTPServer\n\n"
    "__all__ = [\"FortiGateMCPHTTPServer\"]\n",
    encoding="utf-8",
)
PY

RUN useradd --uid 1000 --create-home appuser
COPY entrypoint.sh /usr/local/bin/fortigate-mcp-entrypoint
RUN chmod 0755 /usr/local/bin/fortigate-mcp-entrypoint

USER appuser
WORKDIR /app

EXPOSE 8814
ENTRYPOINT ["/usr/local/bin/fortigate-mcp-entrypoint"]
