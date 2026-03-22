FROM jenkins/inbound-agent:3283.v92c105e0f819-7

# Switch to root to install additional packages
USER root

# Reuse shared install scripts from scripts/install as source-of-truth.
COPY scripts/install/packages.sh /tmp/install-scripts/packages.sh
COPY scripts/install/docker.sh /tmp/install-scripts/docker.sh
COPY scripts/install/terraform.sh /tmp/install-scripts/terraform.sh
COPY scripts/install/ansible.sh /tmp/install-scripts/ansible.sh
COPY scripts/install/kubectl.sh /tmp/install-scripts/kubectl.sh
COPY scripts/install/k9s.sh /tmp/install-scripts/k9s.sh
COPY scripts/install/packer.sh /tmp/install-scripts/packer.sh
COPY scripts/install/minio_client.sh /tmp/install-scripts/minio_client.sh

# Install build/runtime tooling used by pipeline jobs.
RUN chmod 0755 /tmp/install-scripts/packages.sh \
               /tmp/install-scripts/docker.sh \
               /tmp/install-scripts/terraform.sh \
               /tmp/install-scripts/ansible.sh \
               /tmp/install-scripts/kubectl.sh \
               /tmp/install-scripts/k9s.sh \
               /tmp/install-scripts/packer.sh \
               /tmp/install-scripts/minio_client.sh \
    && /tmp/install-scripts/packages.sh \
    && pip3 install --break-system-packages boto3 botocore \
    && INSTALL_DOCKER_PROFILE=cli DOCKER_ENABLE_SERVICE=0 DOCKER_VERIFY=0 TARGET_USER=jenkins /tmp/install-scripts/docker.sh \
    && /tmp/install-scripts/terraform.sh \
    && /tmp/install-scripts/ansible.sh \
    && /tmp/install-scripts/kubectl.sh \
    && /tmp/install-scripts/k9s.sh \
    && TARGET_USER=jenkins /tmp/install-scripts/packer.sh \
    && /tmp/install-scripts/minio_client.sh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/install-scripts

# Add the custom Jenkins agent entrypoint.
COPY docker/jenkins/agent/entrypoint.sh /usr/local/bin/entrypoint.sh
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
