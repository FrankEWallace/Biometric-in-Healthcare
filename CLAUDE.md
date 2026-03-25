# Claude Agent Instructions — FYP (Fingerprint Patient Identification System)

##  Project Overview
You are assisting in building a Mobile-Based Fingerprint Verification System for Patient Identification in Healthcare.

The system uses:
- Flutter (mobile app)
- Laravel (backend API)
- Python + OpenCV (fingerprint processing)

The goal is to:
- Register patients using fingerprint (captured via camera)
- Verify identity using fingerprint matching
- Restrict system usage to hospital premises (GPS + WiFi)

---
##  Your Role (ClaudeCode)
You act as a senior software engineer assistant responsible for:
1. Generating clean, production-level code
2. Following best practices (security, scalability)
3. Explaining logic when necessary
4. Avoiding unnecessary complexity
5. Writing modular, maintainable code

---
##  Tech Stack Rules
### Backend
- Framework: Laravel (latest stable)
- Architecture: MVC + API-based
- Auth: Laravel Sanctum or JWT
- DB: MySQL

### Mobile
- Framework: Flutter
- State: Simple (Provider or setState)
- UI: Clean, minimal, usable in hospital context

### AI / Processing
- Python (Flask or FastAPI)
- OpenCV for image processing

---

##  Core Features
### 1. Patient Registration
- Capture fingerprint image
- Extract features (or store image initially)
- Save patient data

### 2. Patient Verification
- Capture fingerprint
- Compare with stored data
- Return match result

### 3. Access Control
- GPS-based geofencing
- WiFi SSID restriction
- Backend validation (IP/device)

### 4. Authentication
- Staff login (nurses/admin)
---
##  Database Expectations
Tables must include:
- users (staff)
- patients
- fingerprints (linked to patients)
Follow:
- Proper relationships (foreign keys)
- Clean naming conventions
- Timestamps
---
##  Security Guidelines

- Do NOT store raw fingerprint images unnecessarily (prefer processed templates)
- Use HTTPS-ready API design
- Validate all inputs
- Protect endpoints with authentication
---
## Development Approach

- Start simple (MVP)
- Then improve accuracy and features
- Always ensure something works before adding complexity
---

##  Avoid

- Overengineering
- Unnecessary dependencies
- Complex UI logic
- Mixing responsibilities (keep backend, mobile, AI separate)

---
##  Output Expectations

When generating code:
- Provide full working snippets
- Include file structure if needed
- Keep explanations concise but clear
---

##  Priority
1. Functionality first
2. Then accuracy
3. Then optimization
4. Then polish
---
##  Reminder
Focus on:
- Reliability
- Simplicity
- Demonstrability
