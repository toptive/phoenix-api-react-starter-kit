# Performance and memory

Budget: **< 150 MB RSS per app, idle, including the SSR worker**, so one 4 GB server hosts
several products next to one shared Postgres (capacity math: [NEW_SERVER.md](NEW_SERVER.md)).

## Measured (production image, 2026-09-30)

Docker image built from this repo (`linux/arm64`, Debian trixie, OTP 28.4, Node 22), against a
local Postgres, 10-core host, container limit 400 MB. The production droplet is x86_64; expect
similar numbers (same flags, same code) and re-measure there after the first deploy with the
commands at the end of this page. RSS / PSS read from `/proc` inside the container.

| Moment | BEAM RSS | Node (SSR) RSS | Total RSS | Total PSS |
|---|---|---|---|---|
| Idle after boot | 68 MB | 44 MB | 112 MB | 97 MB |
| After warm-up (225 requests, public pages SSR) | 81 MB | 57 MB | 138 MB | 123 MB |
| After 3,000 more SSR renders of `/` | 85 MB | 64 MB | 149 MB | 134 MB |
| Idle 60 s later | 73 MB | 32 MB | **105 MB** | 91 MB |

No growth across 3,000 renders: the Node heap is collected back to 32 MB. SSR latency for `/`:
p50 7 ms, p95 13 ms.

Before tuning, the same image idled at **219 MB** for the BEAM alone.

## What made the difference

| Setting | Where | Effect |
|---|---|---|
| `RELEASE_MODE=interactive` | `Dockerfile` | Modules load on first use instead of all ~2,400 at boot: code memory 49 MB → 16 MB (≈570 modules after warm-up). The first request after a boot takes ~0.2 s while its modules load; later requests are unaffected. |
| `+S 2:2 +SDcpu 2:2 +SDio 4` | `rel/vm.args.eex` | Each scheduler owns allocator instances; on a 10-core host the default 10 schedulers cost ~100 MB of carriers. |
| `+P 65536 +Q 16384` | `rel/vm.args.eex` | Smaller process and port tables. |
| `+MBas aobf +MHas aobf +MMscs 0` | `rel/vm.args.eex` | Allocation strategy that returns carriers sooner. |
| `+sbwt none` (×3) | `rel/vm.args.eex` | No busy-waiting schedulers (CPU for the other apps on the box). |
| `NODE_ENV=production` | `Dockerfile` | **The wainbox leak**: without it the `nodejs` worker re-requires the SSR bundle on every render and never frees the old copies. |
| `NODE_OPTIONS=--max-old-space-size=64 --max-semi-space-size=1` | `Dockerfile` | Caps the SSR heap. |
| One SSR worker (`SSR_POOL_SIZE=1`) | `config/runtime.exs` | The library default is 4. |
| SSR only on public pages | `render_public/3` | Signed-in traffic never touches Node. |
| SSR bundle: React production build, minified, `noExternal` | `vite.config.ts` | 1 MB self-contained CommonJS file; no `node_modules` in the image. |
| tini as PID 1 | `Dockerfile` | Reaps crashed Node workers. |
| `/health` = `SELECT 1` | `HealthController` | The kamal-proxy check never renders a page. |

Tried and rejected: `--jitless` for Node (43 MB instead of 64 MB, but SSR p95 went from 13 ms to
178 ms); `--lite-mode` (not allowed in `NODE_OPTIONS`); one scheduler (no gain over two).

On OTP 28 a regex compiled at build time and kept in a module attribute (`@name ~r/…/`) is
recompiled on every use (whvisas: a 10 s batch became 0.6 s without it). Keep the source in the
attribute and compile it once at runtime into `:persistent_term` (`Plugs.PageViews.bots/0`);
`credo/no_regex_attribute.ex` fails the build otherwise.

Raise the schedulers for a CPU-heavy product with `ERL_AFLAGS="+S 4:4"`, and `SSR_POOL_SIZE`
only when SSR requests queue.

## Front end

Lighthouse 13 on the landing page served by the production image (median of 5 runs):

| | Performance | Accessibility | Best practices | SEO |
|---|---|---|---|---|
| Mobile (simulated slow 4G, 4× CPU) | 98 (FCP 1.8 s, LCP 2.0 s, CLS 0) | 100 | 100 | 100 |
| Desktop | 99 | 100 | 100 | 100 |

What keeps it there: SSR HTML (13 KB gzipped, including the i18n catalogue), one 23 KB CSS file,
the body font preloaded (27 KB), layouts and the toast library loaded lazily, tooltips only in the
signed-in shells, hashed assets cached for a year and served pre-compressed.

Re-measure after big changes: build the image, run it, and run
`pnpm dlx lighthouse http://localhost:4100/ --chrome-flags="--headless=new"`.

## Measuring memory

```sh
docker exec <container> sh -c 'for p in /proc/[0-9]*; do n=$(tr "\0" " " < $p/cmdline | cut -c1-40); r=$(awk "/VmRSS/{print \$2}" $p/status 2>/dev/null); [ -n "$r" ] && echo "$((r/1024)) MB $n"; done'
docker exec <container> /app/bin/starter_kit rpc 'IO.inspect(:erlang.memory())'
```
