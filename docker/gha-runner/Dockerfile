FROM ubuntu:24.04

ARG TARGETARCH
ARG RUNNER_VERSION=2.326.0

ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_HOME=/home/runner/actions-runner \
    PATH=/opt/runner-venv/bin:${PATH}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY packages.apt /tmp/packages.apt
RUN apt-get update \
    && xargs -r apt-get install -y --no-install-recommends < /tmp/packages.apt \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash runner

WORKDIR ${RUNNER_HOME}
RUN case "${TARGETARCH}" in \
      amd64) RUNNER_ARCH="x64" ;; \
      arm64) RUNNER_ARCH="arm64" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL -o actions-runner.tar.gz "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" \
    && tar -xzf actions-runner.tar.gz \
    && rm actions-runner.tar.gz \
    && ./bin/installdependencies.sh

COPY requirements.txt /tmp/requirements.txt
RUN python3 -m venv /opt/runner-venv \
    && /opt/runner-venv/bin/pip install --upgrade pip setuptools wheel \
    && /opt/runner-venv/bin/pip install -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

COPY entrypoint.sh /usr/local/bin/gha-runner-entrypoint
RUN chmod 0755 /usr/local/bin/gha-runner-entrypoint \
    && chown -R runner:runner /home/runner /opt/runner-venv

USER runner
WORKDIR ${RUNNER_HOME}

ENTRYPOINT ["/usr/local/bin/gha-runner-entrypoint"]
