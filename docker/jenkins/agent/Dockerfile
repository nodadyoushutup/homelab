FROM jenkins/inbound-agent:3283.v92c105e0f819-7

# Switch to root to install additional packages
USER root

# TARGETARCH is provided automatically when building with BuildKit. Fallback to
# the runtime architecture when building without it.
ARG TARGETARCH

# Update package lists and install prerequisites, including Python and pip.
RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    common_packages="apt-transport-https \
      curl \
      gnupg \
      lsb-release \
      jq \
      python3 \
      python3-pip \
      bat \
      bridge-utils \
      btop \
      dnsutils \
      duf \
      ethtool \
      fd-find \
      gh \
      git \
      htop \
      ifupdown \
      iotop \
      iperf3 \
      iptables \
      libvirt-clients \
      libvirt-daemon-system \
      lshw \
      lsof \
      make \
      default-mysql-client \
      nano \
      net-tools \
      netcat-openbsd \
      neovim \
      nfs-common \
      nmap \
      open-iscsi \
      parted \
      postgresql-client \
      python3-venv \
      qemu-guest-agent \
      ripgrep \
      rsync \
      screen \
      smartmontools \
      strace \
      tcpdump \
      tmux \
      traceroute \
      tree \
      ufw \
      unzip \
      util-linux \
      vim \
      virtinst \
      wget \
      whois \
      xorriso \
      zip"; \
    arch_packages=""; \
    case "$arch" in \
      amd64|x86_64) \
        arch_packages="cpu-checker qemu-kvm qemu-system-x86" \
        ;; \
      arm64|aarch64) \
        arch_packages="qemu-system-arm" \
        ;; \
      *) \
        echo "Unsupported architecture: $arch" >&2; exit 1 \
        ;; \
    esac; \
    apt-get install -y --no-install-recommends $common_packages $arch_packages; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Install boto3 and botocore via pip, overriding system restrictions.
RUN pip3 install --break-system-packages boto3 botocore

# Add the HashiCorp GPG key and repository (Terraform + Packer come from here)
RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
      amd64|x86_64) repo_arch="amd64" ;; \
      arm64|aarch64) repo_arch="arm64" ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    mkdir -p /usr/share/keyrings; \
    curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg; \
    echo "deb [arch=${repo_arch} signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list

# Install Terraform, Packer, and Ansible
RUN apt-get update && apt-get install -y \
    terraform \
    packer \
    ansible && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install MinIO Client
RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
      amd64|x86_64) mc_arch="amd64" ;; \
      arm64|aarch64) mc_arch="arm64" ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    curl -sSL "https://dl.min.io/client/mc/release/linux-${mc_arch}/mc" -o /usr/local/bin/mc; \
    chmod +x /usr/local/bin/mc

# Add the custom Jenkins agent entrypoint. The build context for this image is
# `docker/jenkins/agent`, so source paths are relative to that directory.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Ensure the Jenkins home directory exists with the correct ownership so that
# named volumes inherit the right permissions when initialised.
RUN mkdir -p /home/jenkins && chown -R jenkins:jenkins /home/jenkins

ENV JENKINS_AGENT_HOME=/home/jenkins \
    JENKINS_HOME=/home/jenkins \
    HOME=/home/jenkins

# Switch back to the default (jenkins) user
USER jenkins

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
