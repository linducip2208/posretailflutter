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
      final response = await _api.get(
        '/held-orders',
        query: {'outlet_id': '$outletId'},
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
      await _api.post('/held-orders/${h.id}/resume');
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Transaksi dilanjutkan.'),
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
        'Data "${h.label}" akan dihapus dan tidak bisa dikembalikan.',
      ),
      confirmLabel: S.tn(context, 'Hapus'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await _sendDelete('/held-orders/${h.id}');
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
            '${S.tn(context, 'Kedaluwarsa')}: ${Fmt.dateTime(h.expiresAt)}',
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

/// Dialog buat hold: label + catatan cart sederhana → POST /held-orders.
class _HoldFormDialog extends StatefulWidget {
  final int outletId;

  const _HoldFormDialog({required this.outletId});

  @override
  State<_HoldFormDialog> createState() => _HoldFormDialogState();
}

class _HoldFormDialogState extends State<_HoldFormDialog> {
  final ApiService _api = ApiService();
  final _labelCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty) {
      setState(() => _error = S.tn(context, 'Label wajib diisi.'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _api.post(
        '/held-orders',
        body: {
          'outlet_id': widget.outletId,
          'label': label,
          'cart': {
            'items': [],
            if (_noteCtrl.text.trim().isNotEmpty)
              'note': _noteCtrl.text.trim(),
          },
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
              controller: _labelCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '${S.t(context, 'Label')} *',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: S.t(context, 'Catatan keranjang (opsional)'),
              ),
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
