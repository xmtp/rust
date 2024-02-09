FROM debian:stable-slim as go-builder
# defined from build kit
# DOCKER_BUILDKIT=1 docker build . -t ...
ARG TARGETARCH

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt update && \
    apt install -y -q --no-install-recommends \
    git curl gnupg2 build-essential coreutils \
    openssl libssl-dev pkg-config \
    ca-certificates apt-transport-https \
    python3 && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

## Go Lang
ARG GO_VERSION=1.22.0
ADD https://go.dev/dl/go${GO_VERSION}.linux-$TARGETARCH.tar.gz /goinstall/go${GO_VERSION}.linux-$TARGETARCH.tar.gz
RUN echo 'SHA256 of this go source package...'
RUN cat /goinstall/go${GO_VERSION}.linux-$TARGETARCH.tar.gz | sha256sum 
RUN tar -C /usr/local -xzf /goinstall/go${GO_VERSION}.linux-$TARGETARCH.tar.gz
WORKDIR /yamlfmt
ENV GOBIN=/usr/local/go/bin
ENV PATH=$PATH:${GOBIN}
RUN go install github.com/google/yamlfmt/cmd/yamlfmt@latest
RUN ls -lR /usr/local/go/bin/yamlfmt && strip /usr/local/go/bin/yamlfmt && ls -lR /usr/local/go/bin/yamlfmt
RUN yamlfmt --version

FROM debian:stable-slim as builder
# defined from build kit
# DOCKER_BUILDKIT=1 docker build . -t ...
ARG TARGETARCH

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt update && \
    apt install -y -q --no-install-recommends \
    git curl gnupg2 build-essential \
    linux-headers-${TARGETARCH} libc6-dev \ 
    openssl libssl-dev pkg-config \
    ca-certificates apt-transport-https \
    python3 && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

RUN useradd --create-home -s /bin/bash xmtp
RUN usermod -a -G sudo xmtp
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

WORKDIR /rustup
## Rust
ADD https://sh.rustup.rs /rustup/rustup.sh
RUN chmod 755 /rustup/rustup.sh

ENV USER=xmtp
USER xmtp
RUN /rustup/rustup.sh -y --default-toolchain stable

ENV PATH=$PATH:~xmtp/.cargo/bin

FROM debian:stable-slim
ARG TARGETARCH

RUN export DEBIAN_FRONTEND=noninteractive && \
  apt update && \
  apt install -y -q --no-install-recommends \
    ca-certificates apt-transport-https \
    sudo ripgrep procps build-essential \
    python3 python3-pip python3-dev \
    git curl protobuf-compiler valgrind \
    openssl libssl-dev pkg-config \
    && \
  apt clean && \
  rm -rf /var/lib/apt/lists/*

RUN echo "building platform $(uname -m)"

RUN useradd --create-home -s /bin/bash xmtp
RUN usermod -a -G sudo xmtp
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

## Node and NPM
RUN mkdir -p /usr/local/nvm
ENV NVM_DIR=/usr/local/nvm

ENV NODE_VERSION=v20.9.0

ADD https://raw.githubusercontent.com/creationix/nvm/master/install.sh /usr/local/etc/nvm/install.sh
RUN bash /usr/local/etc/nvm/install.sh && \
    bash -c ". $NVM_DIR/nvm.sh && nvm install $NODE_VERSION && nvm alias default $NODE_VERSION && nvm use default"

ENV NVM_NODE_PATH ${NVM_DIR}/versions/node/${NODE_VERSION}
ENV NODE_PATH ${NVM_NODE_PATH}/lib/node_modules
ENV PATH      ${NVM_NODE_PATH}/bin:$PATH

RUN npm install npm -g
RUN npm install yarn -g

ENV USER=xmtp
## Rust from builder
COPY --chown=${USER}:${USER} --from=builder /home/${USER}/.cargo /home/${USER}/.cargo
COPY --chown=${USER}:${USER} --from=builder /home/${USER}/.rustup /home/${USER}/.rustup
COPY --chown=${USER}:${USER} --from=go-builder /usr/local/go/bin/yamlfmt /usr/local/go/bin/yamlfmt

ENV PATH=/home/${USER}/.cargo/bin:/usr/local/go/bin:$PATH
USER xmtp
RUN rustup toolchain install stable 
RUN rustup component add rustfmt
RUN rustup component add clippy
RUN rustup component add rust-analyzer
RUN cargo --version

LABEL org.label-schema.build-date=$BUILD_DATE \
    org.label-schema.name="rust" \
    org.label-schema.description="Rust Development Container" \
    org.label-schema.url="https://github.com/xmtp/rust" \
    org.label-schema.vcs-ref=$VCS_REF \
    org.label-schema.vcs-url="git@github.com:xmtp/rust.git" \
    org.label-schema.vendor="xmtp" \
    org.label-schema.version=$VERSION \
    org.label-schema.schema-version="1.0" \
    org.opencontainers.image.description="Rust Development Container"
