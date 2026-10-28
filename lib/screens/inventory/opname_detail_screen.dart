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

/// Detail sesi opname: lihat item (relasi `stockOpnameItems`) dan approve.
///
/// Kontrak backend: `GET /stock-opnames/{id}` (relasi
/// `stockOpnameItems.product`), `POST /stock-opnames` (sesi dibuat beserta
/// `items: [{product_id, actual_stock}]`), dan
/// `POST /stock-opnames/{id}/approve`. TIDAK ada endpoint tambah-item per
/// sesi — item dikirim sekali saat sesi dibuat, jadi layar ini tidak
/// menyediakan tombol tambah item. Bila GET detail 404 (server lama yang
/// belum diperbarui), data bawaan dari daftar tetap ditampilkan dengan
/// penanda jujur + tombol retry.
class OpnameDetailScreen extends StatefulWidget {
  final int opnameId;
  final StockOpname? initial;

  const OpnameDetailScreen({super.key, required this.opnameId, this.initial});

  @override
  State<OpnameDetailScreen> createState() => _OpnameDetailScreenState();
}

class _OpnameDetailScreenState extends State<OpnameDetailScreen> {
  final ApiService _api = ApiService();

  StockOpname? _session;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  /// True bila GET detail 404 (server lama tanpa endpoint detail) sehingga
  /// yang tampil adalah data bawaan dari daftar.
  bool _staleDetail = false;

  @override
  void initState() {
    super.initState();
    _session = widget.initial;
    if (widget.initial != null) _loading = false;
    _load();
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
          _staleDetail = false;
        } else if (_session != null) {
          // 200 tanpa data: pertahankan data daftar.
          _staleDetail = true;
          _error = null;
        } else {
          _error = S.tn(context, 'Sesi opname tidak ditemukan.');
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e.statusCode == 404 && _session != null) {
          // Server lama tanpa GET detail: tampilkan data daftar
          // dengan penanda jujur, bukan layar error kosong.
          _staleDetail = true;
          _error = null;
        } else {
          _error = e.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_session == null) {
          _error = S.tn(context, 'Gagal memuat detail opname.');
        }
      });
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
    final items = s.items ?? const <OpnameItem>[];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (_staleDetail)
            Card(
              color: AppColors.warningSoft,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        S.t(
                          context,
                          'Detail terbaru belum tersedia di server (404). Menampilkan data dari daftar.',
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: _load,
                      child: Text(S.t(context, 'Coba Lagi')),
                    ),
                  ],
                ),
              ),
            ),
          if (_staleDetail) const SizedBox(height: AppSpacing.md),
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
                      S.t(
                        context,
                        'Belum ada item. Buat sesi opname baru dengan item lengkap untuk menambah hitung fisik.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    ...items.map(_countedRow),
                ],
              ),
            ),
          ),
          if (s.status == 'pending')
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Text(
                S.t(
                  context,
                  'Sesi opname dibuat beserta itemnya. Untuk menambah item, buat sesi opname baru dengan item lengkap.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
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
    if (s.status != 'pending') return null;
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
