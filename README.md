# SkillSync

AI-powered asynchronous soft-skills assessment platform. Go/MongoDB backend, Flutter frontend.

## Backend
```
cd backend
cp .env.example .env   # fill in GROQ_API_KEY, JWT_SECRET, AWS_*/MinIO creds
docker compose up --build
```

## Frontend
Platform folders (`android/`, `ios/`, `windows/`, `macos/`, `linux/`, `web/`) are intentionally not included — they're toolchain-generated and must be created locally from `pubspec.yaml`, which this package does include:
```
cd frontend
flutter create .
flutter pub get
flutter run
```
`flutter create .` generates those folders in place without touching `lib/` or `pubspec.yaml`.
