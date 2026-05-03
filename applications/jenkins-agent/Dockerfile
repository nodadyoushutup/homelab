FROM jenkins/inbound-agent:3283.v92c105e0f819-7-jdk21

# Switch to root to install additional packages
USER root

# Reuse shared install scripts from scripts/install as source-of-truth.
COPY scripts/install/ /tmp/install-scripts/

# Install build/runtime tooling used by pipeline jobs.
RUN chmod 0755 /tmp/install-scripts/*.sh \
    && AUTOMATION_TARGET_USER=jenkins \
       AUTOMATION_DOCKER_PROFILE=cli \
       AUTOMATION_DOCKER_ENABLE_SERVICE=0 \
       AUTOMATION_DOCKER_VERIFY=0 \
       /tmp/install-scripts/automation_tooling.sh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/install-scripts

# Add the custom Jenkins agent entrypoint.
COPY applications/jenkins-agent/entrypoint.sh /usr/local/bin/entrypoint.sh
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
