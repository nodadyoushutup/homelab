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

# Switch back to the default (jenkins) user
USER jenkins
