FROM mcr.microsoft.com/devcontainers/base:bookworm

ARG GO_VERSION=1.24.6
ENV GOPATH=/go
ENV PATH=$GOPATH/bin:/usr/local/go/bin:$PATH
ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    build-essential \
    git \
    unzip \
    python3 \
    python3-pip \
    postgresql-client \
    wget \
 && rm -rf /var/lib/apt/lists/*

RUN rm -rf /usr/local/go \
 && curl -fsSL https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz -o /tmp/go.tgz \
 && tar -C /usr/local -xzf /tmp/go.tgz \
 && rm /tmp/go.tgz

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
 && apt-get update \
 && apt-get install -y --no-install-recommends nodejs \
 && npm install -g pnpm \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p ${GOPATH}/bin ${GOPATH}/pkg/mod /root/.cache/go-build \
 && chown -R vscode:vscode ${GOPATH} /root/.cache/go-build

USER vscode

WORKDIR /workspace
