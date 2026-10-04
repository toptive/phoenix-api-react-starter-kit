# Products server (DigitalOcean, 4 GB)

Facundo runs these steps; Claude never runs commands on servers. One droplet hosts several
products: one Docker network (`kamal`), one shared Postgres with one database per app, one
kamal-proxy doing TLS for every domain.

| | |
|---|---|
| Droplet | `toptive-products-nyc3-01` — `s-2vcpu-4gb` (2 vCPU, 4 GB RAM, x86_64), Ubuntu 24.04, region nyc3 |
| Public IP | `209.97.156.205` (in `config/deploy.yml`) |
| Private IP | `10.108.32.2`, VPC `toptive-products-nyc3` (`10.108.32.0/20`) |
| Cloud firewall | `toptive-products-web`: inbound 22, 80, 443 |

The droplet and the firewall already exist. The steps below prepare it once; §5 and §7 repeat
for every new product.

## Capacity (4 GB)

| Consumer | Memory |
|---|---|
| Ubuntu, Docker, DO monitoring agent | ~350 MB |
| kamal-proxy | ~30 MB |
| Postgres 17 (tuned below, capped at 1.2 GB) | ~1 GB |
| **Left for apps** | **~2.5 GB** |

Budget each API app at up to 150 MB idle; measure production workloads
([PERFORMANCE.md](PERFORMANCE.md)); each container is capped at 400 MB (`deploy.yml`).
Keeping a third of the RAM free for peaks and the page cache: **plan for about 10 small products**
on this droplet (2.5 GB × ⅔ ÷ 150 MB ≈ 11). The 2 GB swap file is a safety net, not capacity.
Database connections follow the same math: 10 apps × `POOL_SIZE` 8 = 80 of Postgres's 100.

Resize the droplet (or add a second one in the same VPC) before either number is reached. Watch
memory in the DigitalOcean graphs (§9).

## 1. DNS

For every product domain: an `A` record → `209.97.156.205` (add `AAAA` only if IPv6 is enabled
on the droplet). With Cloudflare, keep the record **DNS only** (grey cloud) for the first deploy
so Let's Encrypt can issue the certificate; you can proxy it later with SSL mode "Full (strict)".

## 2. Firewall

`toptive-products-web` is fine as is (22, 80, 443). Recommended: restrict port 22 to your own IP
addresses in the DigitalOcean console. Never open 5432: Postgres stays on the Docker network.

## 3. Base system

```sh
ssh root@209.97.156.205

apt update && apt -y full-upgrade
apt -y install unattended-upgrades fail2ban
dpkg-reconfigure -f noninteractive unattended-upgrades

# DigitalOcean droplets have no swap: add 2 GB as a safety net
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
sysctl -w vm.swappiness=10 && echo 'vm.swappiness=10' > /etc/sysctl.d/99-swappiness.conf

# SSH: keys only
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl reload ssh

# Memory and disk graphs in the DigitalOcean console (skip if "Monitoring" was ticked at creation)
curl -sSL https://repos.insights.digitalocean.com/install.sh | bash

# Docker (Kamal would install it too; doing it now lets us start Postgres first)
curl -fsSL https://get.docker.com | sh
docker network create kamal
```

## 4. Shared Postgres 17

Tuned for a 4 GB droplet shared with the apps:

```sh
mkdir -p /opt/postgres && openssl rand -base64 32 > /opt/postgres/superuser_password && chmod 600 /opt/postgres/superuser_password

docker run -d --name postgres --restart unless-stopped --network kamal \
  --memory 1200m \
  -p 127.0.0.1:5432:5432 \
  -v postgres_data:/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD_FILE=/run/secrets/pg -v /opt/postgres/superuser_password:/run/secrets/pg:ro \
  postgres:17 \
  -c shared_buffers=512MB -c effective_cache_size=1GB -c work_mem=4MB \
  -c maintenance_work_mem=64MB -c max_connections=100
```

Apps reach it as `postgres:5432` on the `kamal` network. Port 5432 is bound to localhost only
(for SSH tunnels: `ssh -L 5432:127.0.0.1:5432 root@209.97.156.205`), never public. A second
droplet in the VPC can later reach it on the private IP `10.108.32.2` if you publish it there
(`-p 10.108.32.2:5432:5432`) — do that only with a VPC-only firewall rule.

## 5. One database per product

Repeat for each product (`APP` = the app name after `bin/rename`, e.g. `visa_hub`):

```sh
APP=visa_hub
PASS=$(openssl rand -hex 24)
docker exec -i postgres psql -U postgres <<SQL
CREATE ROLE $APP LOGIN PASSWORD '$PASS';
CREATE DATABASE $APP OWNER $APP;
REVOKE CONNECT ON DATABASE $APP FROM PUBLIC;
SQL
echo "DATABASE_URL=ecto://$APP:$PASS@postgres:5432/$APP"   # store it in 1Password
```

The app role owns only its database; the first migration creates the `citext` extension (a
trusted extension, so the owner may create it).

## 6. Backups

Two layers:

1. **Droplet backups**: DigitalOcean console → the droplet → Backups → enable (weekly, or daily).
   Whole-disk snapshots; they restore the server, not a single database.
2. **Nightly logical dumps** of every database to **DigitalOcean Spaces** (bucket
   `toptive-backups` in nyc3, private; or any other S3-compatible storage). Create a Spaces access
   key limited to that bucket. On the droplet:

```sh
curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc && chmod +x /usr/local/bin/mc
mc alias set spaces https://nyc3.digitaloceanspaces.com SPACES_KEY SPACES_SECRET

# keep 30 days of dumps
mc ilm rule add --expire-days 30 spaces/toptive-backups

cat > /usr/local/bin/pg-backup <<'SH'
#!/bin/sh
set -eu
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
for DB in $(docker exec postgres psql -U postgres -Atc "SELECT datname FROM pg_database WHERE datname NOT IN ('postgres','template0','template1')"); do
  docker exec postgres pg_dump -U postgres -Fc "$DB" | mc pipe "spaces/toptive-backups/products-nyc3-01/$DB/$STAMP.dump"
done
SH
chmod +x /usr/local/bin/pg-backup
echo '15 7 * * * root /usr/local/bin/pg-backup >> /var/log/pg-backup.log 2>&1' > /etc/cron.d/pg-backup
```

(07:15 UTC is 03:15 in New York.) Test a restore once into a scratch database:
`mc cat spaces/toptive-backups/products-nyc3-01/<db>/<stamp>.dump | docker exec -i postgres pg_restore -U postgres -d <scratch_db>`.

## 7. Spaces bucket for a product's uploads

DigitalOcean console → Spaces → create a bucket per product in nyc3 (`<app>-uploads`, file
listing **restricted**) and an access key limited to it. In `config/deploy.yml`:
`S3_BUCKET: <app>-uploads`, `S3_ENDPOINT: https://nyc3.digitaloceanspaces.com`,
`S3_REGION: us-east-1` (the signing region SDKs use for Spaces); the key pair goes in the secrets
(`S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`). Bucket → Settings → CORS: allow `PUT` from
`https://<domain>` with header `Content-Type` (browser direct uploads).

## 8. First deploy of a product

From the product repo on your machine: `kamal setup` (installs kamal-proxy and the app, issues
the certificate; the image is pushed through Kamal's local registry over SSH). On an
Apple-silicon Mac the image is cross-built for amd64 ([DEPLOY.md](DEPLOY.md)). Then `/deploy`
for every later deploy.

## 9. Monitoring

- DigitalOcean console → droplet → Graphs (memory, disk, CPU), and Monitoring → Alerts:
  memory > 85 % for 10 min, disk > 80 %.
- On the droplet: `docker stats --no-stream` shows memory per app.
- Sentry per product (`SENTRY_DSN`).
