import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../../l10n/s.dart';
import '../../models/customer.dart';
import '../../models/loyalty.dart';
import '../../services/api_service.dart';
import '../../services/secure_token_storage.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';

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
            ? 'Data reward tidak ditemukan di server.'
            : 'Request gagal.'),
    errors: decoded is Map ? decoded['errors'] : null,
  );
}

/// Katalog reward loyalitas (GET /loyalty-rewards?active=),
/// tambah/ubah (POST/PUT), redeem untuk customer,
/// dan lihat saldo poin (GET /loyalty-points?customer_id=).
class RewardListScreen extends StatefulWidget {
  const RewardListScreen({super.key});

  @override
  State<RewardListScreen> createState() => _RewardListScreenState();
}

class _RewardListScreenState extends State<RewardListScreen> {
  final ApiService _api = ApiService();

  List<LoyaltyReward> _rewards = [];
  bool _loading = true;
  String? _error;
  String? _activeFilter; // null = semua, '1' = aktif, '0' = nonaktif

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  static List<LoyaltyReward> parseList(dynamic data) {
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
        .map(LoyaltyReward.fromJson)
        .toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.get(
        '/loyalty-rewards',
        query: {if (_activeFilter != null) 'active': _activeFilter},
      );
      final data = response is Map ? response['data'] : response;
      if (!mounted) return;
      setState(() {
        _rewards = parseList(data);
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
        _error = S.tn(context, 'Gagal memuat katalog reward.');
      });
    }
  }

  Future<void> _openCreateDialog() async {
    final created = await showDialog<LoyaltyReward>(
      context: context,
      builder: (_) => const _RewardFormDialog(),
    );
    if (created == null || !mounted) return;
    showAppSnackbar(
      context,
      '${S.tn(context, 'Reward')} "${created.name}" ${S.tn(context, 'tersimpan di server.')}',
      type: SnackType.success,
    );
    await _refresh();
  }

  Future<void> _openEditDialog(LoyaltyReward reward) async {
    final updated = await showDialog<LoyaltyReward>(
      context: context,
      builder: (_) => _RewardFormDialog(existing: reward),
    );
    if (updated == null || !mounted) return;
    showAppSnackbar(
      context,
      S.tn(context, 'Reward berhasil diperbarui.'),
      type: SnackType.success,
    );
    await _refresh();
  }

  Future<void> _openRedeemDialog(LoyaltyReward reward) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _RedeemDialog(reward: reward),
    );
    if (ok == true && mounted) await _refresh();
  }

  Future<void> _openBalanceDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _BalanceDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Poin & Reward')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Cek saldo poin'),
            onPressed: _openBalanceDialog,
            icon: const Icon(Icons.account_balance_wallet_outlined),
          ),
          IconButton(
            tooltip: S.t(context, 'Tambah reward'),
            onPressed: _openCreateDialog,
            icon: const Icon(Icons.card_giftcard_outlined),
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
                  child: SegmentedButton<String?>(
                    segments: [
                      ButtonSegment(
                        value: null,
                        label: Text(S.t(context, 'Semua')),
                      ),
                      ButtonSegment(
                        value: '1',
                        label: Text(S.t(context, 'Aktif')),
                      ),
                      ButtonSegment(
                        value: '0',
                        label: Text(S.t(context, 'Nonaktif')),
                      ),
                    ],
                    selected: {_activeFilter},
                    onSelectionChanged: (v) {
                      setState(() => _activeFilter = v.first);
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
    if (_rewards.isEmpty) {
      return EmptyState(
        icon: Icons.card_giftcard_outlined,
        title: S.t(context, 'Tidak ada reward'),
        message: S.t(
          context,
          'Tambah reward baru dengan tombol di kanan atas.',
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
        itemCount: _rewards.length,
        itemBuilder: (_, i) => _rewardCard(_rewards[i]),
      ),
    );
  }

  Widget _rewardCard(LoyaltyReward reward) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.card_giftcard,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          reward.name,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${reward.pointsCost} ${S.t(context, 'poin')} · ${S.t(context, 'Stok')}: ${reward.stock}',
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusBadge(
              reward.active ? S.t(context, 'Aktif') : S.t(context, 'Nonaktif'),
              tone: toneForRewardActive(reward.active),
            ),
            PopupMenuButton<String>(
              tooltip: S.t(context, 'Aksi reward'),
              onSelected: (value) {
                if (value == 'edit') {
                  _openEditDialog(reward);
                } else if (value == 'redeem') {
                  _openRedeemDialog(reward);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'redeem',
                  child: Text(S.t(context, 'Redeem')),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: Text(S.t(context, 'Ubah')),
                ),
              ],
            ),
          ],
        ),
        onTap: () => _openRedeemDialog(reward),
      ),
    );
  }
}

/// Form tambah/ubah reward (POST /loyalty-rewards, PUT /loyalty-rewards/{id}).
class _RewardFormDialog extends StatefulWidget {
  final LoyaltyReward? existing;

  const _RewardFormDialog({this.existing});

  @override
  State<_RewardFormDialog> createState() => _RewardFormDialogState();
}

class _RewardFormDialogState extends State<_RewardFormDialog> {
  final ApiService _api = ApiService();
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _pointsCtrl = TextEditingController(
    text: widget.existing == null ? '' : '${widget.existing!.pointsCost}',
  );
  late final TextEditingController _stockCtrl = TextEditingController(
    text: widget.existing == null ? '' : '${widget.existing!.stock}',
  );
  late bool _active = widget.existing?.active ?? true;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pointsCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = S.tn(context, 'Nama wajib diisi.'));
      return;
    }
    final points = int.tryParse(_pointsCtrl.text.trim()) ?? -1;
    if (points < 0) {
      setState(
        () => _error = S.tn(context, 'Biaya poin harus angka >= 0.'),
      );
      return;
    }
    final stock = int.tryParse(_stockCtrl.text.trim()) ?? -1;
    if (stock < 0) {
      setState(() => _error = S.tn(context, 'Stok harus angka >= 0.'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        'name': name,
        'points_cost': points,
        'stock': stock,
        'active': _active,
      };
      final dynamic response = _isEdit
          ? await _sendPut('/loyalty-rewards/${widget.existing!.id}', body: body)
          : await _api.post('/loyalty-rewards', body: body);
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      LoyaltyReward? result;
      if (data is Map<String, dynamic>) {
        result = LoyaltyReward.fromJson(data);
      } else if (_isEdit) {
        result = LoyaltyReward(
          id: widget.existing!.id,
          name: name,
          pointsCost: points,
          stock: stock,
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
        _error = S.tn(context, 'Gagal menyimpan reward.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEdit ? S.t(context, 'Ubah Reward') : S.t(context, 'Tambah Reward'),
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
              key: const ValueKey('reward_name_field'),
              controller: _nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '${S.t(context, 'Nama')} *',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('reward_points_field'),
              controller: _pointsCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '${S.t(context, 'Biaya poin')} *',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('reward_stock_field'),
              controller: _stockCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: S.t(context, 'Stok')),
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
          key: const ValueKey('reward_save_button'),
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

/// Dialog redeem: pilih customer via GET /customers?search=,
/// lalu POST /loyalty-points/redeem {customer_id, reward_id}.
class _RedeemDialog extends StatefulWidget {
  final LoyaltyReward reward;

  const _RedeemDialog({required this.reward});

  @override
  State<_RedeemDialog> createState() => _RedeemDialogState();
}

class _RedeemDialogState extends State<_RedeemDialog> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<Customer> _customers = [];
  Customer? _selected;
  bool _searching = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    try {
      final response = await _api.get(
        '/customers',
        query: {
          'per_page': '20',
          'page': '1',
          if (_searchCtrl.text.trim().isNotEmpty)
            'search': _searchCtrl.text.trim(),
        },
      );
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      setState(() {
        _customers = data is List
            ? data
                  .whereType<Map<String, dynamic>>()
                  .map(Customer.fromJson)
                  .toList()
            : [];
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  Future<void> _submit() async {
    if (_selected == null) {
      setState(() => _error = S.tn(context, 'Pilih pelanggan dulu.'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _api.post(
        '/loyalty-points/redeem',
        body: {'customer_id': _selected!.id, 'reward_id': widget.reward.id},
      );
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Reward berhasil diredeem.'),
        type: SnackType.success,
      );
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // 422 = saldo kurang / stok habis — tampilkan pesan server jujur.
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = S.tn(context, 'Gagal redeem reward.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        '${S.t(context, 'Redeem')}: ${widget.reward.name} (${widget.reward.pointsCost} ${S.t(context, 'poin')})',
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
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
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: S.t(context, 'Cari pelanggan...'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                ),
                onChanged: _onSearchChanged,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_searching)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: CircularProgressIndicator(),
                )
              else if (_customers.isEmpty)
                Text(
                  S.t(context, 'Tidak ada pelanggan ditemukan.'),
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                ..._customers.map((c) {
                  final selected = _selected?.id == c.id;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(c.name, style: const TextStyle(fontSize: 13)),
                    subtitle: c.phone == null
                        ? null
                        : Text(c.phone!, style: const TextStyle(fontSize: 11)),
                    trailing: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                    ),
                    selected: selected,
                    onTap: () => setState(() => _selected = c),
                  );
                }),
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
              : Text(S.t(context, 'Redeem')),
        ),
      ],
    );
  }
}

/// Dialog cek saldo poin customer (GET /loyalty-points?customer_id=).
class _BalanceDialog extends StatefulWidget {
  const _BalanceDialog();

  @override
  State<_BalanceDialog> createState() => _BalanceDialogState();
}

class _BalanceDialogState extends State<_BalanceDialog> {
  final ApiService _api = ApiService();
  final TextEditingController _idCtrl = TextEditingController();

  LoyaltyPoints? _points;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final id = _idCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => _error = S.tn(context, 'ID pelanggan wajib diisi.'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _points = null;
    });
    try {
      final response = await _api.get(
        '/loyalty-points',
        query: {'customer_id': id},
      );
      final data = response is Map ? response['data'] : response;
      if (!mounted) return;
      setState(() {
        if (data is Map<String, dynamic>) {
          _points = LoyaltyPoints.fromJson(data);
        } else {
          _points = LoyaltyPoints();
        }
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
        _error = S.tn(context, 'Gagal memuat saldo poin.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _points;
    return AlertDialog(
      title: Text(S.t(context, 'Saldo Poin Pelanggan')),
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _idCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: S.t(context, 'ID pelanggan'),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _check(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.tonal(
                  onPressed: _loading ? null : _check,
                  child: Text(S.t(context, 'Cek')),
                ),
              ],
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: CircularProgressIndicator(),
              )
            else if (p != null) ...[
              const SizedBox(height: AppSpacing.md),
              if (p.customerName.isNotEmpty)
                Text(p.customerName, style: const TextStyle(fontSize: 13.5)),
              Text(
                '${p.balance} ${S.t(context, 'poin')}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${S.t(context, 'Masuk')}: ${p.earned} · ${S.t(context, 'Ditukar')}: ${p.redeemed}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                S.t(
                  context,
                  'Poin bertambah otomatis saat order lunas (dihitung server).',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Text(
                  Fmt.rupiah(0).isEmpty
                      ? ''
                      : S.t(context, 'Masukkan ID lalu tekan Cek.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(S.t(context, 'Tutup')),
        ),
      ],
    );
  }
}
