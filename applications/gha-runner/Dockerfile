FROM ubuntu:24.04

ARG TARGETARCH
ARG RUNNER_VERSION=2.332.0

ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_HOME=/home/runner/actions-runner \
    PATH=/opt/runner-venv/bin:${PATH}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY scripts/install/packages.sh /tmp/install-scripts/packages.sh
COPY scripts/install/docker.sh /tmp/install-scripts/docker.sh
COPY scripts/install/terraform.sh /tmp/install-scripts/terraform.sh
COPY scripts/install/ansible.sh /tmp/install-scripts/ansible.sh
COPY scripts/install/kubectl.sh /tmp/install-scripts/kubectl.sh
COPY scripts/install/k9s.sh /tmp/install-scripts/k9s.sh
COPY scripts/install/packer.sh /tmp/install-scripts/packer.sh
COPY scripts/install/minio_client.sh /tmp/install-scripts/minio_client.sh
RUN apt-get update -y \
    && apt-get install -y --no-install-recommends ca-certificates curl git jq libicu74 python3 python3-pip python3-venv sudo unzip zip \
    && chmod 0755 /tmp/install-scripts/packages.sh \
                  /tmp/install-scripts/docker.sh \
                  /tmp/install-scripts/terraform.sh \
                  /tmp/install-scripts/ansible.sh \
                  /tmp/install-scripts/kubectl.sh \
                  /tmp/install-scripts/k9s.sh \
                  /tmp/install-scripts/packer.sh \
                  /tmp/install-scripts/minio_client.sh \
    && /tmp/install-scripts/packages.sh \
    && INSTALL_DOCKER_PROFILE=cli DOCKER_CONFIGURE_USER=0 DOCKER_ENABLE_SERVICE=0 DOCKER_VERIFY=0 /tmp/install-scripts/docker.sh \
    && /tmp/install-scripts/terraform.sh \
    && /tmp/install-scripts/ansible.sh \
    && /tmp/install-scripts/kubectl.sh \
    && /tmp/install-scripts/k9s.sh \
    && PACKER_CONFIGURE_USER=0 /tmp/install-scripts/packer.sh \
    && /tmp/install-scripts/minio_client.sh \
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
