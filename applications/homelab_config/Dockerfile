# homelab-config web app (local-dev container).
# Built via docker/docker-compose.homelab-config.yaml with the source bind-mounted
# for hot reload; the COPY below just bakes a runnable default image.
FROM python:3.12-slim

# ssh-keygen (openssh-client) backs the SSH key fingerprints in ssh_store.py.
# libnss-mdns lets the container resolve <host>.local (mDNS/Avahi) names like
# swarm-cp-0.local when run on the host network - the swarm nodes are addressed
# by their .local hostnames. We write nsswitch.conf so mdns4_minimal is queried
# before regular DNS.
# - openssh-client: system ssh/scp (native SSH-certificate auth) for reconcile.
# - sshpass: non-interactive password fallback when a node has no key yet.
# - libnss-mdns: resolve <host>.local names via the host's avahi (socket mounted
#   by compose); we write nsswitch so mdns4_minimal is queried before DNS.
RUN apt-get update \
  && apt-get install -y --no-install-recommends openssh-client curl libnss-mdns sshpass \
  && rm -rf /var/lib/apt/lists/* \
  && printf '%s\n' \
     'passwd:         files' \
     'group:          files' \
     'shadow:         files' \
     'gshadow:        files' \
     'hosts:          files mdns4_minimal [NOTFOUND=return] dns myhostname' \
     'networks:       files' \
     'protocols:      db files' \
     'services:       db files' \
     'ethers:         db files' \
     'rpc:            db files' \
     'netgroup:       nis' \
     > /etc/nsswitch.conf

ENV PYTHONUNBUFFERED=1 \
  PYTHONDONTWRITEBYTECODE=1 \
  PYTHONPATH=/workspace/applications \
  HOMELAB_CONFIG_HOST=0.0.0.0 \
  HOMELAB_CONFIG_PORT=8770 \
  HOME=/home/homelab

# The compose service runs as uid/gid 1000 (the host operator). The system ssh
# binary refuses to run for a uid with no passwd entry ("No user exists for uid
# 1000"), so bake a matching user with a writable home.
RUN groupadd -g 1000 homelab 2>/dev/null || true; \
  useradd -u 1000 -g 1000 -m -d /home/homelab -s /bin/bash homelab 2>/dev/null || true

WORKDIR /workspace/applications/homelab_config

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Bake the package so the image runs standalone; the compose bind mount overlays
# this path in local dev for live editing.
COPY . /workspace/applications/homelab_config

# The compose service runs as the host user (uid/gid 1000) so bind-mounted files
# on NFS (root-squashed) stay readable/writable. Make the image-owned dirs and the
# runtime data dir writable by that user.
RUN mkdir -p /workspace/data && chown -R 1000:1000 /workspace

EXPOSE 8770

CMD ["python", "-m", "homelab_config"]
