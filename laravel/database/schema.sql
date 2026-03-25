-- =============================================================================
-- BiH Patient Fingerprint Verification System
-- MySQL Schema — canonical reference
-- =============================================================================
-- Run order matches migration numbers (01 → 05).
-- All tables use InnoDB for foreign key enforcement.
-- Character set: utf8mb4 (supports full Unicode including Bosnian characters).
-- =============================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- -----------------------------------------------------------------------------
-- 01. hospitals
--     One row per healthcare institution.
--     Stores GPS + WiFi data used by GeofenceService for access control.
-- -----------------------------------------------------------------------------
CREATE TABLE hospitals (
    id                  BIGINT UNSIGNED     NOT NULL AUTO_INCREMENT,
    name                VARCHAR(200)        NOT NULL,
    city                VARCHAR(100)        NOT NULL,

    -- Geofencing: device must be connected to this SSID
    wifi_ssid           VARCHAR(100)        NULL     COMMENT 'Approved hospital WiFi SSID',

    -- Geofencing: device GPS must fall within gps_radius_meters of this point
    gps_latitude        DECIMAL(10, 7)      NULL,
    gps_longitude       DECIMAL(10, 7)      NULL,
    gps_radius_meters   SMALLINT UNSIGNED   NOT NULL DEFAULT 200,

    is_active           TINYINT(1)          NOT NULL DEFAULT 1,
    created_at          TIMESTAMP           NULL     DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP           NULL     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- -----------------------------------------------------------------------------
-- 02. users  (hospital staff: admin | nurse | doctor)
--     Each user belongs to exactly one hospital.
--     Sanctum tokens are stored in personal_access_tokens.
-- -----------------------------------------------------------------------------
CREATE TABLE users (
    id              BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    hospital_id     BIGINT UNSIGNED  NOT NULL,

    name            VARCHAR(200)     NOT NULL,
    username        VARCHAR(80)      NOT NULL,
    email           VARCHAR(120)     NOT NULL,
    password        VARCHAR(256)     NOT NULL  COMMENT 'bcrypt hash',
    role            ENUM('admin', 'nurse', 'doctor') NOT NULL DEFAULT 'nurse',

    is_active       TINYINT(1)       NOT NULL DEFAULT 1,
    last_login_at   TIMESTAMP        NULL,
    remember_token  VARCHAR(100)     NULL,
    created_at      TIMESTAMP        NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP        NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    UNIQUE  KEY uq_users_username (username),
    UNIQUE  KEY uq_users_email    (email),
    INDEX   ix_users_hospital_id  (hospital_id),

    CONSTRAINT fk_users_hospital
        FOREIGN KEY (hospital_id) REFERENCES hospitals (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- -----------------------------------------------------------------------------
-- 02b. personal_access_tokens  (Laravel Sanctum)
-- -----------------------------------------------------------------------------
CREATE TABLE personal_access_tokens (
    id              BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    tokenable_type  VARCHAR(255)     NOT NULL,
    tokenable_id    BIGINT UNSIGNED  NOT NULL,
    name            VARCHAR(255)     NOT NULL,
    token           VARCHAR(64)      NOT NULL,
    abilities       TEXT             NULL,
    last_used_at    TIMESTAMP        NULL,
    expires_at      TIMESTAMP        NULL,
    created_at      TIMESTAMP        NULL,
    updated_at      TIMESTAMP        NULL,

    PRIMARY KEY (id),
    UNIQUE KEY uq_pat_token          (token),
    INDEX      ix_pat_tokenable      (tokenable_type, tokenable_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- -----------------------------------------------------------------------------
-- 03. patients
--     Core demographic record. Fingerprint templates live in a separate table.
--     jmbg = Jedinstveni Matični Broj Građana (BiH 13-digit national ID).
--
--     Relationship: hospitals (1) ──< patients (many)
-- -----------------------------------------------------------------------------
CREATE TABLE patients (
    id              BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    hospital_id     BIGINT UNSIGNED  NOT NULL,

    full_name       VARCHAR(200)     NOT NULL,
    date_of_birth   DATE             NOT NULL,
    gender          ENUM('male', 'female', 'other') NULL,
    jmbg            VARCHAR(13)      NULL     COMMENT 'BiH national ID (optional)',
    phone           VARCHAR(20)      NULL,
    notes           TEXT             NULL,

    is_active       TINYINT(1)       NOT NULL DEFAULT 1,
    created_at      TIMESTAMP        NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP        NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    UNIQUE  KEY uq_patients_jmbg        (jmbg),
    INDEX   ix_patients_hospital_id     (hospital_id),

    CONSTRAINT fk_patients_hospital
        FOREIGN KEY (hospital_id) REFERENCES hospitals (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- -----------------------------------------------------------------------------
-- 04. fingerprints
--     Stores encrypted ORB feature templates produced by the Python service.
--     Decoupled from patients so one patient can have multiple fingers enrolled.
--
--     hospital_id is denormalised here (also on patients) to avoid a JOIN on
--     every 1-to-N matching scan. The two composite indexes support two-pass
--     matching: pass-1 uses ix_fp_hospital_primary_active, pass-2 uses
--     ix_fp_hospital_active.
--
--     Enrollments with quality_score < 0.30 are rejected at the API layer.
--
--     Relationships:
--       hospitals (1) ──< fingerprints (many)  [cascade delete]
--       patients  (1) ──< fingerprints (many)  [cascade delete]
--       users     (1) ──< fingerprints (many)  [enrolled_by — restrict]
--
--     Constraint: one template per (patient, finger_position) pair.
-- -----------------------------------------------------------------------------
CREATE TABLE fingerprints (
    id              BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    patient_id      BIGINT UNSIGNED  NOT NULL,

    -- Denormalised from patients — avoids JOIN on hot matching queries
    hospital_id     BIGINT UNSIGNED  NOT NULL,

    enrolled_by     BIGINT UNSIGNED  NOT NULL  COMMENT 'User who performed enrollment',

    finger_position ENUM(
        'right_thumb',  'right_index',  'right_middle',  'right_ring',  'right_little',
        'left_thumb',   'left_index',   'left_middle',   'left_ring',   'left_little'
    ) NOT NULL DEFAULT 'right_index',

    -- AES-256-CBC encrypted via Laravel Crypt::encryptString().
    -- Raw template is NEVER persisted in plaintext.
    -- Decrypted payload: { "keypoints": [...], "descriptors": [[...], ...] }
    template        LONGTEXT         NOT NULL  COMMENT 'Encrypted ORB template JSON',

    -- Quality score [0.000–1.000] from Python /process.
    -- API rejects enrollments below 0.300 (MIN_QUALITY_SCORE in PatientController).
    quality_score   DECIMAL(4, 3)    NULL,

    -- Pass-1 matching targets only primary fingerprints per patient
    is_primary      TINYINT(1)       NOT NULL DEFAULT 0,
    is_active       TINYINT(1)       NOT NULL DEFAULT 1,

    created_at      TIMESTAMP        NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP        NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    UNIQUE  KEY uq_patient_finger              (patient_id, finger_position),

    -- Pass-1: primary-only scan (fast path)
    INDEX   ix_fp_hospital_primary_active      (hospital_id, is_primary, is_active),
    -- Pass-2: all-active scan (fallback)
    INDEX   ix_fp_hospital_active              (hospital_id, is_active),

    CONSTRAINT fk_fingerprints_hospital
        FOREIGN KEY (hospital_id) REFERENCES hospitals (id) ON DELETE CASCADE,
    CONSTRAINT fk_fingerprints_patient
        FOREIGN KEY (patient_id)  REFERENCES patients  (id) ON DELETE CASCADE,
    CONSTRAINT fk_fingerprints_user
        FOREIGN KEY (enrolled_by) REFERENCES users      (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- -----------------------------------------------------------------------------
-- 05. verification_logs
--     Immutable audit trail of every verification attempt.
--     patient_id and fingerprint_id are nullable — set only when status = matched.
--
--     Relationships:
--       hospitals     (1) ──< verification_logs (many)
--       users         (1) ──< verification_logs (many)   [operator_id]
--       patients      (1) ──< verification_logs (many)   [nullable]
--       fingerprints  (1) ──< verification_logs (many)   [nullable]
-- -----------------------------------------------------------------------------
CREATE TABLE verification_logs (
    id              BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,

    patient_id      BIGINT UNSIGNED  NULL     COMMENT 'NULL = no match found',
    fingerprint_id  BIGINT UNSIGNED  NULL     COMMENT 'Matched fingerprint record',
    operator_id     BIGINT UNSIGNED  NOT NULL COMMENT 'Staff who triggered verification',
    hospital_id     BIGINT UNSIGNED  NOT NULL,

    -- Match score [0.0000–1.0000] from Python /match endpoint
    score           DECIMAL(5, 4)    NULL,
    status          ENUM('matched', 'no_match', 'error') NOT NULL DEFAULT 'no_match',

    -- Device location snapshot at time of verification
    gps_latitude    DECIMAL(10, 7)   NULL,
    gps_longitude   DECIMAL(10, 7)   NULL,
    wifi_ssid       VARCHAR(100)     NULL,

    error_message   TEXT             NULL,
    created_at      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP        NULL     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    INDEX ix_vl_patient_id   (patient_id),
    INDEX ix_vl_operator_id  (operator_id),
    INDEX ix_vl_created_at   (created_at),

    CONSTRAINT fk_vl_patient
        FOREIGN KEY (patient_id)     REFERENCES patients      (id) ON DELETE SET NULL,
    CONSTRAINT fk_vl_fingerprint
        FOREIGN KEY (fingerprint_id) REFERENCES fingerprints  (id) ON DELETE SET NULL,
    CONSTRAINT fk_vl_operator
        FOREIGN KEY (operator_id)    REFERENCES users         (id) ON DELETE CASCADE,
    CONSTRAINT fk_vl_hospital
        FOREIGN KEY (hospital_id)    REFERENCES hospitals     (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
