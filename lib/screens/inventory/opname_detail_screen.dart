import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../models/inventory_ops.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/confirmation_dialog.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';

/// Detail sesi opname: input qty fisik per item (cari produk),
/// kirim hasil hitung, dan approve dengan konfirmasi.
class OpnameDetailScreen extends StatefulWidget {
  final int opnameId;
  final StockOpname? initial;

  const OpnameDetailScreen({super.key, required this.opnameId, this.initial});

  @override
  State<OpnameDetailScreen> createState() => _OpnameDetailScreenState();
}

class _OpnameDetailScreenState extends State<OpnameDetailScreen> {
  final ApiService _api = ApiService();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  StockOpname? _session;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  List<Map<String, dynamic>> _foundProducts = [];
  bool _searching = false;
  final List<OpnameItem> _draft = [];

  @override
  void initState() {
    super.initState();
    _session = widget.initial;
    if (widget.initial != null) _loading = false;
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_session == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await _api.get('/stock-opnames/${widget.opnameId}');
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (data is Map<String, dynamic>) {
          _session = StockOpname.fromJson(data);
          _error = null;
        } else {
          _error = S.tn(context, 'Sesi opname tidak ditemukan.');
        }
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
        _error = S.tn(context, 'Gagal memuat detail opname.');
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _searchProducts);
  }

  Future<void> _searchProducts() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _foundProducts = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final response = await _api.get('/products', query: {'search': q});
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      setState(() {
        _foundProducts = data is List
            ? data.whereType<Map<String, dynamic>>().toList()
            : [];
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  Future<void> _addProduct(Map<String, dynamic> raw) async {
    int id = 0;
    final rawId = raw['id'];
    if (rawId is int) {
      id = rawId;
    } else if (rawId is num) {
      id = rawId.toInt();
    } else {
      id = int.tryParse(rawId?.toString() ?? '') ?? 0;
    }
    final name = raw['name']?.toString() ?? 'Produk #$id';
    final qty = await showDialog<double>(
      context: context,
      builder: (_) => _PhysicalQtyDialog(productName: name),
    );
    if (qty == null || !mounted) return;
    setState(() {
      final existing = _draft.indexWhere((e) => e.productId == id);
      final item = OpnameItem(
        productId: id,
        productName: name,
        systemQty: 0,
        physicalQty: qty,
        diff: qty,
      );
      if (existing >= 0) {
        _draft[existing] = item;
      } else {
        _draft.add(item);
      }
      _searchCtrl.clear();
      _foundProducts = [];
    });
  }

  Future<void> _submitCount() async {
    if (_draft.isEmpty) {
      showAppSnackbar(
        context,
        S.tn(context, 'Tambahkan minimal satu item hitung fisik.'),
        type: SnackType.warning,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _api.post(
        '/stock-opnames/${widget.opnameId}/items',
        body: {
          'items': _draft.map((e) => e.toJson()).toList(),
        },
      );
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Hasil hitung tersimpan.'),
        type: SnackType.success,
      );
      setState(() => _draft.clear());
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackbar(context, e.message, type: SnackType.error);
    } catch (_) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Gagal menyimpan hasil hitung.'),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmAndApprove() async {
    final s = _session;
    final surplus = s?.totalSurplus ?? 0;
    final deficit = s?.totalDeficit ?? 0;
    final ok = await confirmDialog(
      context,
      title: S.tn(context, 'Setujui hasil opname?'),
      message: S.tn(
        context,
        'Koreksi stok akan diterapkan dan tercatat sebagai mutasi. Surplus: {p}, Defisit: {d}.',
        {'p': _fmtQty(surplus), 'd': _fmtQty(deficit)},
      ),
      confirmLabel: S.tn(context, 'Setujui'),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.post('/stock-opnames/${widget.opnameId}/approve');
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Opname disetujui. Stok dikoreksi.'),
        type: SnackType.success,
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackbar(context, e.message, type: SnackType.error);
    } catch (_) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Gagal menyetujui opname.'),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _fmtQty(double v) =>
      v == v.toInt() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return Scaffold(
      appBar: AppBar(
        title: Text(s?.displayTitle ?? S.t(context, 'Detail Opname')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Muat ulang'),
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(s),
      bottomNavigationBar: s == null ? null : _buildActions(s),
    );
  }

  Widget _buildBody(StockOpname? s) {
    if (_loading && s == null) {
      return const LoadingSkeleton(items: 5, itemHeight: 64);
    }
    if (s == null) {
      return ErrorState(
        message: _error ?? S.tn(context, 'Sesi opname tidak ditemukan.'),
        icon: Icons.fact_check_outlined,
        onRetry: _load,
      );
    }
    final editable = s.status == 'draft' || s.status == 'counted';
    final items = s.items ?? const <OpnameItem>[];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.displayTitle,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontSize: 16),
                        ),
                      ),
                      StatusBadge(
                        opnameStatusLabel(s.status),
                        tone: toneForOpnameStatus(s.status),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _infoRow(S.t(context, 'Tanggal'), Fmt.dateTime(s.createdAt)),
                  if (s.note != null && s.note!.isNotEmpty)
                    _infoRow(S.t(context, 'Catatan'), s.note!),
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _infoRow(
                      S.t(context, 'Surplus'),
                      '+${_fmtQty(s.totalSurplus)}',
                    ),
                    _infoRow(
                      S.t(context, 'Defisit'),
                      _fmtQty(s.totalDeficit),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.t(context, 'Hasil hitung'),
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (items.isEmpty)
                    Text(
                      S.t(context, 'Belum ada item. Tambahkan hitung fisik di bawah.'),
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    ...items.map(_countedRow),
                ],
              ),
            ),
          ),
          if (editable) ...[
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.t(context, 'Tambah hitung fisik'),
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        labelText: S.t(context, 'Cari produk'),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                      ),
                      onChanged: _onSearchChanged,
                    ),
                    if (_searching)
                      const Padding(
                        padding: EdgeInsets.all(AppSpacing.sm),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else
                      ..._foundProducts.map(
                        (p) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            p['name']?.toString() ?? '-',
                            style: const TextStyle(fontSize: 13),
                          ),
                          trailing: const Icon(Icons.add, size: 20),
                          onTap: () => _addProduct(p),
                        ),
                      ),
                    if (_draft.isEmpty)
                      Text(
                        S.t(context, 'Belum ada item baru.'),
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else
                      ..._draft.map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (e.productName?.isNotEmpty ?? false)
                                      ? e.productName!
                                      : 'Produk #${e.productId}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${S.t(context, 'Fisik')}: ${_fmtQty(e.physicalQty)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    setState(() => _draft.remove(e)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _submitCount,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: Text(S.t(context, 'Simpan hasil hitung')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _countedRow(OpnameItem item) {
    final positive = item.diff > 0;
    final zero = item.diff == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (item.productName?.isNotEmpty ?? false)
                      ? item.productName!
                      : 'Produk #${item.productId}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${S.t(context, 'Sistem')}: ${_fmtQty(item.systemQty)} · ${S.t(context, 'Fisik')}: ${_fmtQty(item.physicalQty)}',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ],
            ),
          ),
          Text(
            '${item.diff > 0 ? '+' : ''}${_fmtQty(item.diff)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: zero
                  ? Theme.of(context).textTheme.bodySmall?.color
                  : (positive ? AppColors.success : AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildActions(StockOpname s) {
    if (s.status != 'draft' && s.status != 'counted') return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: FilledButton.icon(
          onPressed: _busy ? null : _confirmAndApprove,
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: Text(S.t(context, 'Setujui & Koreksi Stok')),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog qty fisik untuk satu produk.
class _PhysicalQtyDialog extends StatefulWidget {
  final String productName;

  const _PhysicalQtyDialog({required this.productName});

  @override
  State<_PhysicalQtyDialog> createState() => _PhysicalQtyDialogState();
}

class _PhysicalQtyDialogState extends State<_PhysicalQtyDialog> {
  final _qtyCtrl = TextEditingController(text: '1');

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.productName, style: const TextStyle(fontSize: 15)),
      content: TextField(
        controller: _qtyCtrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: S.t(context, 'Qty fisik')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(S.t(context, 'Batal')),
        ),
        FilledButton(
          onPressed: () {
            final qty =
                double.tryParse(_qtyCtrl.text.trim().replaceAll(',', '.')) ??
                -1;
            if (qty < 0) return;
            Navigator.pop(context, qty);
          },
          child: Text(S.t(context, 'Tambah')),
        ),
      ],
    );
  }
}
