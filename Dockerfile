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

# Install PGAdmin4 
# Use single virtual environment instead of pipx to reduce overhead
# RUN python3 -m venv /opt/pgadmin-venv && \
#     /opt/pgadmin-venv/bin/pip install --no-cache-dir pgadmin4 && \
#     # Create symlink for easy access (safer than adding entire venv to PATH)
#     ln -s /opt/pgadmin-venv/bin/pgadmin4 /usr/local/bin/pgadmin4 && \
#     # Create pgadmin directories with proper permissions for coder user
#     mkdir -p /var/lib/pgadmin /var/log/pgadmin && \
#     # Give coder user access to pgadmin directories
#     chown -R coder:coder /var/lib/pgadmin /var/log/pgadmin && \
#     # Clean up all caches
#     rm -rf /root/.cache/pip /root/.npm /tmp/*

# Configure PGAdmin environment variables (image-level defaults)
# ENV 
#     PGADMIN_SETUP_EMAIL=ixd@sheridancollege.ca \
#     PGADMIN_SETUP_PASSWORD=admin 

# ENV PGADMIN_DEFAULT_EMAIL=ixd@sheridancollege.ca \
#     PGADMIN_DEFAULT_PASSWORD=admin \
#     PGADMIN_LISTEN_ADDRESS=0.0.0.0 \
#     PGADMIN_LISTEN_PORT=5050 \
#     PGADMIN_CONFIG_DESKTOP_USER=ixd@sheridancollege.ca \
#     PGADMIN_CONFIG_SERVER_MODE=False \
#     PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED=False \
#     PGADMIN_CONFIG_CONSOLE_LOG_LEVEL=10 \
#     # NOTE: the following paths will be assumed by scripts
#     PGADMIN_CONFIG_SQLITE_PATH=/home/coder/data/pgadmin.db \
#     PGADMIN_CONFIG_LOG_FILE=/home/coder/logs/pgadmin.log \
#     PGADMIN_CONFIG_SESSION_DB_PATH=/home/coder/data/pgadmin/sessions \
#     PGADMIN_CONFIG_STORAGE_DIR=/home/coder/data/pgadmin/storage

# Install PGWeb (PostgreSQL web interface)
# RUN curl -s https://api.github.com/repos/sosedoff/pgweb/releases/latest \
#     | grep linux_amd64.zip \
#     | grep download \
#     | cut -d '"' -f 4 \
#     | wget -qi - \
#     && unzip pgweb_linux_amd64.zip \
#     && rm pgweb_linux_amd64.zip \
#     && mv pgweb_linux_amd64 /usr/local/bin/pgweb

# Copy PaaS scripts and make them executable
COPY --chown=coder:coder srv/ /opt/bootstrap/srv/
RUN chmod +x /opt/bootstrap/srv/scripts/*.sh 

USER coder

# Pre-install Node dependencies for admin and placeholders
RUN set -eux; \
    cd /opt/bootstrap/srv/admin && npm install --omit=dev; \
    cd /opt/bootstrap/srv/placeholders && npm install --omit=dev


