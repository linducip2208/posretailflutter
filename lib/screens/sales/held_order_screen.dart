import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../config/api_config.dart';
import '../../l10n/s.dart';
import '../../models/sales_ops.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/secure_token_storage.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/confirmation_dialog.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';

/// DELETE via [ApiService.client] langsung (ApiService belum punya delete).
Future<dynamic> _sendDelete(String path) async {
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
    response = await ApiService.client
        .delete(uri, headers: headers)
        .timeout(ApiConfig.requestTimeout);
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
    message: (decoded is Map && decoded['message'] != null
            ? decoded['message'].toString()
            : null) ??
        'Request gagal.',
    errors: decoded is Map ? decoded['errors'] : null,
  );
}

/// Daftar transaksi hold: buat, resume, hapus (auto-expire 24 jam server).
class HeldOrderScreen extends StatefulWidget {
  final int? outletId;

  const HeldOrderScreen({super.key, this.outletId});

  @override
  State<HeldOrderScreen> createState() => _HeldOrderScreenState();
}

class _HeldOrderScreenState extends State<HeldOrderScreen> {
  final ApiService _api = ApiService();

  List<HeldOrder> _holds = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  int? _resolveOutletId() {
    if (widget.outletId != null) return widget.outletId;
    try {
      return context.read<AuthProvider>().currentOutletId;
    } catch (_) {
      return null;
    }
  }

  Future<void> _refresh() async {
    final outletId = _resolveOutletId();
    if (outletId == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = S.tn(context, 'Pilih outlet dulu.');
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Backend: GET /held-carts (hanya per_page; scope outlet + user
      // diambil dari token, bukan query).
      final response = await _api.get(
        '/held-carts',
        query: {'per_page': '50'},
      );
      final data = response is Map ? response['data'] : response;
      if (!mounted) return;
      setState(() {
        _holds = data is List
            ? data
                  .whereType<Map<String, dynamic>>()
                  .map(HeldOrder.fromJson)
                  .toList()
            : [];
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
        _error = S.tn(context, 'Gagal memuat transaksi hold.');
      });
    }
  }

  Future<void> _openCreateDialog() async {
    final outletId = _resolveOutletId();
    if (outletId == null) {
      showAppSnackbar(
        context,
        S.tn(context, 'Pilih outlet dulu.'),
        type: SnackType.warning,
      );
      return;
    }
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _HoldFormDialog(outletId: outletId),
    );
    if (created == true && mounted) {
      showAppSnackbar(
        context,
        S.tn(context, 'Transaksi ditahan.'),
        type: SnackType.success,
      );
      await _refresh();
    }
  }

  Future<void> _resume(HeldOrder h) async {
    final ok = await confirmDialog(
      context,
      title: S.tn(context, 'Lanjutkan transaksi ini?'),
      message: S.tn(context, 'Keranjang hold akan dibuka kembali di kasir.'),
      confirmLabel: S.tn(context, 'Lanjutkan'),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      // Backend mengembalikan {data: heldCart}; tanpa integrasi POS di
      // luar cakupan — cukup sukses + instruksi buka kembali di kasir.
      final response = await _api.post('/held-carts/${h.id}/resume');
      final data = response is Map ? response['data'] : null;
      final resumed = data is Map<String, dynamic>
          ? HeldOrder.fromJson(data)
          : h;
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Transaksi dilanjutkan ({count} item). Buka kembali di kasir.', {
          'count': '${resumed.itemCount}',
        }),
        type: SnackType.success,
      );
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackbar(context, e.message, type: SnackType.error);
    } catch (_) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Gagal melanjutkan transaksi.'),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(HeldOrder h) async {
    final ok = await confirmDialog(
      context,
      title: S.tn(context, 'Hapus transaksi hold?'),
      message: S.tn(
        context,
        'Data "{name}" akan dihapus dan tidak bisa dikembalikan.',
        {'name': h.label},
      ),
      confirmLabel: S.tn(context, 'Hapus'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await _sendDelete('/held-carts/${h.id}');
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Transaksi hold dihapus.'),
        type: SnackType.success,
      );
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackbar(context, e.message, type: SnackType.error);
    } catch (_) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Gagal menghapus transaksi.'),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Tahan Transaksi')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Muat ulang'),
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateDialog,
        icon: const Icon(Icons.pause_circle_outline),
        label: Text(S.t(context, 'Tahan')),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingSkeleton(items: 6, itemHeight: 64);
    if (_error != null) return ErrorState(message: _error!, onRetry: _refresh);
    if (_holds.isEmpty) {
      return EmptyState(
        icon: Icons.pause_circle_outline,
        title: S.t(context, 'Tidak ada transaksi hold'),
        message: S.t(context, 'Tahan transaksi aktif dari kasir.'),
        actionLabel: S.t(context, 'Tahan Baru'),
        onAction: _openCreateDialog,
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: _holds.length,
        itemBuilder: (_, i) => _holdCard(_holds[i]),
      ),
    );
  }

  Widget _holdCard(HeldOrder h) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.pause_circle_outline, size: 20),
        ),
        title: Text(
          h.label,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (h.itemCount > 0) '${h.itemCount} item',
            Fmt.dateTime(h.createdAt),
          ].join(' · '),
          style: const TextStyle(fontSize: 11.5),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: S.t(context, 'Lanjutkan'),
              onPressed: _busy ? null : () => _resume(h),
              icon: const Icon(Icons.play_circle_outline),
            ),
            IconButton(
              tooltip: S.t(context, 'Hapus'),
              onPressed: _busy ? null : () => _delete(h),
              icon: const Icon(
                Icons.delete_outline,
                size: 20,
                color: AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog buat hold: label opsional + baris item sederhana
/// → POST /held-carts {outlet_id, label?, items[]}.
/// Backend mewajibkan items (min 1); label opsional.
class _HoldFormDialog extends StatefulWidget {
  final int outletId;

  const _HoldFormDialog({required this.outletId});

  @override
  State<_HoldFormDialog> createState() => _HoldFormDialogState();
}

class _DraftHoldItem {
  int productId;
  int qty;

  _DraftHoldItem({required this.productId, required this.qty});
}

class _HoldFormDialogState extends State<_HoldFormDialog> {
  final ApiService _api = ApiService();
  final _labelCtrl = TextEditingController();
  final List<_DraftHoldItem> _items = [
    _DraftHoldItem(productId: 0, qty: 1),
  ];
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final items = _items
        .where((e) => e.productId > 0 && e.qty > 0)
        .map((e) => {'product_id': e.productId, 'qty': e.qty})
        .toList();
    if (items.isEmpty) {
      setState(
        () => _error = S.tn(context, 'Tambahkan minimal satu item valid.'),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final label = _labelCtrl.text.trim();
      await _api.post(
        '/held-carts',
        body: {
          'outlet_id': widget.outletId,
          if (label.isNotEmpty) 'label': label,
          'items': items,
        },
      );
      if (!mounted) return;
      Navigator.pop(context, true);
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
        _error = S.tn(context, 'Gagal menahan transaksi.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.t(context, 'Tahan Transaksi')),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                controller: _labelCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: S.t(context, 'Label (opsional)'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                S.t(context, 'Item keranjang'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ..._items.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          key: ValueKey('hold_product_$idx'),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: S.t(context, 'ID Produk'),
                            isDense: true,
                          ),
                          controller: TextEditingController(
                            text: item.productId == 0
                                ? ''
                                : '${item.productId}',
                          ),
                          onChanged: (v) =>
                              item.productId = int.tryParse(v.trim()) ?? 0,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          key: ValueKey('hold_qty_$idx'),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: S.t(context, 'Qty'),
                            isDense: true,
                          ),
                          controller: TextEditingController(
                            text: '${item.qty}',
                          ),
                          onChanged: (v) =>
                              item.qty = int.tryParse(v.trim()) ?? 0,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: _items.length <= 1
                            ? null
                            : () => setState(() => _items.removeAt(idx)),
                      ),
                    ],
                  ),
                );
              }),
              TextButton.icon(
                onPressed: () => setState(
                  () => _items.add(_DraftHoldItem(productId: 0, qty: 1)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: Text(S.t(context, 'Tambah item')),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: Text(S.t(context, 'Batal')),
        ),
        FilledButton(
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
              : Text(S.t(context, 'Tahan')),
        ),
      ],
    );
  }
}
