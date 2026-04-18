# syntax=docker/dockerfile:1.4

FROM langchain/langgraph-api:3.11

COPY . /deps/langgraph

RUN cd /deps/langgraph && \
    PYTHONDONTWRITEBYTECODE=1 uv pip install --system --no-cache-dir -c /api/constraints.txt -e .

ENV LANGSERVE_GRAPHS='{"controller_agent": "/deps/langgraph/apps/controller-agent/agent.py:controller_agent", "code_analysis_agent": "/deps/langgraph/apps/controller-agent/agent.py:code_analysis_agent", "jira_agent": "/deps/langgraph/apps/controller-agent/agent.py:jira_agent"}'

# Re-install the bundled API package after local deps are added so the official
# runtime remains the active entrypoint.
RUN mkdir -p /api/langgraph_api /api/langgraph_runtime /api/langgraph_license && \
    touch /api/langgraph_api/__init__.py /api/langgraph_runtime/__init__.py /api/langgraph_license/__init__.py && \
    PYTHONDONTWRITEBYTECODE=1 uv pip install --system --no-cache-dir --no-deps -e /api
