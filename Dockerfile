FROM ubuntu:noble

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

# Update APT and install basic packages
RUN apt-get update && \
    apt-get install --yes --no-install-recommends \
    locales \
    software-properties-common \
    curl \
    ca-certificates \
    sudo

# Generate and register the locale so runtime programs (e.g. initdb) can use it
RUN locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8
# Make sure the locale is visible to subsequent commands, add Timezone
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    TZ="America/Toronto" 

# Remove the 'ubuntu' user to free up UID 1000 for another user
RUN touch /var/mail/ubuntu && chown ubuntu /var/mail/ubuntu && userdel -r ubuntu

# Add a user `coder` so that you're not developing as the `root` user
RUN useradd coder \
    --create-home \
    --shell=/bin/bash \
    --uid=1000 \
    --user-group && \
    echo "coder ALL=(ALL) NOPASSWD:ALL" >>/etc/sudoers.d/nopasswd

# Add repositories for Git and Node.js LTS 
RUN add-apt-repository ppa:git-core/ppa && \
    curl -sL https://deb.nodesource.com/setup_lts.x | bash - 

# Add repository for PostgreSQL 
# Prevent creation of default postgres cluster (e.g. "17/main") so coder can manage it
RUN apt-get install -y postgresql-common && \
    printf 'create_main_cluster = false\n' | tee /etc/postgresql-common/createcluster.conf >/dev/null && \
    /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y && \
    apt-get update

# Install packages
# Also, Clean up afterwards to reduce image size
RUN apt-get upgrade --yes --no-install-recommends --no-install-suggests && \
    apt-get install --yes --no-install-recommends --no-install-suggests \
    bash \
    dnsutils \
    git \
    htop \
    iproute2 \
    jq \
    lsof \
    man \
    net-tools \
    nodejs \
    openssh-client \
    postgresql-17 \
    postgresql-client-17 \
    postgresql-contrib-17 \
    python3 \
    python3-pip \
    python3-venv \
    rsync \
    tzdata \
    unzip \
    util-linux \
    vim \
    wget \
    zip && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/apt/*

# Add PostgreSQL 17 binaries to PATH
# Verify no default cluster was auto-created (i.e. pg_lsclusters will print only the header)
ENV PATH="/usr/lib/postgresql/17/bin:$PATH"
RUN test "$(pg_lsclusters | wc -l)" -eq 1 || (echo 'Auto-created cluster detected:' && pg_lsclusters && exit 1)

# Install latest npm globally
RUN npm install -g npm@latest

#  Install the GitHub CLI
RUN (type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
    && sudo mkdir -p -m 755 /etc/apt/keyrings \
    && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && sudo mkdir -p -m 755 /etc/apt/sources.list.d \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && sudo apt update \
    && sudo apt install gh -y


# Install pm2
RUN npm install pm2 -g

# Install express
RUN npm install express -g

# Create a build metadata file with current build information
RUN echo "# Docker Build Metadata" > /opt/build-info.md && \
    echo "" >> /opt/build-info.md && \
    echo "**Build Date:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> /opt/build-info.md && \
    echo "**Build Timestamp:** $(date -u '+%s')" >> /opt/build-info.md && \
    echo "**Base Image:** ubuntu:noble" >> /opt/build-info.md && \
    echo "**Architecture:** $(dpkg --print-architecture)" >> /opt/build-info.md && \
    echo "**Node.js Version:** $(node --version)" >> /opt/build-info.md && \
    echo "**NPM Version:** $(npm --version)" >> /opt/build-info.md && \
    echo "**PostgreSQL Version:** $(pg_config --version)" >> /opt/build-info.md && \
    echo "**PM2 Version:** $(npm list -g pm2 --depth=0 2>/dev/null | grep pm2@ | sed 's/.*pm2@//' | sed 's/ .*//')" >> /opt/build-info.md && \
    echo "" >> /opt/build-info.md && \
    echo "This file was generated during the Docker image build process." >> /opt/build-info.md

# Copy PaaS scripts, make them executable
COPY --chown=coder:coder srv/ /opt/bootstrap/srv/
RUN chmod +x /opt/bootstrap/srv/scripts/*.sh

# Copy PM2 ecosystem configuration
COPY --chown=coder:coder ecosystem.config.js /opt/bootstrap/ecosystem.config.js

USER coder

# Pre-install Node dependencies for admin, placeholders, and slot web server
RUN set -eux; \
    cd /opt/bootstrap/srv/admin && npm install --omit=dev; \
    cd /opt/bootstrap/srv/server && npm install --omit=dev


