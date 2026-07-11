import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/patient.dart';
import '../providers/auth_provider.dart';
import '../services/fingerprint_service.dart';
import '../services/location_service.dart';
import '../services/network_service.dart';
import '../services/patient_service.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';
import 'ehr_screen.dart';
import 'fingerprint/fingerprint_liveness_camera_screen.dart';
import 'result_screen.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final _searchController = TextEditingController();
  final _searchFocus      = FocusNode();

  PatientModel? _selectedPatient;
  List<PatientModel> _searchResults = [];
  bool _isSearching = false;
  bool _showDropdown = false;
  Timer? _debounce;

  XFile? _capturedImage;
  bool _isVerifying = false;
  String? _error;
  String _hand = 'right';

  static const int _maxAttempts = 3;
  int _attemptCount = 0;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus) {
        setState(() => _showDropdown = false);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _showDropdown = false;
        _selectedPatient = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(value.trim()));
  }

  Future<void> _runSearch(String query) async {
    final token = context.read<AuthProvider>().user?.token;
    if (token == null) return;

    setState(() => _isSearching = true);

    try {
      final results = await PatientService().searchPatients(
        token: token,
        query: query,
      );
      if (mounted) {
        setState(() {
          _searchResults = results;
          _showDropdown = results.isNotEmpty;
          _isSearching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _selectPatient(PatientModel patient) {
    setState(() {
      _selectedPatient = patient;
      _showDropdown = false;
      _searchResults = [];
      _capturedImage = null;
      _attemptCount = 0;
      _error = null;
    });
    _searchController.clear();
    _searchFocus.unfocus();
  }

  void _clearPatient() {
    setState(() {
      _selectedPatient = null;
      _capturedImage = null;
      _attemptCount = 0;
      _error = null;
    });
  }

  // ── Step 1: open camera in capture-only mode ──────────────────────────────

  Future<void> _openCamera() async {
    if (_selectedPatient == null) {
      setState(() => _error = 'Search and select a patient first.');
      return;
    }

    setState(() => _error = null);

    final XFile? result = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => FingerprintLivenessCameraScreen(
          isHandCapture: true,
          fingerLabel: _hand == 'right' ? 'Right Hand' : 'Left Hand',
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() => _capturedImage = result);
    }
  }

  // ── Step 2: send to Laravel → Python → return verdict ────────────────────

  Future<void> _verify() async {
    if (_capturedImage == null) return;

    final token = context.read<AuthProvider>().user?.token;
    if (token == null || token.isEmpty) {
      setState(() => _error =
          'Your session has expired. Please log out and log in again.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
      _attemptCount++;
    });

    try {
      final position = await LocationService().getCurrentPosition();
      final wifiSsid = await NetworkService().getCurrentSsid();

      final result = await FingerprintService().verifyHand(
        File(_capturedImage!.path),
        token:        token,
        hand:         _hand,
        gpsLatitude:  position?.latitude,
        gpsLongitude: position?.longitude,
        wifiSsid:     wifiSsid,
      );

      if (!mounted) return;

      if (result.isAccessRestricted) {
        setState(() => _isVerifying = false);
        await _showAccessRestrictedDialog();
        if (mounted) setState(() => _capturedImage = null);
        return;
      }

      if (result.isNeedsReview) {
        setState(() => _isVerifying = false);
        await _showAdvisoryDialog(result);
        if (mounted) setState(() => _capturedImage = null);
        return;
      }

      final matchedPatientId = result.patient?['id'] as int?;
      final matchedName      = result.patient?['full_name'] as String?;

      if (result.isMatch && matchedPatientId == _selectedPatient!.id) {
        // Navigate to EHR screen. verifyHand doesn't enrich with GoT-HoMIS
        // EHR/insurance yet (same as the 1:N identify flow) — EhrScreen
        // already renders an "unavailable" state for those when null.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EhrScreen(
              patientName:   matchedName ?? _selectedPatient!.fullName,
              score:         result.score,
              matchedFinger: '4-finger fused ($_hand hand)',
              ehr:           null,
              insurance:     null,
              perFinger:     result.perFinger,
            ),
          ),
        );
        return;
      }

      if (result.isMatch && matchedPatientId != _selectedPatient!.id) {
        // The fingerprint matched a DIFFERENT enrolled patient — a more
        // serious signal than a plain no-match, worth its own dialog.
        setState(() => _isVerifying = false);
        await _showMismatchDialog(matchedName);
        if (mounted) setState(() => _capturedImage = null);
        return;
      }

      // no_match
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            isSuccess:      false,
            isRegistration: false,
            patientName:    _selectedPatient!.fullName,
            patientId:      'ID: ${_selectedPatient!.id}',
            score:          result.score,
            matchedFinger:  '4-finger fused',
            attemptCount:   _attemptCount,
            maxAttempts:    _maxAttempts,
          ),
        ),
      );
      // Reset image + spinner so user captures a fresh scan on retry
      if (mounted) {
        setState(() {
          _isVerifying   = false;
          _capturedImage = null;
        });
      }
    } on FingerprintException catch (e) {
      if (mounted) {
        setState(() {
          _error = _verifyErrorMessage(e);
          _isVerifying = false;
        });
      }
    } catch (_) {
      // Catch unexpected errors (e.g., file read failure) so the screen never
      // gets stuck on the "Verifying…" spinner.
      if (mounted) {
        setState(() {
          _error = 'An unexpected error occurred. Please try again.';
          _isVerifying = false;
        });
      }
    }
  }

  /// needs_review means the backend could not auto-decide (placeholder
  /// matcher or missing calibrated threshold) — surface the advisory
  /// candidate; staff must confirm identity another way.
  Future<void> _showAdvisoryDialog(HandVerifyResult result) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 22),
          SizedBox(width: 8),
          Text('Manual Review Required'),
        ]),
        content: Text(
          result.note ??
              'The system could not decide automatically. Verify the '
                  'patient\'s identity with their ID card.',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// The fingerprint matched a different enrolled patient than the one
  /// selected — flag it distinctly from a plain no-match.
  Future<void> _showMismatchDialog(String? matchedName) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 22),
          SizedBox(width: 8),
          Text('Identity Mismatch'),
        ]),
        content: Text(
          matchedName != null
              ? 'This fingerprint matches a different patient ($matchedName), '
                  'not ${_selectedPatient?.fullName}.'
              : 'This fingerprint does not belong to ${_selectedPatient?.fullName}.',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// access_restricted (plan 005): the patient was identified nationally, but
  /// this facility is not authorized to view their record. The server sends
  /// no PII in this case.
  Future<void> _showAccessRestrictedDialog() {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.lock_outline, color: Color(0xFF6B7280), size: 22),
          SizedBox(width: 8),
          Text('Access Restricted'),
        ]),
        content: const Text(
          'This patient was identified, but they are registered at another '
          'facility. You are not authorized to view their records here.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Returns an actionable, user-facing message for each error kind.
  String _verifyErrorMessage(FingerprintException e) {
    switch (e.kind) {
      case FingerprintErrorKind.network:
        return 'No connection. Check your network and tap Verify again.';
      case FingerprintErrorKind.qualityTooLow:
        return 'The captured image is too blurry. Tap Retake, move to better '
            'lighting, and try again.';
      case FingerprintErrorKind.noFeatures:
        return 'No fingerprint features were detected. Tap Retake, ensure the '
            'finger fully covers the frame, and try again.';
      case FingerprintErrorKind.serviceUnavailable:
        return 'The fingerprint processing service is temporarily unavailable. '
            'Please wait a moment and try again.';
      case FingerprintErrorKind.notFound:
        return 'Patient not found or no fingerprint enrolled. '
            'Verify the patient ID and ensure a fingerprint has been registered.';
      case FingerprintErrorKind.unauthorized:
        return 'Your session has expired. Please log out and log in again.';
      case FingerprintErrorKind.serverError:
        return 'A server error occurred. Please try again or contact support '
            'if the problem persists.';
      default:
        return e.message;
    }
  }

  void _retake() => setState(() {
        _capturedImage = null;
        _error = null;
      });

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Patient')),
      body: SafeArea(
        child: _isVerifying
            ? const _VerifyingView()
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return GestureDetector(
      onTap: () {
        _searchFocus.unfocus();
        setState(() => _showDropdown = false);
      },
      behavior: HitTestBehavior.translucent,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Instruction banner ──────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      color: AppColors.primary, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Search for the patient by name or ID, then capture their fingerprint to verify identity.',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Error banner ────────────────────────────────────────────
            if (_error != null) ...[
              _ErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null),
                onRetry: _capturedImage != null ? _verify : null,
              ),
              const SizedBox(height: 16),
            ],

            // ── Patient search / selected chip ──────────────────────────
            const Text(
              'Patient',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),

            if (_selectedPatient != null)
              _SelectedPatientChip(
                patient: _selectedPatient!,
                onClear: _clearPatient,
              )
            else
              _PatientSearchField(
                controller: _searchController,
                focusNode: _searchFocus,
                isSearching: _isSearching,
                showDropdown: _showDropdown,
                results: _searchResults,
                onChanged: _onSearchChanged,
                onSelect: _selectPatient,
              ),

            const SizedBox(height: 24),

            // ── Hand selector ────────────────────────────────────────────
            const Text(
              'Which hand?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _HandOption(
                  label: 'Right Hand',
                  selected: _hand == 'right',
                  onTap: () => setState(() {
                    _hand = 'right';
                    _capturedImage = null;
                  }),
                ),
                const SizedBox(width: 12),
                _HandOption(
                  label: 'Left Hand',
                  selected: _hand == 'left',
                  onTap: () => setState(() {
                    _hand = 'left';
                    _capturedImage = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Fingerprint capture section ─────────────────────────────
            const Text(
              'Fingerprint',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            if (_capturedImage == null)
              _ScanPrompt(onTap: _openCamera)
            else
              _CapturedPreview(
                imagePath: _capturedImage!.path,
                onRetake: _retake,
              ),

            const SizedBox(height: 32),

            // ── Action buttons ──────────────────────────────────────────
            if (_capturedImage != null)
              PrimaryButton(
                label: 'Verify Identity',
                icon: Icons.verified_user_rounded,
                onPressed: _isVerifying ? null : _verify,
              ),

            if (_capturedImage == null)
              PrimaryButton(
                label: 'Scan Fingerprint',
                icon: Icons.fingerprint,
                onPressed: _openCamera,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _HandOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _HandOption(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.1)
                : AppColors.secondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.back_hand_outlined,
                color:
                    selected ? AppColors.primary : AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color:
                      selected ? AppColors.primary : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerifyingView extends StatelessWidget {
  const _VerifyingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 20),
          Text(
            'Verifying fingerprint…',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 15),
          ),
          SizedBox(height: 6),
          Text(
            'Comparing against stored template',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ScanPrompt extends StatelessWidget {
  final VoidCallback onTap;
  const _ScanPrompt({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFF0F1923),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.fingerprint,
              size: 56,
              color: AppColors.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tap to capture fingerprint',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapturedPreview extends StatelessWidget {
  final String imagePath;
  final VoidCallback onRetake;

  const _CapturedPreview(
      {required this.imagePath, required this.onRetake});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(
            File(imagePath),
            width: double.infinity,
            height: 220,
            fit: BoxFit.cover,
            errorBuilder: (_, e, s) => Container(
              height: 220,
              color: Colors.black26,
              child: const Icon(Icons.broken_image,
                  color: Colors.white38, size: 48),
            ),
          ),
        ),
        // Success badge
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.5)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle,
                    color: AppColors.success, size: 14),
                SizedBox(width: 5),
                Text('Captured',
                    style: TextStyle(
                        color: AppColors.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
        // Retake button
        Positioned(
          top: 12,
          right: 12,
          child: GestureDetector(
            onTap: onRetake,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, color: Colors.white70, size: 14),
                  SizedBox(width: 5),
                  Text('Retake',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  /// When provided, shows a "Retry" button inside the banner.
  final VoidCallback? onRetry;

  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.error_outline,
                    color: AppColors.error, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                      color: AppColors.error, fontSize: 13, height: 1.4),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.close, color: AppColors.error, size: 16),
                ),
              ),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Shows the confirmed patient as a dismissible tile.
class _SelectedPatientChip extends StatelessWidget {
  final PatientModel patient;
  final VoidCallback onClear;

  const _SelectedPatientChip({required this.patient, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.fullName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  patient.displayId,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close, color: AppColors.textSecondary, size: 18),
          ),
        ],
      ),
    );
  }
}

// Search field with live dropdown results.
class _PatientSearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearching;
  final bool showDropdown;
  final List<PatientModel> results;
  final ValueChanged<String> onChanged;
  final ValueChanged<PatientModel> onSelect;

  const _PatientSearchField({
    required this.controller,
    required this.focusNode,
    required this.isSearching,
    required this.showDropdown,
    required this.results,
    required this.onChanged,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: 'Search by name or patient ID…',
            prefixIcon: const Icon(Icons.search,
                color: AppColors.textSecondary, size: 20),
            suffixIcon: isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    ),
                  )
                : null,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.divider, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.divider, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
        if (showDropdown)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: results.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: AppColors.divider),
                itemBuilder: (_, i) {
                  final p = results[i];
                  return InkWell(
                    onTap: () => onSelect(p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline,
                              color: AppColors.textSecondary, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.fullName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  p.displayId,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
