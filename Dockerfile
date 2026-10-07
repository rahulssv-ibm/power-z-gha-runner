# Copyright (c) 2021 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
ENV INSTALL_IN_GOPATH=false
# Required for libxml2-dev
ENV TZ=Etc/UTC

# Install docker and required dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        docker.io \
        curl \
        make \
        git \
        wget \
        sudo && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
