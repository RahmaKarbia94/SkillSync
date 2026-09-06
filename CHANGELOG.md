# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Support for multi-language assessment prompts
- Analytics dashboard for test administrators
- Peer review assessment type
- Real-time notification system

### Changed
- Improved video upload performance using multipart streaming
- Refactored assessment scoring algorithm for better accuracy
- Updated Flutter dependencies to latest stable versions

### Fixed
- Video upload timeout on slow connections
- Memory leak in video player widget
- JWT token refresh race condition

---

## [1.0.0] - 2026-09-01

### Added
- Initial release of SkillSync platform
- Go backend with REST API
- Flutter cross-platform mobile and desktop app
- AI-powered soft-skills assessment using GROQ
- Video interview capture and storage on AWS S3
- User authentication with JWT tokens
- Assessment creation and management
- Results scoring and analytics
- MongoDB data persistence
- Docker containerization
- Comprehensive documentation

### Security
- Secure S3 bucket configuration with signed URLs
- Input validation and sanitization
- CORS restrictions
- JWT token authentication and refresh

### Documentation
- API documentation with Swagger
- Setup and deployment guides
- Contributing guidelines
- Architecture documentation

---

## Release Notes

### How to Upgrade

1. Pull latest changes: `git pull origin main`
2. Update dependencies:
   - Backend: `cd backend && go mod tidy`
   - Frontend: `cd frontend && flutter pub get`
3. Run tests: `go test ./...` and `flutter test`
4. Rebuild: `docker compose build`

### Support

For issues or questions, please:
- Check [Existing Issues](https://github.com/RahmaKarbia94/SkillSync/issues)
- Create a [New Issue](https://github.com/RahmaKarbia94/SkillSync/issues/new)
- Review [Documentation](https://github.com/RahmaKarbia94/SkillSync/wiki)

---

**Note:** This project follows semantic versioning. Breaking changes only happen in major version updates.
