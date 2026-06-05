import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/hospital_service.dart';
import '../../theme/app_theme.dart';

class HospitalScreen extends StatefulWidget {
  const HospitalScreen({super.key});

  @override
  State<HospitalScreen> createState() => _HospitalScreenState();
}

class _HospitalScreenState extends State<HospitalScreen> {
  final _svc = HospitalService();

  bool _loading = true;
  List<Map<String, dynamic>> _hospitals = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _token => context.read<AuthProvider>().user!.token;

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final hospitals = await _svc.getHospitals(token: _token);
      if (mounted) setState(() { _hospitals = hospitals; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Hospitals'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add hospital',
            onPressed: () => _showForm(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: cs.error)))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: cs.primary,
                  child: _hospitals.isEmpty
                      ? const Center(child: Text('No hospitals registered yet.'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _hospitals.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _HospitalCard(
                            hospital: _hospitals[i],
                            onEdit: () => _showForm(context, hospital: _hospitals[i]),
                            onToggle: () => _toggleActive(_hospitals[i]),
                          ),
                        ),
                ),
    );
  }

  Future<void> _toggleActive(Map<String, dynamic> hospital) async {
    final isActive = hospital['is_active'] as bool? ?? true;
    try {
      await _svc.updateHospital(
        token: _token,
        hospitalId: hospital['id'] as int,
        isActive: !isActive,
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _showForm(BuildContext context, {Map<String, dynamic>? hospital}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HospitalFormSheet(hospital: hospital, token: _token),
    );
    if (result == true) _load();
  }
}

class _HospitalCard extends StatelessWidget {
  const _HospitalCard({
    required this.hospital,
    required this.onEdit,
    required this.onToggle,
  });

  final Map<String, dynamic> hospital;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final isActive = hospital['is_active'] as bool? ?? true;
    final lat      = hospital['gps_latitude'];
    final lng      = hospital['gps_longitude'];
    final radius   = hospital['gps_radius_meters'] ?? 200;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isActive ? AppColors.primaryTint : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.local_hospital_rounded,
            size: 20,
            color: isActive ? AppColors.primary : cs.onSurfaceVariant,
          ),
        ),
        title: Text(
          hospital['name'] as String? ?? '—',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              '${hospital['city'] ?? ''}  ·  Code: ${hospital['code'] ?? '—'}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            if (lat != null && lng != null) ...[
              const SizedBox(height: 2),
              Text(
                'GPS: $lat, $lng  ·  ${radius}m radius',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
            if (hospital['wifi_ssid'] != null) ...[
              const SizedBox(height: 2),
              Text(
                'WiFi: ${hospital['wifi_ssid']}',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit')   onEdit();
            if (v == 'toggle') onToggle();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit',   child: Text('Edit')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(isActive ? 'Deactivate' : 'Activate'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HospitalFormSheet extends StatefulWidget {
  const _HospitalFormSheet({this.hospital, required this.token});
  final Map<String, dynamic>? hospital;
  final String token;

  @override
  State<_HospitalFormSheet> createState() => _HospitalFormSheetState();
}

class _HospitalFormSheetState extends State<_HospitalFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _svc     = HospitalService();

  late final _nameCtrl   = TextEditingController(text: widget.hospital?['name']   as String?);
  late final _codeCtrl   = TextEditingController(text: widget.hospital?['code']   as String?);
  late final _cityCtrl   = TextEditingController(text: widget.hospital?['city']   as String?);
  late final _ssidCtrl   = TextEditingController(text: widget.hospital?['wifi_ssid'] as String?);
  late final _latCtrl    = TextEditingController(text: widget.hospital?['gps_latitude']?.toString());
  late final _lngCtrl    = TextEditingController(text: widget.hospital?['gps_longitude']?.toString());
  late final _radiusCtrl = TextEditingController(
      text: (widget.hospital?['gps_radius_meters'] ?? 200).toString());

  bool _saving = false;

  bool get _isEdit => widget.hospital != null;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _codeCtrl, _cityCtrl, _ssidCtrl, _latCtrl, _lngCtrl, _radiusCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final lat    = double.tryParse(_latCtrl.text.trim());
    final lng    = double.tryParse(_lngCtrl.text.trim());
    final radius = int.tryParse(_radiusCtrl.text.trim());

    try {
      if (_isEdit) {
        await _svc.updateHospital(
          token:           widget.token,
          hospitalId:      widget.hospital!['id'] as int,
          name:            _nameCtrl.text.trim(),
          code:            _codeCtrl.text.trim(),
          city:            _cityCtrl.text.trim(),
          wifiSsid:        _ssidCtrl.text.trim(),
          gpsLatitude:     lat,
          gpsLongitude:    lng,
          gpsRadiusMeters: radius,
        );
      } else {
        await _svc.createHospital(
          token:           widget.token,
          name:            _nameCtrl.text.trim(),
          code:            _codeCtrl.text.trim(),
          city:            _cityCtrl.text.trim(),
          wifiSsid:        _ssidCtrl.text.trim(),
          gpsLatitude:     lat,
          gpsLongitude:    lng,
          gpsRadiusMeters: radius,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on HospitalException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(_isEdit ? 'Edit Hospital' : 'Add Hospital',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),

              _Field(controller: _nameCtrl,   label: 'Hospital name', required: true),
              const SizedBox(height: 12),
              _Field(controller: _codeCtrl,   label: 'Code (e.g. MNH)',  required: true),
              const SizedBox(height: 12),
              _Field(controller: _cityCtrl,   label: 'City',             required: true),
              const SizedBox(height: 12),
              _Field(controller: _ssidCtrl,   label: 'WiFi SSID (optional)'),
              const SizedBox(height: 16),

              Text('GPS Geofence', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _Field(controller: _latCtrl,  label: 'Latitude',  numeric: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _Field(controller: _lngCtrl,  label: 'Longitude', numeric: true)),
                ],
              ),
              const SizedBox(height: 12),
              _Field(controller: _radiusCtrl, label: 'Radius (meters)', numeric: true),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_isEdit ? 'Save Changes' : 'Add Hospital'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.required = false,
    this.numeric  = false,
  });

  final TextEditingController controller;
  final String label;
  final bool required;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller:  controller,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
      decoration: InputDecoration(labelText: label),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
    );
  }
}
