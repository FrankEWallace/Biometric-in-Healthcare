# Dev Commands Reference

Quick reference for running every part of the stack locally. Run each service in its own terminal tab.

## 1. MySQL

Make sure MySQL is running (MAMP, Homebrew, or Docker) on port 3306 with a `bih_db` database matching `laravel/.env`.

## 2. Python microservice (fingerprint + face processing)

```bash
cd python-service
source venv/bin/activate      # or .venv/bin/activate depending on which exists
python run.py
```
Runs on `http://localhost:5001`. Docs at `http://localhost:5001/docs`.

## 3. Laravel API

```bash
cd laravel
php artisan serve
```
Runs on `http://localhost:8000` (matches `APP_URL` in `laravel/.env`). First time / after pulling changes:
```bash
composer install
php artisan migrate
npm install && npm run dev   # Vite, only needed for the legacy Blade dashboard assets
```

## 4. Web admin (Next.js)

```bash
cd web-admin
npm install
npm run dev
```
Runs on `http://localhost:3000`. Points at the API via `NEXT_PUBLIC_API_URL` in `web-admin/.env.local` (build-time env, restart dev server after changing).

## 5. Flutter mobile app

List connected devices:
```bash
cd mobile
flutter devices
```

**Always point release builds at the deployed backend**, not the local default (`AppConfig.baseUrl` in `lib/config/app_config.dart` falls back to a placeholder otherwise):

```bash
# Release build on a connected iOS device
flutter run --release --dart-define=API_BASE_URL=https://fyp.fwtechnologies.co.tz/api -d <device-id>

# Release build on a connected Android device
flutter run --release --dart-define=API_BASE_URL=https://fyp.fwtechnologies.co.tz/api -d <device-id>

# Debug against local Laravel instead (device must reach your Mac's LAN IP, not localhost)
flutter run --dart-define=API_BASE_URL=http://<your-mac-lan-ip>:8000/api -d <device-id>
```

First-time iOS device setup: on the phone, go to **Settings → General → VPN & Device Management** and trust the developer profile after the first install attempt, or the app will fail to launch with a code-signing error.

## 6. Full stack via Docker (mirrors production)

```bash
docker compose up --build
```
Brings up `mysql`, `python-service`, `laravel`, and `web-admin` together per `docker-compose.yml`. Requires `.env` (root), `laravel/.env`, and `python-service/.env` to be filled in — see each service's `.env.example`.

## Production (VPS)

Deploys automatically on push to `main`. To check/redeploy manually:
```bash
ssh wallace@94.72.98.83
cd /home/wallace/Biometric-in-Healthcare
git pull --ff-only
docker compose build && docker compose up -d
```
Live at `https://fyp.fwtechnologies.co.tz`.
