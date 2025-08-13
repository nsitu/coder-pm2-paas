FROM ubuntu:noble

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# Install packages
RUN apt-get update && \
    apt-get upgrade --yes --no-install-recommends --no-install-suggests && \
    apt-get install --yes --no-install-recommends --no-install-suggests \
    ca-certificates \
    bash \
    build-essential \ 
    curl \ 
    htop \
    jq \
    locales \
    man \
    pipx \
    python3 \
    python3-pip \
    software-properties-common \
    sudo \
    # systemd \
    # systemd-sysv \
    unzip \
    zip \
    vim \
    wget \
    net-tools \
    dnsutils \
    tzdata \
    rsync \ 
    openssh-client \
    lsof \
    util-linux \
    nginx && \ 
    # Install latest Git using their official PPA
    add-apt-repository ppa:git-core/ppa && \
    apt-get install --yes git \
    && rm -rf /var/lib/apt/lists/*


# Install whichever Node version is LTS 
RUN curl -sL https://deb.nodesource.com/setup_lts.x | bash -
RUN DEBIAN_FRONTEND="noninteractive" apt-get update -y && \
    apt-get install -y nodejs 

# Latest NPM 
RUN npm install -g npm@latest --verbose

# Install pm2
RUN npm install pm2 -g

# Generate the desired locale (en_US.UTF-8)
RUN locale-gen en_US.UTF-8

# Set Timezone
ENV TZ="America/Toronto"

# Make typing unicode characters in the terminal work.
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Remove the `ubuntu` user and add a user `coder` so that you're not developing as the `root` user
RUN userdel -r ubuntu && \
    useradd coder \
    --create-home \
    --shell=/bin/bash \ 
    --uid=1000 \
    --user-group && \
    echo "coder ALL=(ALL) NOPASSWD:ALL" >>/etc/sudoers.d/nopasswd

# Copy system files to seed the container
COPY --chown=coder:coder srv/ /opt/bootstrap/srv/

# Make the deploy script executable
RUN chmod +x /opt/bootstrap/srv/deploy/deploy.sh

# Pre-seed GitHub known_hosts to avoid first-clone prompts (optional):
RUN mkdir -p /home/coder/.ssh && ssh-keyscan github.com >> /home/coder/.ssh/known_hosts && chown -R coder:coder /home/coder/.ssh

USER coder

# adds user's bin directory to PATH
RUN pipx ensurepath 

