import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/staff_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_snackbar.dart';
import 'staff_form_sheet.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen>
    with SingleTickerProviderStateMixin {
  final _service = StaffService();
  late TabController _tabController;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _all = [];
  String _search = '';

  static const _roles = ['All', 'Admin', 'Doctor', 'Nurse'];

  // Pagination
  static const _pageSize = 10;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _roles.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() => _page = 0);
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _token => context.read<AuthProvider>().user!.token;

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await _service.getStaff(token: _token);
      if (mounted) setState(() { _all = list; _loading = false; });
    } on StaffException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final roleFilter = _roles[_tabController.index].toLowerCase();
    return _all.where((s) {
      final matchRole = roleFilter == 'all' || s['role'] == roleFilter;
      final q = _search.toLowerCase();
      final matchSearch = q.isEmpty ||
          (s['name'] as String? ?? '').toLowerCase().contains(q) ||
          (s['username'] as String? ?? '').toLowerCase().contains(q) ||
          (s['email'] as String? ?? '').toLowerCase().contains(q);
      return matchRole && matchSearch;
    }).toList();
  }

  List<Map<String, dynamic>> get _pageItems {
    final f = _filtered;
    final start = _page * _pageSize;
    if (start >= f.length) return [];
    return f.sublist(start, (start + _pageSize).clamp(0, f.length));
  }

  int get _totalPages => (_filtered.length / _pageSize).ceil().clamp(1, 9999);

  Future<void> _toggleActive(Map<String, dynamic> member) async {
    final id       = member['id'] as int;
    final activate = !(member['is_active'] as bool? ?? false);
    final name     = member['name'] as String? ?? 'this user';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(activate ? 'Reactivate Staff' : 'Deactivate Staff'),
        content: Text(activate
            ? 'Reactivate $name? They will regain system access.'
            : 'Deactivate $name? They will immediately lose access.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: activate ? AppColors.success : AppColors.error,
              minimumSize: const Size(80, 40),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(activate ? 'Reactivate' : 'Deactivate'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _service.setActive(token: _token, userId: id, isActive: activate);
      await _load();
      if (mounted) {
        showStatusSnackbar(context,
            message: activate ? '$name reactivated.' : '$name deactivated.',
            status: activate ? SnackStatus.success : SnackStatus.warning);
      }
    } on StaffException catch (e) {
      if (mounted) showStatusSnackbar(context, message: e.message, status: SnackStatus.error);
    }
  }

  void _openForm({Map<String, dynamic>? member}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StaffFormSheet(
        existing: member,
        onSaved: (result) async {
          Navigator.pop(context);
          await _load();
          if (mounted) {
            showStatusSnackbar(context,
                message: member == null
                    ? 'Staff member created.'
                    : 'Staff member updated.',
                status: SnackStatus.success);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Staff Management'),
        bottom: TabBar(
          controller: _tabController,
          tabs: _roles.map((r) => Tab(text: r)).toList(),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Staff'),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() { _search = v; _page = 0; }),
              decoration: InputDecoration(
                hintText: 'Search by name, username or email…',
                prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                isDense: true,
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded, size: 18, color: cs.onSurfaceVariant),
                        onPressed: () => setState(() { _search = ''; _page = 0; }),
                      )
                    : null,
              ),
            ),
          ),

          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: cs.primary))
                : _error != null
                    ? _ErrorView(message: _error!, onRetry: _load)
                    : _filtered.isEmpty
                        ? _EmptyView(hasSearch: _search.isNotEmpty)
                        : Column(
                            children: [
                              Expanded(child: _StaffTable(
                                rows: _pageItems,
                                onEdit: (m) => _openForm(member: m),
                                onToggle: _toggleActive,
                              )),
                              _Pagination(
                                current: _page,
                                total: _totalPages,
                                count: _filtered.length,
                                pageSize: _pageSize,
                                onPrev: _page > 0
                                    ? () => setState(() => _page--)
                                    : null,
                                onNext: _page < _totalPages - 1
                                    ? () => setState(() => _page++)
                                    : null,
                              ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}

// ── Staff table ───────────────────────────────────────────────────────────────

class _StaffTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(Map<String, dynamic>) onToggle;

  const _StaffTable({required this.rows, required this.onEdit, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: rows.length,
      separatorBuilder: (context, index) => Divider(height: 1, color: cs.outline),
      itemBuilder: (_, i) => _StaffRow(
        member: rows[i],
        onEdit: () => onEdit(rows[i]),
        onToggle: () => onToggle(rows[i]),
      ),
    );
  }
}

class _StaffRow extends StatelessWidget {
  final Map<String, dynamic> member;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  const _StaffRow({required this.member, required this.onEdit, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final name     = member['name']     as String? ?? '—';
    final username = member['username'] as String? ?? '—';
    final role     = member['role']     as String? ?? '—';
    final active   = member['is_active'] as bool? ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 18,
            backgroundColor: _roleColor(role).withValues(alpha: 0.15),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _roleColor(role)),
            ),
          ),
          const SizedBox(width: 12),

          // Name + username
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface),
                    overflow: TextOverflow.ellipsis),
                Text('@$username',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),

          // Role badge
          _RoleBadge(role: role),
          const SizedBox(width: 8),

          // Status pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: active ? AppColors.successLight : AppColors.errorLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              active ? 'Active' : 'Inactive',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.success : AppColors.error),
            ),
          ),
          const SizedBox(width: 4),

          // Actions
          IconButton(
            icon: Icon(Icons.edit_rounded, size: 18, color: cs.onSurfaceVariant),
            onPressed: onEdit,
            visualDensity: VisualDensity.compact,
            tooltip: 'Edit',
          ),
          IconButton(
            icon: Icon(
              active ? Icons.person_off_rounded : Icons.person_rounded,
              size: 18,
              color: active ? AppColors.error : AppColors.success,
            ),
            onPressed: onToggle,
            visualDensity: VisualDensity.compact,
            tooltip: active ? 'Deactivate' : 'Reactivate',
          ),
        ],
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':       return AppColors.primary;
      case 'super_admin': return AppColors.primaryDark;
      case 'doctor':      return AppColors.success;
      default:            return AppColors.warning;
    }
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (role) {
      'admin'       => ('Admin',  AppColors.primary, AppColors.primaryTint),
      'super_admin' => ('Super',  AppColors.primaryDark, AppColors.primaryTint),
      'doctor'      => ('Doctor', AppColors.success, AppColors.successLight),
      _             => ('Nurse',  AppColors.warning, AppColors.warningLight),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ── Pagination ────────────────────────────────────────────────────────────────

class _Pagination extends StatelessWidget {
  final int current;
  final int total;
  final int count;
  final int pageSize;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _Pagination({
    required this.current,
    required this.total,
    required this.count,
    required this.pageSize,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final start = current * pageSize + 1;
    final end   = ((current + 1) * pageSize).clamp(0, count);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline)),
      ),
      child: Row(
        children: [
          Text(
            'Showing $start–$end of $count',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: onPrev,
            visualDensity: VisualDensity.compact,
            color: onPrev != null ? cs.onSurface : cs.onSurfaceVariant,
          ),
          Text('${current + 1} / $total',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: onNext,
            visualDensity: VisualDensity.compact,
            color: onNext != null ? cs.onSurface : cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

// ── Empty / error states ──────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  final bool hasSearch;
  const _EmptyView({required this.hasSearch});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.group_off_rounded, size: 48, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          hasSearch ? 'No staff match your search.' : 'No staff in this category.',
          style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
        ),
      ]),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cancel_rounded, color: AppColors.error, size: 48),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      ),
    );
  }
}
