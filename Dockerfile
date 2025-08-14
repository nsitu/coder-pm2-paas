FROM ubuntu:noble

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ="America/Toronto"

# Add all repositories first
RUN apt-get update && \
    apt-get install --yes --no-install-recommends software-properties-common curl ca-certificates && \
    # Add Git PPA for latest version
    add-apt-repository ppa:git-core/ppa && \
    # Add PostgreSQL official repository
    apt-get install -y postgresql-common && \
    /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y && \
    # Add Node.js LTS repository
    curl -sL https://deb.nodesource.com/setup_lts.x | bash - && \
    # Single comprehensive update after all repositories are added
    apt-get update

# Install all packages in single optimized layer
RUN apt-get upgrade --yes --no-install-recommends --no-install-suggests && \
    apt-get install --yes --no-install-recommends --no-install-suggests \
    bash \
    dnsutils \
    git \
    htop \
    jq \
    locales \
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
    sudo \
    tzdata \
    unzip \
    util-linux \
    vim \
    wget \
    zip && \
    # Clean up aggressively to reduce image size
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/apt/*

# Install npm and PGAdmin4 efficiently
RUN npm install -g npm@latest && \
    # Use single virtual environment instead of pipx to reduce overhead
    python3 -m venv /opt/pgadmin-venv && \
    /opt/pgadmin-venv/bin/pip install --no-cache-dir pgadmin4 && \
    # Create symlink for easy access
    ln -s /opt/pgadmin-venv/bin/pgadmin4 /usr/local/bin/pgadmin4 && \
    mkdir -p /var/lib/pgladmin /var/log/pgladmin && \
    # Clean up all caches
    rm -rf /root/.cache/pip /root/.npm /tmp/*

# Locale and user setup
RUN locale-gen en_US.UTF-8 && \
    userdel -r ubuntu && \
    useradd coder \
    --create-home \
    --shell=/bin/bash \
    --uid=1000 \
    --user-group && \
    echo "coder ALL=(ALL) NOPASSWD:ALL" >>/etc/sudoers.d/nopasswd

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Add PostgreSQL 17 binaries to PATH
ENV PATH="/usr/lib/postgresql/17/bin:$PATH"

# Copy system files and setup permissions in single layer
COPY --chown=coder:coder srv/ /opt/bootstrap/srv/
RUN chmod +x /opt/bootstrap/srv/scripts/*.sh && \
    mkdir -p /home/coder/.ssh && \
    ssh-keyscan github.com >> /home/coder/.ssh/known_hosts && \
    chown -R coder:coder /home/coder/.ssh

USER coder
