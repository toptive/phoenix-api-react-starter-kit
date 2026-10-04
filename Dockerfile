# syntax=docker/dockerfile:1
#
# Release image: Phoenix release + the Node binary for Inertia SSR (public pages only).
# docs/DEPLOY.md explains each choice; docs/PERFORMANCE.md the memory numbers.
#
#   builder — Elixir, Node, pnpm; builds the Vite client + SSR bundles and the release
#   runner  — Debian slim + the release + `node` (no npm, no node_modules) + tini

ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.4.3
ARG DEBIAN_VERSION=trixie-20260824-slim
ARG NODE_VERSION=22

FROM docker.io/node:${NODE_VERSION}-trixie-slim AS node

FROM docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION} AS builder

RUN apt-get update -y && apt-get install -y --no-install-recommends build-essential git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack \
  && corepack enable pnpm

WORKDIR /app
# Build-stage BEAM flags (config/deploy.yml builder.args): the emulated amd64 build on
# Apple silicon needs "+JMsingle true". Empty keeps the OTP defaults; the runner never sees it.
ARG ERL_FLAGS=""
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mkdir config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

COPY priv priv
COPY lib lib
COPY i18n i18n
COPY assets assets
COPY vite.config.ts tsconfig.json components.json ./

RUN mix compile
# Client bundle → priv/static/assets, SSR bundle → priv/ssr/ssr.js (self-contained)
RUN NODE_ENV=production pnpm build \
  && find priv/static -type f \( -name '*.js' -o -name '*.css' -o -name '*.svg' -o -name '*.json' \) -exec gzip -k -9 {} \;

COPY config/runtime.exs config/
COPY rel rel
RUN mix release

FROM docker.io/debian:${DEBIAN_VERSION} AS runner

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates tini \
  && rm -rf /var/lib/apt/lists/* \
  && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# Only the node binary: the SSR bundle carries its own dependencies.
COPY --from=node /usr/local/bin/node /usr/local/bin/node

WORKDIR /app
RUN chown nobody /app

ENV MIX_ENV=prod \
    PHX_SERVER=true \
    # Load modules on first use instead of all ~2400 at boot: -50 MB of code memory.
    RELEASE_MODE=interactive \
    # nodejs workers cache the SSR bundle only in production mode (without it, every
    # render re-requires the bundle and memory grows without bound).
    NODE_ENV=production \
    NODE_OPTIONS="--max-old-space-size=64 --max-semi-space-size=1"

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/starter_kit ./

USER nobody

EXPOSE 4000
# tini is PID 1: forwards signals and reaps SSR Node processes.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/app/bin/server"]
