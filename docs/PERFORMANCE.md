# Performance and memory

Target: under 150 MB idle RSS per app with a 400 MB container cap. Measure the current
production image after deploy; historical measurements from a different rendering stack
are not a baseline for this API and SPA.

## Runtime budget

The release runs BEAM only. Node and pnpm build the SPA in the Docker builder.
`RELEASE_MODE=interactive` loads modules on demand. `rel/vm.args.eex` limits scheduler,
process and port table overhead; raise schedulers with `ERL_AFLAGS` for a CPU-heavy product.
Oban concurrency stays below the database pool. `/health` checks the database without
rendering a page. `tini` forwards signals and reaps subprocesses.

Avoid compiled regexes in module attributes; the custom Credo gate enforces this.

## Browser performance

Landing pages are prerendered by `pnpm build`. Route pages are loaded lazily. Vite emits
hashed assets cached for a year and the image precompresses them. HTML remains uncached
because Phoenix adds a bootstrap CSP nonce. Keep fonts self-hosted and preload only critical files.

Measure after significant changes with Lighthouse against the production image:
`pnpm dlx lighthouse http://localhost:4100/ --chrome-flags="--headless=new"`.
Targets: mobile performance at least 95 and accessibility, best practices and SEO at least 95.

## Memory measurement

Facundo can inspect the container with `docker stats --no-stream <container>` and
`docker exec <container> /app/bin/starter_kit rpc 'IO.inspect(:erlang.memory())'`.
