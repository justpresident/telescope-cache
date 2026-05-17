# Test environment for telescope-cache.nvim
#
# This image contains everything required to run the test suite. The repo
# itself is NOT copied in — mount it at /workspace at runtime. That keeps
# rebuilds rare and source iteration fast.
#
# Build:    docker build -t telescope-cache-tests .
# Run:      docker run --rm -v "$(pwd):/workspace" telescope-cache-tests
# Override: docker run --rm -v "$(pwd):/workspace" telescope-cache-tests make test-all

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies. Versions track Ubuntu 24.04 (noble) and match the
# packages installed in .github/workflows/tests.yml.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      make \
      build-essential \
      libsqlcipher1 \
      libsqlcipher-dev \
      sqlite3 \
      luarocks \
    && rm -rf /var/lib/apt/lists/*

# Neovim 0.9 from apt is too old for current telescope (telescope master
# uses vim.uv / vim.iter / other 0.10+ APIs). Pull the latest stable tarball
# to match what rhysd/action-setup-vim installs in CI.
RUN curl -fsSL \
      https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz \
      | tar -xz -C /opt \
 && ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim

# Lua dependencies and the busted-compatible test runner used by `make test`.
RUN luarocks install luafilesystem \
 && luarocks install vusted

# Plugin runtime dependencies. Cloning into the default Neovim pack dir means
# both plenary (testing framework) and telescope (host plugin) are picked up
# automatically from runtimepath.
ENV NVIM_PACK_DIR=/root/.local/share/nvim/site/pack/deps/start
RUN mkdir -p ${NVIM_PACK_DIR} \
 && git clone --depth 1 https://github.com/nvim-lua/plenary.nvim \
      ${NVIM_PACK_DIR}/plenary.nvim \
 && git clone --depth 1 https://github.com/nvim-telescope/telescope.nvim \
      ${NVIM_PACK_DIR}/telescope.nvim \
 && mkdir -p /opt/nvim-plugins \
 && ln -s ${NVIM_PACK_DIR}/plenary.nvim   /opt/nvim-plugins/plenary.nvim \
 && ln -s ${NVIM_PACK_DIR}/telescope.nvim /opt/nvim-plugins/telescope.nvim

WORKDIR /workspace

# Default to the primary test target; override with any `make <target>`.
CMD ["make", "test"]
