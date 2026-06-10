# Implementation Report — Mobile-Based Biometric Patient Identification System

**Project:** Fingerprint and Face Patient Identification System for Healthcare
**Architecture:** Flutter mobile client · Laravel 11 REST API · Python (FastAPI) biometric microservice · MySQL 8
**Document purpose:** A plain-language but academically structured explanation of how the whole system is implemented.

---

## 1. Introduction

Patient misidentification is a recognised and persistent source of clinical error. When a patient is identified by an ID card, a wristband, or a verbal exchange, the identifier can be lost, swapped, or misheard. This project replaces that fragile link with a *biometric* one: the patient's own body — their face and fingerprint — becomes the credential that ties them to their medical record.

The system is designed for use *inside a hospital* by clinical staff (nurses, doctors, administrators). A nurse points a smartphone camera at the patient, the application captures a biometric sample, and the backend answers a single question: **"Which patient is this, and how confident are we?"** Crucially, the system never *automatically rejects or accepts* a patient on a borderline result — it escalates ambiguous cases to a human, which is the responsible design for a clinical setting.

This document explains, layer by layer, how that pipeline is built.

---

## 2. System Architecture

The system is divided into three independently deployable services. This separation follows the *separation of concerns* principle: each service has one responsibility and can be developed, tested, and scaled on its own.

```
┌─────────────────────────┐
│   Flutter Mobile App    │   Staff-facing UI (Android / iOS)
│  - Auto-trigger capture │   Captures samples, enforces on-site use
│  - GPS + WiFi gate      │
└────────────┬────────────┘
             │  HTTPS / JSON  (authenticated with a bearer token)
             ▼
┌─────────────────────────┐
│   Laravel 11 REST API   │   The "brain" — all decisions live here
│  - Sanctum token auth   │   Authentication, authorisation, audit,
│  - Role + hospital gate │   business rules, the decision matrix
└────────────┬────────────┘
             │  Internal HTTP (localhost only, never public)
             ▼
┌─────────────────────────┐
│  FastAPI Microservice   │   The "eyes" — raw image → numbers
│  - OpenCV fingerprint   │   Feature extraction and similarity search
│  - FAISS face search    │
└────────────┬────────────┘
             ▼
        MySQL 8 Database
```

**Why three services and not one?** Biometric processing needs Python's scientific stack (OpenCV, NumPy, InsightFace, FAISS). Clinical workflow, permissions, and audit are best expressed in Laravel. The mobile layer must run natively on a phone. Forcing all three into one codebase would couple unrelated concerns and make each harder to reason about. The microservice is *never* exposed to the public internet — only Laravel may talk to it, over localhost.

---

## 3. The Mobile Client (Flutter)

The mobile application is the only part staff ever see. It is responsible for three things: **capturing a good sample**, **enforcing on-premises use**, and **presenting the result clearly**.

### 3.1 Capture
Fingerprints and faces are captured with the ordinary smartphone camera — no dedicated scanner hardware. To get usable samples from a hand-held camera, the app uses an **auto-trigger** approach: instead of asking the nurse to press a button at exactly the right moment, the app continuously inspects the live camera stream and fires the capture automatically when image quality is acceptable (in focus, well-lit, correctly framed). This removes a major source of human-introduced blur. The capture screens live in `mobile/lib/screens/fingerprint/`, `.../face/`, and `.../camera_screen.dart`.

### 3.2 On-premises enforcement (geofencing + WiFi)
Two client-side gates restrict the app to hospital grounds:
- **GPS geofencing** — the device's coordinates are compared against the hospital's configured perimeter (`location_service.dart`).
- **WiFi SSID restriction** — the app reads the connected network name via `network_info_plus` and only proceeds on the designated hospital network (`network_service.dart`).

These are **convenience controls, not a security boundary**. A determined attacker can spoof GPS or SSID, so the backend independently validates request context. This layered stance (defence in depth) is standard security practice.

### 3.3 Configuration
The API address and test bypasses are injected at build time with Flutter's `--dart-define` flags rather than hard-coded, so the same source builds for development, staging, and production without edits.

---

## 4. The Application Backend (Laravel 11)

Laravel is the decision-making centre. The mobile app holds *no* authority — every rule is enforced here.

### 4.1 Authentication and authorisation
- **Authentication** uses **Laravel Sanctum**, which issues a per-session bearer token at login and revokes it at logout.
- **Authorisation** is enforced by two middleware layers applied at the route level:
  - `role:` middleware restricts each endpoint to permitted roles.
  - `hospital.access` middleware enforces **multi-tenant isolation** — a user from Hospital A can never read or modify Hospital B's data.

There are four roles, each with progressively narrower clinical access:

| Role | Scope | Representative permissions |
|------|-------|----------------------------|
| `super_admin` | Cross-hospital | Manage hospitals and users; **no clinical data access** |
| `admin` | Own hospital | Manage staff, edit demographics, approve edit requests, unlock fingerprints |
| `doctor` | Own hospital | Read-only access to records, EHR, and logs |
| `nurse` | Own hospital | Register patients, enrol biometrics, run verification |

### 4.2 Audit and accountability
A dedicated `AuditLog` service records *who* did *what* to *which* resource and *when*, for every sensitive action — including manual face-match confirmations. The log is append-only, which is essential for clinical and legal accountability.

### 4.3 Edit-request workflow
Nurses cannot silently change patient demographics. They submit an **edit request** that an administrator must approve or reject. This preserves data integrity and creates a reviewable trail.

### 4.4 Rate limiting
Login (10/min/IP), enrollment (20/min/token), and verification (30/min/token) are rate-limited to blunt brute-force and abuse.

---

## 5. The Biometric Microservice (Python / FastAPI)

This service turns raw images into comparable numbers. It exposes a small internal HTTP API consumed only by Laravel.

### 5.1 Fingerprint pipeline (contactless, camera-based)

A camera photograph of a fingertip is *not* a clean scanner image — it has uneven lighting, variable scale, and rotation. The pipeline (`minutiae_service.py`, `image_processor.py`) progressively cleans the image and then extracts the features that uniquely identify a fingerprint:

```
grayscale
 → 5×5 Gaussian blur
 → CLAHE  (Contrast-Limited Adaptive Histogram Equalisation)   [Zuiderveld, 1994]
 → 8-orientation Gabor filter bank  (ridge enhancement)        [Hong et al., 1998]
 → adaptive threshold → binary image
 → morphological open/close  (remove speckle, close gaps)
 → iterative thinning  (reduce ridges to 1-pixel skeleton)
 → minutiae extraction via the crossing-number method          [Maltoni et al., 2009]
 → centroid + RMS-scale normalisation
 → rotation search (24 steps) + spatial matching
```

Because the fingerprint pipeline is fundamentally a **strictly ordered chain of transformations** — each stage consumes the output of the one before it — it is best represented as a **sequence flow** rather than a static block diagram. The flow below (suitable for rendering with Mermaid in a report) traces a single fingertip photograph from raw capture through to a final 0–100 match score:

```mermaid
flowchart LR
    A[Grayscale] --> B[5×5 Gaussian Blur]
    B --> C["CLAHE<br/>(contrast)"]
    C --> D["8-orientation<br/>Gabor filter bank"]
    D --> E[Adaptive Threshold]
    E --> F[Morphological<br/>Open / Close]
    F --> G[Iterative Thinning<br/>1-px skeleton]
    G --> H["Minutiae Extraction<br/>(crossing-number)"]
    H --> I[Centroid +<br/>RMS-scale Normalisation]
    I --> J[Rotation Search<br/>24 steps + matching]
    J --> K(["Score =<br/>2 × matched / (probe+cand) × 100"])
```

Reading the flow left-to-right makes the dependency order explicit: cleaning stages (grayscale → Gabor) come first, structural stages (threshold → thinning) next, and feature/matching stages (minutiae → score) last. Each arrow represents data handed from one stage to the next, which is exactly why a sequence flow communicates the pipeline more faithfully than a flat list.

**Minutiae** are the small ridge features that make every fingerprint unique. The **crossing-number** method reads each pixel's 3×3 neighbourhood on the thinned skeleton:
- crossing number `1` → a **ridge ending**
- crossing number `3` → a **bifurcation** (a ridge splitting in two)

**Matching** compares two minutiae sets:
1. Translate both sets to their centroids (removes position differences).
2. Apply **RMS scale normalisation** so that captures taken at different camera distances become comparable — this was a critical fix; without it scores were meaningless.
3. Rotate one set through 24 steps covering 360° to absorb hand rotation.
4. Count minutiae pairs that fall within distance and angle tolerance.
5. Score = `2 × matched_pairs / (|probe| + |candidate|) × 100`, on a 0–100 scale.

> **Design note:** an earlier version used ORB (a general-purpose computer-vision descriptor). It was abandoned because ORB is not designed for fingerprints. The custom minutiae approach is the biometrically correct primitive. (SourceAFIS, a stronger library, was also evaluated but dropped due to a Python 3.13 incompatibility.)

### 5.2 Face pipeline (the primary biometric)

Face recognition is **more robust** to the variability of a hand-held camera than contactless fingerprinting, so it is the *primary* modality.

- **On the phone:** Google ML Kit performs face detection, landmark tracking, and the active-liveness challenge.
- **On the server:** the **InsightFace `buffalo_s` ArcFace model** [Deng et al., 2019] converts a face into a **512-dimensional embedding** — a list of 512 numbers that captures the face's identity. Two photos of the same person produce nearby vectors; two different people produce distant ones.
- **Search:** vectors are stored in a **FAISS `IndexFlatIP`** index [Johnson et al., 2019]. All vectors are L2-normalised before insertion, so the inner product equals **cosine similarity**. `FlatIP` is *exact* (not approximate) and comfortably handles ~100,000 patients on one CPU core. Given a new face, FAISS returns the top-N most similar enrolled patients almost instantly — this is **1:N identification**.

### 5.3 Liveness detection (anti-spoofing)

To stop someone holding up a photo or a screen, both an **active** and a **passive** check must pass (`liveness_service.py`):

- **Active (phone):** a state machine asks the user to blink and turn their head; ML Kit's eye-open and head-angle outputs confirm a live, cooperative subject.
- **Passive (server), face:**
  - *Moiré detection* — screens and printed photos introduce periodic high-frequency bands in the **Fourier (FFT)** domain that live skin does not.
  - *Specular-highlight ratio* — real skin produces small, localised highlights; flat prints have almost none, screens over-expose broadly.
- **Passive (server), fingerprint:** *Lucas-Kanade optical flow* across several frames detects the micro-movement (0.3–2.5 px) of a live finger from breathing and pulse; a photo shows near-zero displacement.

---

## 6. Enrollment Strategies

Enrollment is the act of *registering* a biometric so it can be matched later. Two refinements improve reliability:

### 6.1 Multi-template enrollment
Rather than storing one sample per patient, the system stores **several** (multiple face embeddings, multiple fingerprint templates). At match time it searches all of a patient's templates and keeps the **best (max) score**. This tolerates day-to-day variation in pose and lighting. For faces, the oldest template is evicted once a per-patient cap is reached.

### 6.2 Gallery-of-3 fingerprint enrollment
Each finger may store up to **three** templates capturing different angles and ridge coverage (`2026_06_05_000001_add_gallery_support_to_fingerprints_table.php`). The design carefully balances accuracy against speed:
- **1:1 verification** uses all three templates with a **Max-Rule** (best score wins) → higher genuine-match rates.
- **1:N identification** uses only **one representative template per finger** — the one flagged `is_gallery_lead` — so a large search does not become three times slower or inflate the false-accept rate.

If a finger enrols with fewer than three usable captures, it is flagged `needs_reenrollment` for later improvement.

---

## 7. The Multi-Modal Decision Matrix

The two biometrics are combined deliberately rather than treated as interchangeable:

1. **Face → shortlist.** FAISS returns the top-5 candidate patients. A score above the identify threshold (≈0.40) is a strong candidate; a borderline band (≈0.32–0.40) is marked `needs_review`.
2. **Fingerprint → confirm.** The fingerprint is matched *only against the shortlisted candidates*, not the whole database.
3. **Resolution:**
   - Fingerprint clearly confirms one candidate → **`confirmed`**.
   - Fingerprint is ambiguous or fails → **`manual_review`**.

The system **never auto-rejects and never auto-accepts** a borderline case. In a hospital, a confident wrong answer is more dangerous than asking a human to look — so ambiguity is always escalated, with the decision recorded in the audit log.

---

## 8. Data Model

The MySQL schema (see `laravel/database/migrations/`) models the clinical domain with enforced foreign keys:

| Table | Purpose |
|-------|---------|
| `hospitals` | Multi-tenant root; each row isolates one clinical site |
| `users` | Staff accounts with a role and a hospital |
| `patients` | Demographic records, scoped per hospital |
| `fingerprints` | Minutiae templates, gallery flags, and lock state |
| `face_templates` | 512-dim embeddings (multiple per patient) |
| `verification_logs` | Every identification scan, with score and modality |
| `visits` / `visit_stages` | Patient visit lifecycle and stage tracking |
| `patient_edit_requests` | Nurse-submitted demographic corrections awaiting approval |
| `supervisor_overrides` | Recorded manual overrides of automated decisions |
| `audit_logs` | Append-only record of all sensitive actions |

**Privacy by design:** the system stores **mathematical templates, not raw biometric images** — minutiae descriptors for fingerprints and 512-number embeddings for faces. These cannot be trivially reversed into a usable photograph, limiting the harm of a data breach.

---

## 9. Security Summary

- **Templates, not images** — minimises biometric data exposure.
- **Token authentication** (Sanctum) with logout revocation.
- **Role + hospital middleware** — least privilege and tenant isolation enforced server-side.
- **Server-side validation** — client geofencing is never trusted as a boundary.
- **Input validation** — all API inputs pass through Laravel Form Requests.
- **Append-only audit trail** for accountability.
- **Fingerprint locking** — records exceeding a failed-match threshold auto-lock and need an administrator to unlock.
- **FAISS index integrity** — embeddings are dimension-validated; a corrupt index is *quarantined* with a timestamped backup, not silently discarded.
- **Transactional enrollment** — database writes and FAISS calls share a transaction, so a failure on either side rolls back cleanly.
- **HTTPS in production** and the microservice **bound to localhost** only.

---

## 10. Evaluation and Known Limitations

Honest reporting of limits is part of good engineering. From live testing (small sample, two subjects, phone camera):

- The fingerprint **matching algorithm is correct**, but **camera-based contactless capture has an accuracy ceiling**. Genuine and impostor scores overlap in the 28–40 range, so no single threshold eliminates both false accepts and false rejects under inconsistent capture.
- The dominant cause is **partial capture** — a different part of the fingertip is imaged each time, leaving a small overlap zone. This is a *physical* limit that no matching algorithm can fully overcome without dedicated scanner hardware. This matches the well-documented findings of NIST's contactless and fingerprint vendor evaluations [NIST FpVTE; NIST IREX].
- **Reported FAR/FRR figures are uncalibrated.** A formal study with **N ≥ 50 subjects** is required before any clinical deployment, and all thresholds must be re-tuned on the target hardware.
- **Mitigation in this system:** face recognition (ArcFace) is the **primary** biometric because it is far more robust to capture variability; fingerprint is a **secondary confirmation** within the decision matrix, never the sole decider.

### Future work
- A formal FAR/FRR study at scale.
- A deep-learning ridge extractor (e.g. FingerNet) or an optional USB scanner for production-grade fingerprinting.
- Completing the Flutter active-liveness state machine and field-calibrating all liveness thresholds.

---

## 11. References

> The following sources informed the biometric design decisions in this report.

1. J. Deng, J. Guo, N. Xue, and S. Zafeiriou, "ArcFace: Additive Angular Margin Loss for Deep Face Recognition," *IEEE/CVF Conference on Computer Vision and Pattern Recognition (CVPR)*, 2019.
2. J. Johnson, M. Douze, and H. Jégou, "Billion-scale similarity search with GPUs," *IEEE Transactions on Big Data*, vol. 7, no. 3, pp. 535–547, 2019. (FAISS)
3. D. Maltoni, D. Maio, A. K. Jain, and S. Prabhakar, *Handbook of Fingerprint Recognition*, 2nd ed. London: Springer, 2009. (Minutiae and crossing-number extraction)
4. L. Hong, Y. Wan, and A. K. Jain, "Fingerprint Image Enhancement: Algorithm and Performance Evaluation," *IEEE Transactions on Pattern Analysis and Machine Intelligence*, vol. 20, no. 8, pp. 777–789, 1998. (Gabor-filter ridge enhancement)
5. K. Zuiderveld, "Contrast Limited Adaptive Histogram Equalization," in *Graphics Gems IV*, Academic Press, 1994.
6. B. D. Lucas and T. Kanade, "An Iterative Image Registration Technique with an Application to Stereo Vision," *Proc. Imaging Understanding Workshop*, 1981. (Optical-flow liveness)
7. A. K. Jain, A. Ross, and S. Prabhakar, "An Introduction to Biometric Recognition," *IEEE Transactions on Circuits and Systems for Video Technology*, vol. 14, no. 1, pp. 4–20, 2004.
8. National Institute of Standards and Technology (NIST), *Fingerprint Vendor Technology Evaluation (FpVTE)*, NISTIR 8034. Gaithersburg, MD, 2015.
9. National Institute of Standards and Technology (NIST), *IREX and Contactless Fingerprint Capture Evaluations*, NIST Technical Reports. (Accuracy limits of contactless capture)
10. ISO/IEC 19794-2, *Information technology — Biometric data interchange formats — Part 2: Finger minutiae data*. International Organization for Standardization.
11. ISO/IEC 30107-1, *Information technology — Biometric presentation attack detection — Part 1: Framework*. (Liveness / anti-spoofing)
12. World Health Organization, *Patient Identification*, Patient Safety Solutions, vol. 1, solution 2, 2007. (Clinical motivation)

---

*This document describes the system as implemented at the time of writing. Biometric thresholds are engineering estimates pending a formal accuracy study and must not be treated as clinically validated.*
