import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../../l10n/s.dart';
import '../../models/loyalty.dart';
import '../../services/api_service.dart';
import '../../services/secure_token_storage.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';

/// PUT via [ApiService.client] langsung (ApiService belum menyediakan PUT),
/// pola yang sama seperti supplier_list_screen.dart.
Future<dynamic> _sendPut(
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
    response = await ApiService.client
        .put(uri, headers: headers, body: body != null ? jsonEncode(body) : null)
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
    message:
        (decoded is Map && decoded['message'] != null
            ? decoded['message'].toString()
            : null) ??
        (response.statusCode == 404
            ? 'Data diskon tidak ditemukan di server.'
            : 'Request gagal.'),
    errors: decoded is Map ? decoded['errors'] : null,
  );
}

/// Daftar template diskon (GET /discounts?type=&active=),
/// tambah/ubah (POST/PUT /discounts), toggle aktif.
class DiscountListScreen extends StatefulWidget {
  const DiscountListScreen({super.key});

  @override
  State<DiscountListScreen> createState() => _DiscountListScreenState();
}

class _DiscountListScreenState extends State<DiscountListScreen> {
  final ApiService _api = ApiService();

  List<DiscountTemplate> _items = [];
  bool _loading = true;
  String? _error;
  String? _typeFilter; // null = semua
  String? _activeFilter; // null = semua
  bool _togglingId = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  static List<DiscountTemplate> parseList(dynamic data) {
    final List<dynamic> rows;
    if (data is List) {
      rows = data;
    } else if (data is Map && data['data'] is List) {
      rows = data['data'] as List;
    } else {
      return [];
    }
    return rows
        .whereType<Map<String, dynamic>>()
        .map(DiscountTemplate.fromJson)
        .toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.get(
        '/discounts',
        query: {
          if (_typeFilter != null) 'type': _typeFilter,
          if (_activeFilter != null) 'active': _activeFilter,
        },
      );
      final data = response is Map ? response['data'] : response;
      if (!mounted) return;
      setState(() {
        _items = parseList(data);
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
        _error = S.tn(context, 'Gagal memuat template diskon.');
      });
    }
  }

  Future<void> _openCreateDialog() async {
    final created = await showDialog<DiscountTemplate>(
      context: context,
      builder: (_) => const _DiscountFormDialog(),
    );
    if (created == null || !mounted) return;
    showAppSnackbar(
      context,
      '${S.tn(context, 'Diskon')} "${created.name}" ${S.tn(context, 'tersimpan di server.')}',
      type: SnackType.success,
    );
    await _refresh();
  }

  Future<void> _openEditDialog(DiscountTemplate item) async {
    final updated = await showDialog<DiscountTemplate>(
      context: context,
      builder: (_) => _DiscountFormDialog(existing: item),
    );
    if (updated == null || !mounted) return;
    showAppSnackbar(
      context,
      S.tn(context, 'Diskon berhasil diperbarui.'),
      type: SnackType.success,
    );
    await _refresh();
  }

  Future<void> _toggleActive(DiscountTemplate item) async {
    if (_togglingId) return;
    setState(() => _togglingId = true);
    try {
      await _sendPut('/discounts/${item.id}', body: {'active': !item.active});
      if (!mounted) return;
      showAppSnackbar(
        context,
        item.active
            ? S.tn(context, 'Diskon dinonaktifkan.')
            : S.tn(context, 'Diskon diaktifkan.'),
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
        S.tn(context, 'Gagal mengubah status diskon.'),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _togglingId = false);
    }
  }

  String _valueLabel(DiscountTemplate d) {
    switch (d.type) {
      case 'percent':
        return '${d.value.toStringAsFixed(d.value.truncateToDouble() == d.value ? 0 : 1)}%';
      case 'fixed':
        return Fmt.rupiah(d.value);
      case 'buy_x_get_y':
        return '${S.t(context, 'Beli')} ${d.buyQty} ${S.t(context, 'gratis')} ${d.getQty}';
      default:
        return '${d.value}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Template Diskon')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Tambah diskon'),
            onPressed: _openCreateDialog,
            icon: const Icon(Icons.add),
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
                  child: DropdownButtonFormField<String?>(
                    initialValue: _typeFilter,
                    decoration: InputDecoration(
                      labelText: S.t(context, 'Tipe'),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(S.t(context, 'Semua tipe')),
                      ),
                      DropdownMenuItem(
                        value: 'percent',
                        child: Text(discountTypeLabel('percent')),
                      ),
                      DropdownMenuItem(
                        value: 'fixed',
                        child: Text(discountTypeLabel('fixed')),
                      ),
                      DropdownMenuItem(
                        value: 'buy_x_get_y',
                        child: Text(discountTypeLabel('buy_x_get_y')),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _typeFilter = v);
                      _refresh();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _activeFilter,
                    decoration: InputDecoration(
                      labelText: S.t(context, 'Status'),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(S.t(context, 'Semua')),
                      ),
                      DropdownMenuItem(
                        value: '1',
                        child: Text(S.t(context, 'Aktif')),
                      ),
                      DropdownMenuItem(
                        value: '0',
                        child: Text(S.t(context, 'Nonaktif')),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _activeFilter = v);
                      _refresh();
                    },
                  ),
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
    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.discount_outlined,
        title: S.t(context, 'Tidak ada template diskon'),
        message: S.t(
          context,
          'Tambah template baru dengan tombol di kanan atas.',
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
        itemCount: _items.length,
        itemBuilder: (_, i) => _discountCard(_items[i]),
      ),
    );
  }

  Widget _discountCard(DiscountTemplate d) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primaryContainer,
          child: Icon(
            Icons.discount,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          d.name,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${discountTypeLabel(d.type)} · ${_valueLabel(d)}'
          '${d.minPurchase > 0 ? ' · min ${Fmt.rupiah(d.minPurchase)}' : ''}',
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: d.active,
              onChanged: _togglingId ? null : (_) => _toggleActive(d),
            ),
            PopupMenuButton<String>(
              tooltip: S.t(context, 'Aksi diskon'),
              onSelected: (value) {
                if (value == 'edit') _openEditDialog(d);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Text(S.t(context, 'Ubah')),
                ),
              ],
            ),
          ],
        ),
        onTap: () => _openEditDialog(d),
      ),
    );
  }
}

/// Form tambah/ubah template diskon.
/// POST/PUT /discounts {name, type, value, min_purchase?, buy_qty?,
/// get_qty?, start_at?, end_at?, active}
class _DiscountFormDialog extends StatefulWidget {
  final DiscountTemplate? existing;

  const _DiscountFormDialog({this.existing});

  @override
  State<_DiscountFormDialog> createState() => _DiscountFormDialogState();
}

class _DiscountFormDialogState extends State<_DiscountFormDialog> {
  final ApiService _api = ApiService();
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _valueCtrl = TextEditingController(
    text: widget.existing == null
        ? ''
        : widget.existing!.value.truncateToDouble() == widget.existing!.value
        ? '${widget.existing!.value.toInt()}'
        : '${widget.existing!.value}',
  );
  late final TextEditingController _minCtrl = TextEditingController(
    text: widget.existing == null || widget.existing!.minPurchase <= 0
        ? ''
        : '${widget.existing!.minPurchase.toInt()}',
  );
  late final TextEditingController _buyCtrl = TextEditingController(
    text: widget.existing == null || widget.existing!.buyQty <= 0
        ? ''
        : '${widget.existing!.buyQty}',
  );
  late final TextEditingController _getCtrl = TextEditingController(
    text: widget.existing == null || widget.existing!.getQty <= 0
        ? ''
        : '${widget.existing!.getQty}',
  );
  late String _type = widget.existing?.type ?? 'percent';
  late bool _active = widget.existing?.active ?? true;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _valueCtrl.dispose();
    _minCtrl.dispose();
    _buyCtrl.dispose();
    _getCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = S.tn(context, 'Nama wajib diisi.'));
      return;
    }
    final value = double.tryParse(_valueCtrl.text.trim());
    if (_type != 'buy_x_get_y' && (value == null || value < 0)) {
      setState(() => _error = S.tn(context, 'Nilai diskon tidak valid.'));
      return;
    }
    if (_type == 'percent' && value != null && value > 100) {
      setState(
        () => _error = S.tn(context, 'Diskon persen maksimal 100.'),
      );
      return;
    }
    int? buyQty;
    int? getQty;
    if (_type == 'buy_x_get_y') {
      buyQty = int.tryParse(_buyCtrl.text.trim());
      getQty = int.tryParse(_getCtrl.text.trim());
      if (buyQty == null || buyQty <= 0 || getQty == null || getQty <= 0) {
        setState(
          () => _error = S.tn(context, 'Isi beli X dan gratis Y (> 0).'),
        );
        return;
      }
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        'name': name,
        'type': _type,
        if (_type != 'buy_x_get_y') 'value': value,
        ...?(_minCtrl.text.trim().isNotEmpty
            ? {
                'min_purchase': double.tryParse(_minCtrl.text.trim()) ?? 0,
              }
            : null),
        ...?buyQty != null ? {'buy_qty': buyQty} : null,
        ...?getQty != null ? {'get_qty': getQty} : null,
        'active': _active,
      };
      final dynamic response = _isEdit
          ? await _sendPut('/discounts/${widget.existing!.id}', body: body)
          : await _api.post('/discounts', body: body);
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      DiscountTemplate? result;
      if (data is Map<String, dynamic>) {
        result = DiscountTemplate.fromJson(data);
      } else if (_isEdit) {
        result = DiscountTemplate(
          id: widget.existing!.id,
          name: name,
          type: _type,
          value: value ?? 0,
          active: _active,
        );
      }
      Navigator.pop(context, result);
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
        _error = S.tn(context, 'Gagal menyimpan diskon.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEdit ? S.t(context, 'Ubah Diskon') : S.t(context, 'Tambah Diskon'),
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
              key: const ValueKey('discount_name_field'),
              controller: _nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '${S.t(context, 'Nama')} *',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: InputDecoration(labelText: S.t(context, 'Tipe')),
              items: const [
                DropdownMenuItem(value: 'percent', child: Text('Persen (%)')),
                DropdownMenuItem(value: 'fixed', child: Text('Nominal (Rp)')),
                DropdownMenuItem(
                  value: 'buy_x_get_y',
                  child: Text('Beli X Gratis Y'),
                ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _type = v);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            if (_type == 'buy_x_get_y') ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _buyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '${S.t(context, 'Beli (X)')} *',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _getCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '${S.t(context, 'Gratis (Y)')} *',
                      ),
                    ),
                  ),
                ],
              ),
            ] else
              TextField(
                key: const ValueKey('discount_value_field'),
                controller: _valueCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _type == 'percent'
                      ? '${S.t(context, 'Nilai (%)')} *'
                      : '${S.t(context, 'Nilai (Rp)')} *',
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _minCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: S.t(context, 'Min. belanja (Rp, opsional)'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              title: Text(S.t(context, 'Aktif')),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              contentPadding: EdgeInsets.zero,
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
          key: const ValueKey('discount_save_button'),
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
