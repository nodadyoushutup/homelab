FROM ubuntu:24.04

ARG TARGETARCH
ARG RUNNER_VERSION=2.334.0

ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_HOME=/home/runner/actions-runner \
    PATH=/opt/runner-venv/bin:${PATH}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY scripts/install/ /tmp/install-scripts/
RUN apt-get update -y \
    && apt-get install -y --no-install-recommends ca-certificates curl git golang-go jq libicu74 make python3 python3-pip python3-venv sudo unzip zip \
    && chmod 0755 /tmp/install-scripts/*.sh \
    && AUTOMATION_DOCKER_PROFILE=cli \
       AUTOMATION_DOCKER_CONFIGURE_USER=0 \
       AUTOMATION_DOCKER_ENABLE_SERVICE=0 \
       AUTOMATION_DOCKER_VERIFY=0 \
       AUTOMATION_PACKER_CONFIGURE_USER=0 \
       /tmp/install-scripts/automation_tooling.sh \
    && rm -rf /var/lib/apt/lists/* /tmp/install-scripts

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

COPY applications/gha-runner/requirements.txt /tmp/requirements.txt
RUN python3 -m venv /opt/runner-venv \
    && /opt/runner-venv/bin/pip install --upgrade pip setuptools wheel \
    && /opt/runner-venv/bin/pip install -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

COPY applications/gha-runner/entrypoint.sh /usr/local/bin/gha-runner-entrypoint
RUN chmod 0755 /usr/local/bin/gha-runner-entrypoint \
    && chown -R runner:runner /home/runner /opt/runner-venv

USER runner
WORKDIR ${RUNNER_HOME}

ENTRYPOINT ["/usr/local/bin/gha-runner-entrypoint"]
