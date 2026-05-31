#!/usr/bin/env bash
# Server-side deploy for inpres-x (Hostinger, Laravel-in-public_html + SQLite).
# Run via SSH after a git pull / webhook deploy:
#   ssh -p 65002 <user>@<host>
#   cd ~/domains/inpres-x.myappsonline.net/public_html && bash deploy.sh
#
# Webhook auto-runs `git pull` + `composer install` only. This script does the rest:
# env/key, SQLite migrate+seed, caches, and (if node present) front-end build.
set -euo pipefail

echo "==> inpres-x deploy starting"

# 1. .env — create from example on first run (then edit prod values once).
if [ ! -f .env ]; then
  cp .env.example .env
  echo "==> .env created from .env.example — EDIT prod values then re-run"
fi

# 2. APP_KEY — generate if missing.
if ! grep -q "^APP_KEY=base64:" .env; then
  php artisan key:generate --force
fi

# 3. Composer deps (idempotent; webhook may have done this already).
if [ ! -d vendor ]; then
  composer install --no-dev --optimize-autoloader
fi

# 4. SQLite DB — file is gitignored, create it if missing.
if [ ! -f database/database.sqlite ]; then
  touch database/database.sqlite
  echo "==> created empty database/database.sqlite"
fi

# 5. Migrate + seed (demo data lives in seeders, not the .sqlite file).
php artisan migrate --force
php artisan db:seed --force

# 6. storage symlink (Hostinger php exec() disabled → artisan storage:link fails; use ln).
if [ ! -e public/storage ]; then
  ln -s "$(pwd)/storage/app/public" public/storage || true
fi

# 7. Permissions.
chmod -R 775 storage bootstrap/cache || true

# 8. Caches.
php artisan config:cache
php artisan route:cache
php artisan view:cache

# 9. Front-end build (public/build is gitignored). Skip if node absent —
#    fallback: build locally and commit public/build with `git add -f`.
if command -v npm >/dev/null 2>&1; then
  npm install --no-audit --no-fund
  npm run build
else
  echo "==> npm not found — build public/build locally and 'git add -f public/build', then push"
fi

echo "==> inpres-x deploy done"
