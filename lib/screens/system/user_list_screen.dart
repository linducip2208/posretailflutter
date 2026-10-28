import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../models/system_ops.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';

/// Daftar pengguna + peran — backend nyata (produksi, READ-ONLY):
/// - GET /users?search=&per_page= (envelope `{data: [...]}`) →
///   {id, name, email, role, active, outlets: [{id, name}]}
///   (scope outlet diterapkan server via token; tanpa filter
///   outlet_id/role di server)
/// - GET /roles → {data: [{id, name, slug, description}]}
///
/// Tidak ada POST/PUT /users di backend, jadi layar ini read-only yang
/// jujur: tambah/ubah/nonaktifkan pengguna dilakukan dari web admin.
class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<AppUser> _users = [];
  List<RoleInfo> _roles = [];
  String _roleFilter = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  static List<AppUser> parseUsers(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<Map<String, dynamic>>().map(AppUser.fromJson).toList();
  }

  static List<RoleInfo> parseRoles(dynamic raw) {
    if (raw is! List) return [];
    return raw.map(RoleInfo.fromJson).toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = _searchCtrl.text.trim();
      final response = await _api.get(
        '/users',
        query: {
          if (q.isNotEmpty) 'search': q,
          'per_page': '50',
        },
      );
      final raw = response is Map ? response['data'] : response;
      final users = parseUsers(raw);
      // Daftar peran untuk dropdown (gagal → fallback knownRoles).
      List<RoleInfo> roles = [];
      try {
        final rolesResp = await _api.get('/roles');
        final rRaw = rolesResp is Map ? rolesResp['data'] : rolesResp;
        if (rRaw is List) roles = parseRoles(rRaw);
      } catch (_) {
        roles = [];
      }
      if (!mounted) return;
      setState(() {
        _users = users;
        _roles = roles;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = S.tn(context, 'Gagal memuat daftar pengguna.');
      });
    }
  }

  List<String> get _roleOptions {
    if (_roles.isEmpty) return knownRoles;
    final names = _roles.map((r) => r.name.toLowerCase()).toSet().toList();
    for (final k in knownRoles) {
      if (!names.contains(k)) names.add(k);
    }
    return names;
  }

  /// Filter peran client-side (server tidak mendukung ?role=).
  List<AppUser> get _filtered {
    if (_roleFilter.isEmpty) return _users;
    return _users
        .where((u) => u.role.toLowerCase() == _roleFilter.toLowerCase())
        .toList();
  }

  Future<void> _openDetail(AppUser user) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _UserDetailSheet(user: user),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Pengguna & Peran')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Muat ulang'),
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              0,
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              S.t(
                context,
                'Kelola dari web admin (read-only di aplikasi).',
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: S.t(context, 'Cari nama atau email...'),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(
                        const Duration(milliseconds: 350),
                        _refresh,
                      );
                    },
                    onSubmitted: (_) => _refresh(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                DropdownButton<String>(
                  value: _roleFilter.isEmpty ? null : _roleFilter,
                  hint: Text(S.t(context, 'Semua peran')),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(S.t(context, 'Semua peran')),
                    ),
                    for (final r in _roleOptions)
                      DropdownMenuItem(
                        value: r,
                        child: Text(AppUser.roleLabel(r)),
                      ),
                  ],
                  onChanged: (v) => setState(() => _roleFilter = v ?? ''),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingSkeleton(items: 6, itemHeight: 64);
    if (_error != null) return ErrorState(message: _error!, onRetry: _refresh);
    final rows = _filtered;
    if (rows.isEmpty) {
      return EmptyState(
        icon: Icons.manage_accounts_outlined,
        title: S.t(context, 'Tidak ada pengguna'),
        message: S.t(
          context,
          'Pengguna baru dibuat dari web admin.',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: rows.length,
        itemBuilder: (_, i) => _userCard(rows[i]),
      ),
    );
  }

  Widget _userCard(AppUser user) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            user.name.isEmpty ? '?' : user.name.substring(0, 1).toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(
          user.name.isEmpty ? S.t(context, 'Tanpa nama') : user.name,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [AppUser.roleLabel(user.role), if (user.email != null) user.email!]
              .join(' · '),
          style: const TextStyle(fontSize: 11.5),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: StatusBadge(
          user.active ? S.t(context, 'Aktif') : S.t(context, 'Nonaktif'),
          tone: user.active ? BadgeTone.success : BadgeTone.neutral,
        ),
        onTap: () => _openDetail(user),
      ),
    );
  }
}

/// Detail pengguna (read-only) + matriks akses peran.
/// Perubahan peran/status hanya dari web admin.
class _UserDetailSheet extends StatelessWidget {
  final AppUser user;

  const _UserDetailSheet({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = user;
    final access = roleAccessMatrix[u.role.toLowerCase()] ?? const [];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  u.name.isEmpty ? '?' : u.name.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.name,
                      style: theme.textTheme.titleMedium?.copyWith(fontSize: 16),
                    ),
                    Row(
                      children: [
                        StatusBadge(
                          AppUser.roleLabel(u.role),
                          tone: BadgeTone.info,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        StatusBadge(
                          u.active
                              ? S.t(context, 'Aktif')
                              : S.t(context, 'Nonaktif'),
                          tone: u.active
                              ? BadgeTone.success
                              : BadgeTone.neutral,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _infoRow(context, S.t(context, 'Email'), u.email),
          _infoRow(
            context,
            S.t(context, 'Outlet'),
            u.outletIds.isEmpty ? null : u.outletIds.join(', '),
          ),
          const Divider(height: AppSpacing.xl),
          Text(
            S.t(context, 'Hak Akses Peran'),
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (access.isEmpty)
            Text(
              S.t(context, 'Tidak ada info hak akses untuk peran ini.'),
              style: theme.textTheme.bodySmall,
            )
          else
            for (final a in access)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 16),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(a, style: const TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              S.t(
                context,
                'Kelola dari web admin (read-only di aplikasi).',
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String? value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              (value == null || value.isEmpty) ? '-' : value,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// SnackBar info read-only — dipakai bila aksi tulis dicoba.
void showReadOnlyUserNotice(BuildContext context) {
  showAppSnackbar(
    context,
    S.tn(context, 'Kelola dari web admin (read-only di aplikasi).'),
    type: SnackType.info,
  );
}
