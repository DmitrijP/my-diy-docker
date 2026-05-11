FROM dockerhub.registry.inter.de/ubuntu:22.04
LABEL vendor="IT LAB @ Dmitrij Patuk"

ENV DEBIAN_FRONTEND=noninteractive
ENV BUILDUSR=developer
ENV GO_VERSION=1.22.3

# -------------------------------------------------
# System setup (root)
# -------------------------------------------------
RUN apt-get -qq update && \
    apt-get -qq install -y \
    build-essential \
    wget \
    apt-file \
    sudo \
    vim \
    neovim \
    gdb \
    clang \
    clang-format \
    git \
    iproute2 \
    iputils-ping \
    psmisc \
    htop \
    traceroute \
    iptables \
    tcpdump && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------
# Install Go system-wide
# -------------------------------------------------
RUN wget -q https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz && \
    rm go${GO_VERSION}.linux-amd64.tar.gz

ENV PATH="/usr/local/go/bin:${PATH}"

# -------------------------------------------------
# Create developer user
# -------------------------------------------------
RUN useradd -ms /bin/bash ${BUILDUSR} && \
    echo "${BUILDUSR}:${BUILDUSR}" | chpasswd && \
    usermod -aG sudo ${BUILDUSR}

# -------------------------------------------------
# Switch to developer user
# -------------------------------------------------
USER ${BUILDUSR}

# -------------------------------------------------
# User environment
# -------------------------------------------------
ENV HOME=/home/${BUILDUSR}
ENV GOPATH=${HOME}/go
ENV SRC=${HOME}/source-code
ENV BASH_ENV=${HOME}/.bashrc

RUN mkdir -p ${GOPATH} ${SRC}

# -------------------------------------------------
# Config files
# -------------------------------------------------
COPY --chown=${BUILDUSR}:${BUILDUSR} .bashrc ${HOME}/.bashrc
COPY --chown=${BUILDUSR}:${BUILDUSR} .vimrc ${HOME}/.vimrc
COPY --chown=${BUILDUSR}:${BUILDUSR} .clang-format ${HOME}/.clang-format

RUN chown ${BUILDUSR}:${BUILDUSR} \
    ${HOME}/.bashrc \
    ${HOME}/.vimrc \
    ${HOME}/.clang-format

# -------------------------------------------------
# Git configuration
# -------------------------------------------------
RUN git config --global color.ui auto && \
    git config --global core.editor vim && \
    git config --global init.defaultBranch main

WORKDIR ${SRC}

