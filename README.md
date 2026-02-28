# Gom - Pottery Classification System

## Requirements

- PHP 8.2+
- Composer 2.x
- Python 3.10+
- Flutter 3.x

---

## First-time Setup

### gom-ai

```powershell
cd gom-ai
pip install -r requirements.txt
```

### gom-api

```powershell
cd gom-api
composer install
copy .env.example .env
php artisan key:generate
php artisan migrate
php artisan storage:link
```

### gom_app

```powershell
cd gom_app
flutter pub get
```

---

## Run

Open **three separate terminals**:

**Terminal 1 — AI Server** (`http://localhost:8001`)
```powershell
cd gom-ai
python -m uvicorn main:app --host 0.0.0.0 --port 8001 --reload
```

**Terminal 2 — Laravel API** (`http://localhost:8000`)
```powershell
cd gom-api
php artisan serve --host=0.0.0.0 --port=8000
```

**Terminal 3 — Flutter App** (`http://localhost:8082`)
```powershell
cd gom_app
flutter run -d chrome --web-port 8082
```

> For Android Emulator: `flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000`
