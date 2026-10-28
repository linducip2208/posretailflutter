import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../../l10n/s.dart';
import '../../models/purchase_order.dart';
import '../../models/supplier.dart';
import '../../services/api_service.dart';
import '../../services/secure_token_storage.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/confirmation_dialog.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';

/// PUT/DELETE belum tersedia di [ApiService], jadi operasi tulis selain
/// POST dilakukan lewat [ApiService.client] langsung (tetap memakai token
/// dan pesan error manusiawi yang sama). GET/POST tetap via [ApiService].
/// Kontrak backend baru: `PUT /suppliers/{id}`
/// (`name?/contact_person?/phone?/email?/address?`) dan
/// `DELETE /suppliers/{id}` (409 bila masih punya PO). 404 berarti server
/// lama yang belum diperbarui — dilaporkan jujur.
Future<dynamic> _sendWrite(
  String method,
  String path, {
  Map<String, dynamic>? body,
}) async {
  String? token;
  try {
    token = await SecureTokenStorage().readToken();
  } catch (_) {
    token = null; // Storage tak tersedia (mis. widget test) — lanjut tanpa token.
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
        _httpMessage(response.statusCode),
    errors: decoded is Map ? decoded['errors'] : null,
  );
}

String _httpMessage(int status) {
  switch (status) {
    case 400:
      return 'Permintaan tidak valid.';
    case 401:
      return 'Sesi berakhir, silakan login kembali.';
    case 403:
      return 'Anda tidak memiliki akses.';
    case 404:
      return 'Data supplier tidak ditemukan di server.';
    case 409:
      return 'Data bentrok, coba lagi.';
    case 422:
      return 'Data tidak valid, periksa isian.';
    case 429:
      return 'Terlalu banyak percobaan, tunggu sebentar.';
    case 500:
      return 'Server bermasalah, coba lagi.';
    case 502:
    case 503:
      return 'Server sibuk, coba lagi.';
    default:
      if (status >= 500) return 'Server bermasalah, coba lagi.';
      return 'Request gagal.';
  }
}

/// Daftar supplier: pencarian server, pagination, tambah/ubah/hapus,
/// dan detail + riwayat PO via API nyata.
class SupplierListScreen extends StatefulWidget {
  const SupplierListScreen({super.key});

  @override
  State<SupplierListScreen> createState() => _SupplierListScreenState();
}

class _SupplierListScreenState extends State<SupplierListScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _debounce;

  List<Supplier> _suppliers = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients || _loadingMore || _page >= _lastPage) return;
    final position = _scrollCtrl.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _refresh);
  }

  Map<String, String?> _query(String page) => {
    'per_page': '50',
    'page': page,
    if (_searchCtrl.text.trim().isNotEmpty)
      'search': _searchCtrl.text.trim(),
  };

  static List<Supplier> _parseList(dynamic data) {
    final List<dynamic> rows;
    if (data is List) {
      rows = data;
    } else if (data is Map && data['data'] is List) {
      rows = data['data'] as List;
    } else {
      return [];
    }
    return rows.whereType<Map<String, dynamic>>().map(Supplier.fromJson).toList();
  }

  static int _metaInt(dynamic meta, String key) =>
      meta is Map ? (meta[key] as num?)?.toInt() ?? 0 : 0;

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.get('/suppliers', query: _query('1'));
      final data = response is Map ? response['data'] : response;
      final meta = response is Map ? response['meta'] : null;
      if (!mounted) return;
      setState(() {
        _suppliers = _parseList(data);
        _page = 1;
        _lastPage = _metaInt(meta, 'last_page');
        if (_lastPage < 1) _lastPage = 1;
        _total = _metaInt(meta, 'total');
        if (_total == 0 && meta == null) _total = _suppliers.length;
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
        _error = S.tn(context, 'Gagal memuat daftar supplier.');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_page >= _lastPage) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final response = await _api.get(
        '/suppliers',
        query: _query('$nextPage'),
      );
      final data = response is Map ? response['data'] : response;
      if (!mounted) return;
      setState(() {
        _suppliers = [..._suppliers, ..._parseList(data)];
        _page = nextPage;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _openCreateDialog() async {
    final created = await showDialog<Supplier>(
      context: context,
      builder: (_) => const _SupplierFormDialog(),
    );
    if (created == null || !mounted) return;
    showAppSnackbar(
      context,
      '${S.tn(context, 'Supplier')} "${created.name}" ${S.tn(context, 'tersimpan di server.')}',
      type: SnackType.success,
    );
    await _refresh();
  }

  Future<void> _openEditDialog(Supplier supplier) async {
    final updated = await showDialog<Supplier>(
      context: context,
      builder: (_) => _SupplierFormDialog(existing: supplier),
    );
    if (updated == null || !mounted) return;
    showAppSnackbar(
      context,
      S.tn(context, 'Supplier berhasil diperbarui.'),
      type: SnackType.success,
    );
    await _refresh();
  }

  Future<void> _delete(Supplier supplier) async {
    final confirmed = await confirmDialog(
      context,
      title: S.tn(context, 'Hapus supplier?'),
      message: S.tn(
        context,
        'Data {name} akan dihapus dari server dan tidak bisa dikembalikan.',
        {
          'name': supplier.name.isEmpty
              ? S.tn(context, 'supplier ini')
              : '"${supplier.name}"',
        },
      ),
      confirmLabel: S.tn(context, 'Hapus'),
      cancelLabel: S.tn(context, 'Batal'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _sendWrite('DELETE', '/suppliers/${supplier.id}');
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Supplier berhasil dihapus.'),
        type: SnackType.success,
      );
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        e.statusCode == 404
            ? S.tn(
                context,
                'Hapus supplier belum tersedia di server (mungkin belum diperbarui). Coba lagi nanti.',
              )
            : e.message,
        type: SnackType.error,
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Gagal menghapus supplier.'),
        type: SnackType.error,
      );
    }
  }

  Future<void> _openDetail(Supplier supplier) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SupplierDetailSheet(
        supplier: supplier,
        onEdit: _openEditDialog,
        onDelete: _delete,
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Supplier')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Tambah supplier'),
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
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: S.t(context, 'Cari nama, telepon, atau email...'),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _refresh();
                        },
                      ),
              ),
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _refresh(),
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
    if (_suppliers.isEmpty) {
      return EmptyState(
        icon: Icons.local_shipping_outlined,
        title: S.t(context, 'Tidak ada supplier'),
        message: S.t(
          context,
          'Tambah supplier baru dengan tombol di kanan atas.',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: _suppliers.length + 1,
        itemBuilder: (_, i) {
          if (i == _suppliers.length) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : Text(
                        '$_total ${S.t(context, 'supplier')}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
            );
          }
          return _supplierCard(_suppliers[i]);
        },
      ),
    );
  }

  Widget _supplierCard(Supplier supplier) {
    final theme = Theme.of(context);
    final contacts = [
      if (supplier.phone != null) supplier.phone!,
      if (supplier.email != null) supplier.email!,
    ].join(' · ');
    final displayName = supplier.name.isEmpty
        ? S.t(context, 'Tanpa nama')
        : supplier.name;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            displayName == '?' || displayName.isEmpty
                ? '?'
                : displayName.substring(0, 1).toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(
          displayName,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          contacts.isEmpty ? S.t(context, 'Tanpa kontak') : contacts,
          style: const TextStyle(fontSize: 11.5),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (supplier.poCount != null && supplier.poCount! > 0)
              StatusBadge(
                '${supplier.poCount} PO',
                tone: BadgeTone.info,
              ),
            PopupMenuButton<String>(
              tooltip: S.t(context, 'Aksi supplier'),
              onSelected: (value) {
                if (value == 'edit') {
                  _openEditDialog(supplier);
                } else if (value == 'delete') {
                  _delete(supplier);
                }
              },
              itemBuilder: (_) => [
                // itemBuilder dipanggil dari gesture handler (di luar fase
                // build), jadi pakai S.tn (read) bukan S.t (watch).
                PopupMenuItem(
                  value: 'edit',
                  child: Text(S.tn(context, 'Ubah')),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(S.tn(context, 'Hapus')),
                ),
              ],
            ),
          ],
        ),
        onTap: () => _openDetail(supplier),
      ),
    );
  }
}

/// Form tambah/ubah supplier (POST /suppliers, PUT /suppliers/{id}).
class _SupplierFormDialog extends StatefulWidget {
  final Supplier? existing;

  const _SupplierFormDialog({this.existing});

  @override
  State<_SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<_SupplierFormDialog> {
  final ApiService _api = ApiService();
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _contactCtrl = TextEditingController(
    text: widget.existing?.contactPerson ?? '',
  );
  late final TextEditingController _phoneCtrl = TextEditingController(
    text: widget.existing?.phone ?? '',
  );
  late final TextEditingController _emailCtrl = TextEditingController(
    text: widget.existing?.email ?? '',
  );
  late final TextEditingController _addressCtrl = TextEditingController(
    text: widget.existing?.address ?? '',
  );

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = S.tn(context, 'Nama wajib diisi.'));
      return;
    }
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty && !email.contains('@')) {
      setState(() => _error = S.tn(context, 'Format email tidak valid.'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        'name': name,
        // Kontrak backend: `contact_person` (nullable, max 255).
        if (_contactCtrl.text.trim().isNotEmpty)
          'contact_person': _contactCtrl.text.trim(),
        if (_phoneCtrl.text.trim().isNotEmpty)
          'phone': _phoneCtrl.text.trim(),
        if (email.isNotEmpty) 'email': email,
        if (_addressCtrl.text.trim().isNotEmpty)
          'address': _addressCtrl.text.trim(),
      };
      final dynamic response = _isEdit
          ? await _sendWrite('PUT', '/suppliers/${widget.existing!.id}', body: body)
          : await _api.post('/suppliers', body: body);
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      Supplier? result;
      if (data is Map<String, dynamic>) {
        result = Supplier.fromJson(data);
      } else if (_isEdit) {
        result = Supplier(
          id: widget.existing!.id,
          name: name,
          contactPerson: _contactCtrl.text.trim().isEmpty
              ? null
              : _contactCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isEmpty
              ? null
              : _phoneCtrl.text.trim(),
          email: email.isEmpty ? null : email,
          address: _addressCtrl.text.trim().isEmpty
              ? null
              : _addressCtrl.text.trim(),
        );
      }
      Navigator.pop(context, result);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // PUT /suppliers/{id} ada di backend baru; 404 berarti server
        // lama yang belum diperbarui — dilaporkan jujur.
        if (e.statusCode == 404 && _isEdit) {
          _error = S.tn(
            context,
            'Ubah supplier belum tersedia di server (mungkin belum diperbarui). Coba lagi nanti.',
          );
        } else {
          _error = e.statusCode == 422
              ? S.tn(
                  context,
                  'Data tidak valid. Pastikan email belum digunakan supplier lain.',
                )
              : e.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = S.tn(context, 'Gagal menyimpan supplier.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEdit ? S.t(context, 'Ubah Supplier') : S.t(context, 'Tambah Supplier'),
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
              key: const ValueKey('supplier_name_field'),
              controller: _nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '${S.t(context, 'Nama')} *',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('supplier_contact_field'),
              controller: _contactCtrl,
              decoration: InputDecoration(
                labelText: S.t(context, 'Kontak person'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('supplier_phone_field'),
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: S.t(context, 'Telepon')),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('supplier_email_field'),
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: S.t(context, 'Email')),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('supplier_address_field'),
              controller: _addressCtrl,
              maxLines: 2,
              decoration: InputDecoration(labelText: S.t(context, 'Alamat')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: Text(S.t(context, 'Batal')),
        ),
        FilledButton(
          key: const ValueKey('supplier_save_button'),
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

/// Detail supplier + riwayat PO dari server (GET /suppliers/{id}).
class _SupplierDetailSheet extends StatefulWidget {
  final Supplier supplier;
  final Future<void> Function(Supplier supplier) onEdit;
  final Future<void> Function(Supplier supplier) onDelete;

  const _SupplierDetailSheet({
    required this.supplier,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_SupplierDetailSheet> createState() => _SupplierDetailSheetState();
}

class _SupplierDetailSheetState extends State<_SupplierDetailSheet> {
  final ApiService _api = ApiService();
  late Supplier _supplier = widget.supplier;
  bool _reloading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final response = await _api.get('/suppliers/${_supplier.id}');
      final data = response is Map ? response['data'] : null;
      // GET /suppliers/{id} backend hanya mengembalikan `po_count`
      // (tanpa daftar PO), jadi riwayat diambil lewat filter yang didukung:
      // GET /purchase-orders?supplier_id={id}.
      List<SupplierPo> history = const [];
      try {
        final poResponse = await _api.get(
          '/purchase-orders',
          query: {'supplier_id': '${_supplier.id}', 'per_page': '20'},
        );
        final poData = poResponse is Map ? poResponse['data'] : poResponse;
        if (poData is List) {
          history = poData
              .whereType<Map<String, dynamic>>()
              .map(
                (m) => SupplierPo.fromJson({
                  'id': m['id'],
                  'po_number': m['po_number'] ?? m['number'],
                  'status': m['status'],
                  'total_amount':
                      m['total_amount'] ?? m['total_cost'] ?? m['total'],
                  'created_at': m['created_at'] ?? m['date'],
                }),
              )
              .toList();
        }
      } catch (_) {
        // Riwayat opsional: abaikan bila gagal, info supplier tetap tampil.
      }
      if (!mounted) return;
      setState(() {
        if (data is Map<String, dynamic>) {
          final parsed = Supplier.fromJson(data);
          _supplier = Supplier(
            id: parsed.id,
            name: parsed.name,
            contactPerson: parsed.contactPerson,
            phone: parsed.phone,
            email: parsed.email,
            address: parsed.address,
            poCount: parsed.poCount,
            createdAt: parsed.createdAt,
            purchaseOrders: history.isNotEmpty
                ? history
                : parsed.purchaseOrders,
          );
        }
        _reloading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _reloading = false);
      showAppSnackbar(context, e.message, type: SnackType.error);
    } catch (_) {
      // Abaikan: data lama tetap ditampilkan.
      if (!mounted) return;
      setState(() => _reloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _supplier;
    final displayName = s.name.isEmpty ? S.t(context, 'Tanpa nama') : s.name;

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
                  displayName.isEmpty
                      ? '?'
                      : displayName.substring(0, 1).toUpperCase(),
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
                      displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                      ),
                    ),
                    if (s.poCount != null && s.poCount! > 0)
                      StatusBadge('${s.poCount} PO', tone: BadgeTone.info),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _infoRow(context, S.t(context, 'Kontak person'), s.contactPerson),
          _infoRow(context, S.t(context, 'Telepon'), s.phone),
          _infoRow(context, S.t(context, 'Email'), s.email),
          _infoRow(context, S.t(context, 'Alamat'), s.address),
          const Divider(height: AppSpacing.xl),
          Text(
            S.t(context, 'Riwayat Pembelian (PO)'),
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_reloading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: CircularProgressIndicator(),
              ),
            )
          else if (s.purchaseOrders.isEmpty)
            Text(
              S.t(
                context,
                'Belum ada riwayat pembelian tercatat untuk supplier ini.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            )
          else
            ...s.purchaseOrders.map((po) => _poRow(context, po)),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await widget.onEdit(_supplier);
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
                  onPressed: () async {
                    Navigator.pop(context);
                    await widget.onDelete(_supplier);
                  },
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: AppColors.error,
                  ),
                  label: Text(
                    S.t(context, 'Hapus'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _poRow(BuildContext context, SupplierPo po) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        dense: true,
        title: Text(
          po.number,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          po.date ?? '-',
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              po.total == null ? '-' : Fmt.rupiah(po.total!),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (po.status != null && po.status!.isNotEmpty)
              StatusBadge(
                poStatusLabel(po.status!),
                tone: toneForPoStatus(po.status!),
              ),
          ],
        ),
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
