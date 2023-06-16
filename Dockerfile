#### MAIN
FROM ruby:3.1.3-bullseye as main

ENV CARGO_HOME=/usr/local/cargo \
    CARGO_NET_GIT_FETCH_WITH_CLI=true \
    CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse \
    NODE_ENV=development \
    RUSTUP_HOME=/usr/local/rustup \
    SHELL=/bin/bash \
    TMP_DIR=/mnt/tmp \
    WORKDIR=/app

RUN echo "Installing node" \
  && NODE_VERSION='16.19.0' \
  && ARCH= && dpkgArch="$(dpkg --print-architecture)" \
  && case "${dpkgArch##*-}" in \
    amd64) ARCH='x64';; \
    arm64) ARCH='arm64';; \
    *) echo "unsupported architecture -- ${dpkgArch##*-}"; exit 1 ;; \
  esac \
  # gpg keys listed at https://github.com/nodejs/node#release-keys
  && set -ex \
  && for key in \
    4ED778F539E3634C779C87C6D7062848A1AB005C \
    94AE36675C464D64BAFA68DD7434390BDBE9B9C5 \
    74F12602B6F1C4E913FAA37AD3A89613643B6201 \
    71DCFD284A79C3B38668286BC97EC7A07EDE3FC1 \
    8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
    C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8 \
    C82FA3AE1CBEDC6BE46B9360C43CEC45C17AB93C \
    DD8F2338BAE7501E3DD5AC78C273792F7D83545D \
    A48C2BEE680E841632CD4E44F07496B3EB3C1762 \
    108F52B48DB57BB0CC439B2997B01419BD92F80A \
    B9E2F5981AA6E0CD28160D9FF13993A75599653C \
  ; do \
      gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$key" || \
      gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key" ; \
  done \
  && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-$ARCH.tar.xz" \
  && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt.asc" \
  && gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc \
  && grep " node-v$NODE_VERSION-linux-$ARCH.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
  && tar -xJf "node-v$NODE_VERSION-linux-$ARCH.tar.xz" -C /usr/local --strip-components=1 --no-same-owner \
  && rm "node-v$NODE_VERSION-linux-$ARCH.tar.xz" SHASUMS256.txt.asc SHASUMS256.txt \
  && ln -s /usr/local/bin/node /usr/local/bin/nodejs \
  # smoke tests
  && node --version \
  && npm --version

RUN echo 'Installing build dependencies' \
    && apt-get update \
    && apt-get --assume-yes --no-install-recommends install \
        ca-certificates \
        cmake \
        fd-find \
        gcc \
        jq \
        libc6-dev \
        parallel \
        rsync \
        tini \
        wget \
    && echo 'Cleaning up' \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/cache/apt

ENV PATH="${WORKDIR}/bin:${WORKDIR}/node_modules/.bin:${CARGO_HOME}/bin:${PATH}"

WORKDIR ${WORKDIR}

RUN echo "Installing Rust" \
    && RUST_VERSION='1.69.0' \
    && ARCH= && dpkgArch="$(dpkg --print-architecture)" \
    && case "${dpkgArch##*-}" in \
      amd64) ARCH='x86_64-unknown-linux-gnu';; \
      arm64) ARCH='aarch64-unknown-linux-gnu';; \
      *) echo >&2 "unsupported architecture -- ${dpkgArch##*-}"; exit 1 ;; \
    esac \
    && set -eux \
    && mkdir /tmp/rust-install \
    && cd /tmp/rust-install \
    && curl -fsSLO --compressed "https://static.rust-lang.org/rustup/dist/${ARCH}/rustup-init" \
    && curl -fsSLO --compressed "https://static.rust-lang.org/rustup/dist/${ARCH}/rustup-init.sha256" \
    && cat rustup-init.sha256 | awk '{print $1 " *rustup-init"}' > ./checksums.txt \
    && sha256sum --check ./checksums.txt --status \
    && chmod +x ./rustup-init \
    && ./rustup-init -y --no-modify-path --profile default --default-toolchain "${RUST_VERSION}" --default-host "${ARCH}" \
    && echo 'Cleaning up' \
    && cd .. \
    && rm -rfv rust-install \
    && echo 'Smoke test' \
    && cargo --version \
    && rustc --version \
    && rustup --version \
    && echo 'Install wasm23-wasi target' \
    && rustup target add wasm32-wasi \
    && echo 'Done'

ENV npm_config_cache="${TMP_DIR}/npm-cache" \
    npm_config_store_dir="${TMP_DIR}/pnpm-store"

RUN echo "Installing pnpm" \
    && PNPM_VERSION='8.6.1' \
    && npm install -g "pnpm@${PNPM_VERSION}" \
    && echo "====================" \
    && echo "Installing ripgrep" \
    && RIPGREP_VERSION='v13.0.0-4' \
    && ARCH= && dpkgArch="$(dpkg --print-architecture)" \
    && case "${dpkgArch##*-}" in \
      amd64) ARCH='x86_64-unknown-linux-musl';; \
      arm64) ARCH='aarch64-unknown-linux-musl';; \
      *) echo "unsupported architecture -- ${dpkgArch##*-}"; exit 1 ;; \
    esac \
    && set -ex \
    && cd $TMP_DIR \
    && curl -fsSLO --compressed "https://github.com/microsoft/ripgrep-prebuilt/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-${ARCH}.tar.gz" \
    && tar -xf "./ripgrep-${RIPGREP_VERSION}-${ARCH}.tar.gz" \
    && cp -fv ./rg /usr/local/bin \
    && chmod +x /usr/local/bin/rg \
    && echo "Cleaning up" \
    && rm -rf ./ripgrep* \
    && echo "====================" \
    && echo "Installing watchexec" \
    && WATCHEXEC_VERSION='1.22.3' \
    && ARCH= && dpkgArch="$(dpkg --print-architecture)" \
    && case "${dpkgArch##*-}" in \
      amd64) ARCH='x86_64-unknown-linux-musl';; \
      arm64) ARCH='aarch64-unknown-linux-musl';; \
      *) echo "unsupported architecture -- ${dpkgArch##*-}"; exit 1 ;; \
    esac \
    && set -ex \
    && cd $TMP_DIR \
    && curl -fsSLO --compressed "https://github.com/watchexec/watchexec/releases/download/v${WATCHEXEC_VERSION}/watchexec-${WATCHEXEC_VERSION}-${ARCH}.tar.xz" \
    && curl -fsSL "https://github.com/watchexec/watchexec/releases/download/v${WATCHEXEC_VERSION}/SHA512SUMS" | grep $ARCH | grep '.tar.xz' > watchexecsums \
    && sha512sum --check watchexecsums --status \
    && tar -xJf "./watchexec-${WATCHEXEC_VERSION}-${ARCH}.tar.xz" \
    && cp -fv "./watchexec-${WATCHEXEC_VERSION}-${ARCH}/watchexec" /usr/local/bin \
    && chmod +x /usr/local/bin/watchexec \
    && echo "Cleaning up" \
    && rm -rf ./watchexec* \
    && echo "===================" \
    && echo "Installing Hivemind" \
    && HIVEMIND_VERSION='1.0.6' \
    && ARCH= && dpkgArch="$(dpkg --print-architecture)" \
    && case "${dpkgArch##*-}" in \
      amd64) ARCH='amd64';; \
      arm64) ARCH='arm64';; \
      *) echo "unsupported architecture -- ${dpkgArch##*-}"; exit 1 ;; \
    esac \
    && set -ex \
    && cd $TMP_DIR \
    && curl -fsSLO --compressed "https://github.com/DarthSim/hivemind/releases/download/v${HIVEMIND_VERSION}/hivemind-v${HIVEMIND_VERSION}-linux-${ARCH}.gz" \
    && gunzip "./hivemind-v${HIVEMIND_VERSION}-linux-${ARCH}.gz" \
    && cp -fv "./hivemind-v${HIVEMIND_VERSION}-linux-${ARCH}" /usr/local/bin/hivemind \
    && chmod +x /usr/local/bin/hivemind \
    && echo "Cleaning up" \
    && rm -rf ./hivemind* \
    && echo 'Done'
