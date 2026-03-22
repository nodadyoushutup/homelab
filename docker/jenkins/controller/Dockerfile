FROM jenkins/jenkins:2.555

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    CASC_JENKINS_CONFIG="/var/jenkins_home/jenkins.yaml"

# Switch to root for installing plugins and additional tools
USER root

# Copy the plugins file and install plugins. The build context for this image is
# the repository root, so source paths are relative to the repo root.
COPY docker/jenkins/controller/plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt --verbose

# Copy the agent exporter
COPY docker/jenkins/controller/export-agent-secret.groovy /usr/share/jenkins/ref/init.groovy.d/export-agent-secret.groovy

# Reuse shared install scripts from scripts/install as source-of-truth.
COPY scripts/install/packages.sh /tmp/install-scripts/packages.sh
COPY scripts/install/docker.sh /tmp/install-scripts/docker.sh
COPY scripts/install/terraform.sh /tmp/install-scripts/terraform.sh
COPY scripts/install/ansible.sh /tmp/install-scripts/ansible.sh
COPY scripts/install/kubectl.sh /tmp/install-scripts/kubectl.sh
COPY scripts/install/k9s.sh /tmp/install-scripts/k9s.sh
COPY scripts/install/packer.sh /tmp/install-scripts/packer.sh
COPY scripts/install/minio_client.sh /tmp/install-scripts/minio_client.sh

# Install base packages and tools via shared scripts.
RUN chmod 0755 /tmp/install-scripts/packages.sh \
               /tmp/install-scripts/docker.sh \
               /tmp/install-scripts/terraform.sh \
               /tmp/install-scripts/ansible.sh \
               /tmp/install-scripts/kubectl.sh \
               /tmp/install-scripts/k9s.sh \
               /tmp/install-scripts/packer.sh \
               /tmp/install-scripts/minio_client.sh \
    && /tmp/install-scripts/packages.sh \
    && INSTALL_DOCKER_PROFILE=cli DOCKER_ENABLE_SERVICE=0 DOCKER_VERIFY=0 TARGET_USER=jenkins /tmp/install-scripts/docker.sh \
    && /tmp/install-scripts/terraform.sh \
    && /tmp/install-scripts/ansible.sh \
    && /tmp/install-scripts/kubectl.sh \
    && /tmp/install-scripts/k9s.sh \
    && TARGET_USER=jenkins /tmp/install-scripts/packer.sh \
    && /tmp/install-scripts/minio_client.sh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/install-scripts

# Switch back to the default (jenkins) user
USER jenkins
