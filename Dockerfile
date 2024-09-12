#syntax=docker/dockerfile:1.9

FROM ghcr.io/cloudnative-pg/postgresql:17rc1-4-bookworm

USER root

ARG POSTGRES_VERSION=16
ARG TIMESCALE_VERSION
ARG PGRX_VERSION=0.10.2

ENV PGRX_HOME=/usr/local/pgrx
ENV PATH="${PGRX_HOME}/bin:${PATH}"

RUN <<EOT
  set -eux

  # Install dependencies
  apt-get update
  apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    build-essential \
    git \
    postgresql-server-dev-$POSTGRES_VERSION \
    libssl-dev \
    libkrb5-dev \
    pkg-config

  # Install Rust and Cargo
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  . $HOME/.cargo/env

  # Install specific version of pgrx
  cargo install cargo-pgrx --version $PGRX_VERSION --locked

  # Manually set up pgrx configuration
  mkdir -p $PGRX_HOME
  echo "[pg_config_paths]" > $PGRX_HOME/config.toml
  echo "pg$POSTGRES_VERSION = \"/usr/lib/postgresql/$POSTGRES_VERSION/bin/pg_config\"" >> $PGRX_HOME/config.toml

  # Initialize pgrx
  cargo pgrx init --pg$POSTGRES_VERSION /usr/lib/postgresql/$POSTGRES_VERSION/bin/pg_config

  # Add Timescale apt repo
  . /etc/os-release 2>/dev/null
  echo "deb https://packagecloud.io/timescale/timescaledb/debian/ $VERSION_CODENAME main" >/etc/apt/sources.list.d/timescaledb.list
  curl -Lsf https://packagecloud.io/timescale/timescaledb/gpgkey | gpg --dearmor >/etc/apt/trusted.gpg.d/timescale.gpg

  # Install Timescale
  apt-get update
  apt-get install -y --no-install-recommends \
    "timescaledb-2-postgresql-$POSTGRES_VERSION=$TIMESCALE_VERSION~debian$VERSION_ID" \

  # Build and install TimescaleDB Toolkit
  git clone https://github.com/timescale/timescaledb-toolkit
  cd timescaledb-toolkit/extension
  cargo pgrx install --release
  cargo run --manifest-path ../tools/post-install/Cargo.toml -- pg_config

  # Cleanup
  cd /
  rm -rf timescaledb-toolkit
  rm -rf $HOME/.cargo $HOME/.rustup
  apt-get purge -y curl gnupg build-essential git postgresql-server-dev-$POSTGRES_VERSION pkg-config
  apt-get autoremove -y
  rm /etc/apt/sources.list.d/timescaledb.list /etc/apt/trusted.gpg.d/timescale.gpg
  rm -rf /var/cache/apt/*
EOT

# Creates a bootstrap script to enable extensions
COPY <<EOF /docker-entrypoint-initdb.d/enable-extensions.sql
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS plpgsql;
EOF

USER 26
