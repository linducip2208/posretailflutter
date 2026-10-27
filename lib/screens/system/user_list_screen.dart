import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../config/api_config.dart';
import '../../l10n/s.dart';
import '../../models/system_ops.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/secure_token_storage.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/confirmation_dialog.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';

/// PUT belum tersedia di [ApiService]; tiru pola supplier_list_screen:
/// tulis via [ApiService.client] langsung dengan token + pesan manusiawi.
Future<dynamic> _sendWrite(
  String method,
  String path, {
  Map<String, dynamic>? body,
}) async {
  String? token;
  try {
    token = await SecureTokenStorage().readToken();
  } catch (_) {
    token = null;
  }
  final uri = Uri.parse('${ApiConfig.baseUrl}$path');
  final headers = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };
  http.Response response;
  try {
    final Future<http.Response> future = method == 'PUT'
        ? ApiService.client.put(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
        : ApiService.client.delete(uri, headers: headers);
    response = await future.timeout(ApiConfig.requestTimeout);
  } on TimeoutException {
    throw ApiNetworkException(
      'Koneksi ke server timeout. Periksa jaringan lalu coba lagi.',
    );
  } on SocketException {
    throw ApiNetworkException(
      'Tidak dapat terhubung ke server. Periksa jaringan Anda.',
    );
  } on http.ClientException {
    throw ApiNetworkException(
      'Koneksi ke server gagal. Periksa jaringan Anda.',
    );
  }
  dynamic decoded;
  try {
    decoded = response.body.isNotEmpty ? jsonDecode(response.body) : {};
  } catch (_) {
    decoded = {};
  }
  if (response.statusCode >= 200 && response.statusCode < 300) return decoded;
  throw ApiException(
    statusCode: response.statusCode,
    message:
        (decoded is Map && decoded['message'] != null
            ? decoded['message'].toString()
            : null) ??
        'Request gagal.',
    errors: decoded is Map ? decoded['errors'] : null,
  );
}

/// Daftar pengguna + peran (kontrak grup 12):
/// GET /users?outlet_id=&role=, POST /users, PUT /users/{id}, GET /roles.
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

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final outletId = context.read<AuthProvider>().currentOutletId;
      final response = await _api.get(
        '/users',
        query: {
          if (outletId != null) 'outlet_id': '$outletId',
          if (_roleFilter.isNotEmpty) 'role': _roleFilter,
        },
      );
      final raw = response is Map ? response['data'] : response;
      final rows = raw is List
          ? raw.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      List<AppUser> users = rows.map(AppUser.fromJson).toList();
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q.isNotEmpty) {
        users = users
            .where(
              (u) =>
                  u.name.toLowerCase().contains(q) ||
                  (u.email ?? '').toLowerCase().contains(q),
            )
            .toList();
      }
      // Daftar peran untuk dropdown (gagal → fallback knownRoles).
      List<RoleInfo> roles = [];
      try {
        final rolesResp = await _api.get('/roles');
        final rRaw = rolesResp is Map ? rolesResp['data'] : rolesResp;
        if (rRaw is List) {
          roles = rRaw.map(RoleInfo.fromJson).toList();
        }
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

  Future<void> _openCreateDialog() async {
    final created = await showDialog<AppUser>(
      context: context,
      builder: (_) => _UserFormDialog(roles: _roleOptions),
    );
    if (created == null || !mounted) return;
    showAppSnackbar(
      context,
      '${S.tn(context, 'Pengguna')} "${created.name}" ${S.tn(context, 'tersimpan di server.')}',
      type: SnackType.success,
    );
    await _refresh();
  }

  Future<void> _openDetail(AppUser user) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _UserDetailSheet(user: user, onChanged: _refresh),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Pengguna & Peran')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Tambah pengguna'),
            onPressed: _openCreateDialog,
            icon: const Icon(Icons.person_add_alt),
          ),
          IconButton(
            tooltip: S.t(context, 'Muat ulang'),
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
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
                  onChanged: (v) {
                    setState(() => _roleFilter = v ?? '');
                    _refresh();
                  },
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
    if (_users.isEmpty) {
      return EmptyState(
        icon: Icons.manage_accounts_outlined,
        title: S.t(context, 'Tidak ada pengguna'),
        message: S.t(
          context,
          'Tambah pengguna baru dengan tombol di kanan atas.',
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
        itemCount: _users.length,
        itemBuilder: (_, i) => _userCard(_users[i]),
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

/// Form tambah (POST /users) / ubah (PUT /users/{id}) pengguna.
class _UserFormDialog extends StatefulWidget {
  final AppUser? existing;
  final List<String> roles;

  const _UserFormDialog({this.existing, required this.roles});

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final ApiService _api = ApiService();
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _emailCtrl = TextEditingController(
    text: widget.existing?.email ?? '',
  );
  final TextEditingController _passwordCtrl = TextEditingController();
  late String _role = widget.existing?.role ?? 'kasir';
  late bool _active = widget.existing?.active ?? true;
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = S.tn(context, 'Nama wajib diisi.'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final outletId = context.read<AuthProvider>().currentOutletId;
      final body = <String, dynamic>{
        'name': name,
        if (_emailCtrl.text.trim().isNotEmpty)
          'email': _emailCtrl.text.trim(),
        if (!_isEdit && _passwordCtrl.text.isNotEmpty)
          'password': _passwordCtrl.text,
        'role': _role,
        if (_isEdit) 'active': _active,
        if (outletId != null) 'outlet_ids': [outletId],
      };
      final dynamic response = _isEdit
          ? await _sendWrite('PUT', '/users/${widget.existing!.id}', body: body)
          : await _api.post('/users', body: body);
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      Navigator.pop(
        context,
        data is Map<String, dynamic>
            ? AppUser.fromJson(data)
            : AppUser(id: widget.existing?.id ?? 0, name: name, role: _role),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = S.tn(context, 'Gagal menyimpan pengguna.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEdit
            ? S.t(context, 'Ubah Pengguna')
            : S.t(context, 'Tambah Pengguna'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(_error!, style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextField(
              key: const ValueKey('user_name_field'),
              controller: _nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '${S.t(context, 'Nama')} *',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: S.t(context, 'Email')),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: S.t(context, 'Kata sandi'),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: widget.roles.contains(_role) ? _role : null,
              hint: Text(S.t(context, 'Pilih peran')),
              items: [
                for (final r in widget.roles)
                  DropdownMenuItem(value: r, child: Text(AppUser.roleLabel(r))),
              ],
              onChanged: (v) => setState(() => _role = v ?? 'kasir'),
              decoration: InputDecoration(labelText: S.t(context, 'Peran')),
            ),
            if (_isEdit) ...[
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(S.t(context, 'Akun aktif')),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: Text(S.t(context, 'Batal')),
        ),
        FilledButton(
          key: const ValueKey('user_save_button'),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(S.t(context, 'Simpan')),
        ),
      ],
    );
  }
}

/// Detail pengguna + matriks akses peran + ubah cepat peran/status.
class _UserDetailSheet extends StatefulWidget {
  final AppUser user;
  final Future<void> Function() onChanged;

  const _UserDetailSheet({required this.user, required this.onChanged});

  @override
  State<_UserDetailSheet> createState() => _UserDetailSheetState();
}

class _UserDetailSheetState extends State<_UserDetailSheet> {
  bool _busy = false;

  Future<void> _quickUpdate({String? role, bool? active}) async {
    setState(() => _busy = true);
    try {
      await _sendWrite('PUT', '/users/${widget.user.id}', body: {
        if (role case final String r) 'role': r,
        if (active case final bool a) 'active': a,
      });
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Pengguna berhasil diperbarui.'),
        type: SnackType.success,
      );
      Navigator.pop(context);
      await widget.onChanged();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackbar(context, e.message, type: SnackType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmToggleActive() async {
    final toActive = !widget.user.active;
    final confirmed = await confirmDialog(
      context,
      title: toActive
          ? S.tn(context, 'Aktifkan pengguna?')
          : S.tn(context, 'Nonaktifkan pengguna?'),
      message: S.tn(
        context,
        toActive
            ? 'Pengguna bisa login kembali.'
            : 'Pengguna tidak bisa login sampai diaktifkan lagi.',
      ),
      confirmLabel: S.tn(context, 'Ya'),
      cancelLabel: S.tn(context, 'Batal'),
    );
    if (confirmed) _quickUpdate(active: toActive);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = widget.user;
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
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy
                      ? null
                      : () async {
                          final updated = await showDialog<AppUser>(
                            context: context,
                            builder: (_) => _UserFormDialog(
                              existing: u,
                              roles: knownRoles,
                            ),
                          );
                          if (updated != null && context.mounted) {
                            Navigator.pop(context);
                            await widget.onChanged();
                          }
                        },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(
                    S.t(context, 'Ubah'),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _confirmToggleActive,
                  icon: Icon(
                    u.active ? Icons.block_outlined : Icons.check_circle,
                    size: 18,
                  ),
                  label: Text(
                    u.active
                        ? S.t(context, 'Nonaktifkan')
                        : S.t(context, 'Aktifkan'),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            ],
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
