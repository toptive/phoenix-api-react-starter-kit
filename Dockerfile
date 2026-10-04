# syntax=docker/dockerfile:1
#
# Release image: Phoenix release with the built React SPA.
# docs/DEPLOY.md explains each choice; docs/PERFORMANCE.md the memory numbers.
#
#   builder — Elixir, Node, pnpm; builds the Vite SPA and the release
#   runner  — Debian slim + the release (no Node or node_modules) + tini

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
COPY vendor/typelizer vendor/typelizer
RUN if grep -Eq 'path: "\.\./typelizer-ex"' mix.exs; then \
      echo "typelizer path dependency cannot be built in Docker: use Hex or vendor/typelizer (docs/DEPLOY.md)" >&2; exit 1; \
    fi
RUN mix deps.get --only prod && mkdir config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

COPY priv priv
COPY lib lib
COPY i18n i18n
COPY frontend frontend

RUN mix compile
# Vite and prerendering write HTML and hashed assets to priv/static.
ARG VITE_API_URL=""
ARG VITE_PUBLIC_URL="https://CHANGE_ME.example.com"
ARG VITE_SITE_INDEXING="0"
ARG VITE_PRERENDER_API_URL=""
RUN VITE_API_URL="$VITE_API_URL" VITE_PUBLIC_URL="$VITE_PUBLIC_URL" \
    VITE_SITE_INDEXING="$VITE_SITE_INDEXING" VITE_PRERENDER_API_URL="$VITE_PRERENDER_API_URL" \
    NODE_ENV=production pnpm build \
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

WORKDIR /app
RUN chown nobody /app

ENV MIX_ENV=prod \
    PHX_SERVER=true \
    # Load modules on first use instead of all ~2400 at boot: -50 MB of code memory.
    RELEASE_MODE=interactive

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/starter_kit ./

USER nobody

EXPOSE 4000
# tini forwards signals and reaps release subprocesses.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/app/bin/launch"]
