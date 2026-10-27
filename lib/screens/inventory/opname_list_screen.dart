import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/s.dart';
import '../../models/inventory_ops.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';
import 'opname_detail_screen.dart';

/// Daftar sesi stock opname: filter status, pagination,
/// buka sesi baru, dan navigasi ke detail penghitungan.
class OpnameListScreen extends StatefulWidget {
  /// Outlet eksplisit agar layar testable tanpa [AuthProvider].
  final int? outletId;

  const OpnameListScreen({super.key, this.outletId});

  @override
  State<OpnameListScreen> createState() => _OpnameListScreenState();
}

class _OpnameListScreenState extends State<OpnameListScreen> {
  static const _filters = ['semua', 'draft', 'counted', 'approved', 'cancelled'];

  final ApiService _api = ApiService();
  final ScrollController _scrollCtrl = ScrollController();

  List<StockOpname> _sessions = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String _statusFilter = 'semua';
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
    _scrollCtrl.dispose();
    super.dispose();
  }

  int? _resolveOutletId() {
    if (widget.outletId != null) return widget.outletId;
    try {
      return context.read<AuthProvider>().currentOutletId;
    } catch (_) {
      return null;
    }
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients || _loadingMore || _page >= _lastPage) return;
    final position = _scrollCtrl.position;
    if (position.pixels >= position.maxScrollExtent - 300) _loadMore();
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
        '/stock-opnames',
        query: {
          'outlet_id': '$outletId',
          'per_page': '50',
          'page': '1',
          if (_statusFilter != 'semua') 'status': _statusFilter,
        },
      );
      final data = response is Map ? response['data'] : null;
      final meta = response is Map ? response['meta'] : null;
      if (!mounted) return;
      setState(() {
        _sessions = data is List
            ? data
                  .whereType<Map<String, dynamic>>()
                  .map(StockOpname.fromJson)
                  .toList()
            : [];
        _page = 1;
        _lastPage = meta is Map ? (meta['last_page'] as num?)?.toInt() ?? 1 : 1;
        _total = meta is Map ? (meta['total'] as num?)?.toInt() ?? 0 : 0;
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
        _error = S.tn(context, 'Gagal memuat sesi opname.');
      });
    }
  }

  Future<void> _loadMore() async {
    final outletId = _resolveOutletId();
    if (outletId == null || _page >= _lastPage) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final response = await _api.get(
        '/stock-opnames',
        query: {
          'outlet_id': '$outletId',
          'per_page': '50',
          'page': '$nextPage',
          if (_statusFilter != 'semua') 'status': _statusFilter,
        },
      );
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      setState(() {
        if (data is List) {
          _sessions = [
            ..._sessions,
            ...data.whereType<Map<String, dynamic>>().map(StockOpname.fromJson),
          ];
        }
        _page = nextPage;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
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
      builder: (_) => _OpnameCreateDialog(outletId: outletId),
    );
    if (created == true && mounted) {
      showAppSnackbar(
        context,
        S.tn(context, 'Sesi opname dibuka.'),
        type: SnackType.success,
      );
      await _refresh();
    }
  }

  Future<void> _openDetail(StockOpname session) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OpnameDetailScreen(
          opnameId: session.id,
          initial: session,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Stock Opname')),
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
        icon: const Icon(Icons.add),
        label: Text(S.t(context, 'Buka Sesi')),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: _filters.map((f) {
                final selected = _statusFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    label: Text(
                      f == 'semua'
                          ? S.t(context, 'Semua')
                          : opnameStatusLabel(f),
                    ),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _statusFilter = f);
                      _refresh();
                    },
                  ),
                );
              }).toList(),
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
    if (_sessions.isEmpty) {
      return EmptyState(
        icon: Icons.fact_check_outlined,
        title: S.t(context, 'Tidak ada sesi opname'),
        message: S.t(context, 'Buka sesi baru untuk mulai menghitung stok.'),
        actionLabel: S.t(context, 'Buka Sesi'),
        onAction: _openCreateDialog,
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
        itemCount: _sessions.length + 1,
        itemBuilder: (_, i) {
          if (i == _sessions.length) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : Text(
                        '$_total ${S.t(context, 'sesi')}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
            );
          }
          return _sessionCard(_sessions[i]);
        },
      ),
    );
  }

  Widget _sessionCard(StockOpname s) {
    final itemCount = s.items?.length ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.fact_check_outlined, size: 20),
        ),
        title: Text(
          s.displayTitle,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (itemCount > 0) '$itemCount item',
            Fmt.date(s.createdAt),
          ].join(' · '),
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: StatusBadge(
          opnameStatusLabel(s.status),
          tone: toneForOpnameStatus(s.status),
        ),
        onTap: () => _openDetail(s),
      ),
    );
  }
}

/// Dialog buka sesi: POST /stock-opnames {outlet_id, note?}.
class _OpnameCreateDialog extends StatefulWidget {
  final int outletId;

  const _OpnameCreateDialog({required this.outletId});

  @override
  State<_OpnameCreateDialog> createState() => _OpnameCreateDialogState();
}

class _OpnameCreateDialogState extends State<_OpnameCreateDialog> {
  final ApiService _api = ApiService();
  final _noteCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _api.post(
        '/stock-opnames',
        body: {
          'outlet_id': widget.outletId,
          if (_noteCtrl.text.trim().isNotEmpty) 'note': _noteCtrl.text.trim(),
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
        _error = S.tn(context, 'Gagal membuka sesi opname.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.t(context, 'Buka Sesi Opname')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.errorSoft,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(_error!, style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Text(
            S.t(context, 'Sesi baru mencatat stok sistem saat ini sebagai acuan hitung fisik.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: S.t(context, 'Catatan (opsional)'),
            ),
          ),
        ],
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
              : Text(S.t(context, 'Buka')),
        ),
      ],
    );
  }
}
