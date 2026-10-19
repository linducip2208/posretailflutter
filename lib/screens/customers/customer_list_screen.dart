import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/s.dart';
import '../../models/customer.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/payment_dialog.dart' show ThousandsInputFormatter;

/// Daftar pelanggan: pencarian server, pagination, tambah pelanggan,
/// dan pengelolaan saldo deposit (topup/pakai/refund) via API nyata.
class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _debounce;

  List<Customer> _customers = [];
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

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.get(
        '/customers',
        query: {
          'per_page': '50',
          'page': '1',
          if (_searchCtrl.text.trim().isNotEmpty)
            'search': _searchCtrl.text.trim(),
        },
      );
      final data = response is Map ? response['data'] : null;
      final meta = response is Map ? response['meta'] : null;
      if (!mounted) return;
      setState(() {
        _customers = data is List
            ? data
                  .whereType<Map<String, dynamic>>()
                  .map(Customer.fromJson)
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
        _error = S.tn(context, 'Gagal memuat daftar pelanggan.');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_page >= _lastPage) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final response = await _api.get(
        '/customers',
        query: {
          'per_page': '50',
          'page': '$nextPage',
          if (_searchCtrl.text.trim().isNotEmpty)
            'search': _searchCtrl.text.trim(),
        },
      );
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      setState(() {
        if (data is List) {
          _customers = [
            ..._customers,
            ...data.whereType<Map<String, dynamic>>().map(Customer.fromJson),
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
    final created = await showDialog<Customer>(
      context: context,
      builder: (_) => const _CustomerFormDialog(),
    );
    if (created == null || !mounted) return;
    showAppSnackbar(
      context,
      '${S.tn(context, 'Pelanggan')} "${created.name}" ${S.tn(context, 'tersimpan di server.')}',
      type: SnackType.success,
    );
    await _refresh();
  }

  Future<void> _openDetail(Customer customer) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CustomerDetailSheet(customer: customer),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Pelanggan')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Tambah pelanggan'),
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
    if (_customers.isEmpty) {
      return EmptyState(
        icon: Icons.people_outline,
        title: S.t(context, 'Tidak ada pelanggan'),
        message: S.t(
          context,
          'Tambah pelanggan baru dengan tombol di kanan atas.',
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
        itemCount: _customers.length + 1,
        itemBuilder: (_, i) {
          if (i == _customers.length) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : Text(
                        '$_total ${S.t(context, 'pelanggan')}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
            );
          }
          return _customerCard(_customers[i]);
        },
      ),
    );
  }

  Widget _customerCard(Customer customer) {
    final theme = Theme.of(context);
    final contacts = [
      if (customer.phone != null && customer.phone!.isNotEmpty) customer.phone!,
      if (customer.email != null && customer.email!.isNotEmpty) customer.email!,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            customer.name.isEmpty
                ? '?'
                : customer.name.substring(0, 1).toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(
          customer.name,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          contacts.isEmpty ? S.t(context, 'Tanpa kontak') : contacts,
          style: const TextStyle(fontSize: 11.5),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (customer.depositBalance > 0)
              StatusBadge(
                '${S.t(context, 'Saldo')} ${Fmt.rupiah(customer.depositBalance)}',
                tone: BadgeTone.success,
              )
            else if (customer.totalPoints != null && customer.totalPoints! > 0)
              StatusBadge('${customer.totalPoints} poin', tone: BadgeTone.info),
          ],
        ),
        onTap: () => _openDetail(customer),
      ),
    );
  }
}

/// Form tambah pelanggan (POST /customers).
class _CustomerFormDialog extends StatefulWidget {
  const _CustomerFormDialog();

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  final ApiService _api = ApiService();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
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
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final response = await _api.post(
        '/customers',
        body: {
          'name': name,
          if (_phoneCtrl.text.trim().isNotEmpty)
            'phone': _phoneCtrl.text.trim(),
          if (_emailCtrl.text.trim().isNotEmpty)
            'email': _emailCtrl.text.trim(),
          if (_addressCtrl.text.trim().isNotEmpty)
            'address': _addressCtrl.text.trim(),
        },
      );
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      Navigator.pop(
        context,
        data is Map<String, dynamic> ? Customer.fromJson(data) : null,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.statusCode == 422
            ? S.tn(
                context,
                'Data tidak valid. Pastikan email belum digunakan pelanggan lain.',
              )
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = S.tn(context, 'Gagal menyimpan pelanggan.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.t(context, 'Tambah Pelanggan')),
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
              controller: _nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '${S.t(context, 'Nama')} *',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: S.t(context, 'Telepon')),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: S.t(context, 'Email')),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
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

/// Detail pelanggan + pengelolaan saldo deposit.
class _CustomerDetailSheet extends StatefulWidget {
  final Customer customer;

  const _CustomerDetailSheet({required this.customer});

  @override
  State<_CustomerDetailSheet> createState() => _CustomerDetailSheetState();
}

class _CustomerDetailSheetState extends State<_CustomerDetailSheet> {
  final ApiService _api = ApiService();
  late Customer _customer = widget.customer;
  bool _busy = false;

  Future<void> _reload() async {
    try {
      final response = await _api.get('/customers/${_customer.id}');
      final data = response is Map ? response['data'] : null;
      if (!mounted || data is! Map<String, dynamic>) return;
      setState(() => _customer = Customer.fromJson(data));
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackbar(context, e.message, type: SnackType.error);
    } catch (_) {
      // Abaikan: data lama tetap ditampilkan.
    }
  }

  Future<void> _adjustDeposit(String type) async {
    final outletId = context.read<AuthProvider>().currentOutletId;
    if (outletId == null) {
      showAppSnackbar(
        context,
        S.tn(context, 'Pilih outlet dulu.'),
        type: SnackType.warning,
      );
      return;
    }

    final amount = await showDialog<double>(
      context: context,
      builder: (_) => _DepositAmountDialog(type: type),
    );
    if (amount == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await _api.post(
        '/customers/${_customer.id}/deposits',
        body: {'outlet_id': outletId, 'type': type, 'amount': amount},
      );
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Saldo deposit diperbarui.'),
        type: SnackType.success,
      );
      await _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackbar(context, e.message, type: SnackType.error);
    } catch (_) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Gagal memperbarui saldo.'),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _customer;

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
                  c.name.isEmpty ? '?' : c.name.substring(0, 1).toUpperCase(),
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
                      c.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                      ),
                    ),
                    if (c.groupName != null && c.groupName!.isNotEmpty)
                      StatusBadge(c.groupName!, tone: BadgeTone.info),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _infoRow(context, S.t(context, 'Telepon'), c.phone),
          _infoRow(context, S.t(context, 'Email'), c.email),
          _infoRow(context, S.t(context, 'Alamat'), c.address),
          if (c.totalPoints != null)
            _infoRow(context, S.t(context, 'Poin'), '${c.totalPoints}'),
          const Divider(height: AppSpacing.xl),
          Text(
            S.t(context, 'Saldo Deposit'),
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            Fmt.rupiah(c.depositBalance),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            S.t(
              context,
              'Saldo ini disesuaikan manual (topup/pakai/refund) dan tercatat di server. Pembayaran checkout belum otomatis memakai saldo deposit.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _adjustDeposit('topup'),
                  icon: const Icon(Icons.add_card, size: 18),
                  label: Text(
                    S.t(context, 'Topup'),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _adjustDeposit('use'),
                  icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                  label: Text(
                    S.t(context, 'Pakai'),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _adjustDeposit('refund'),
                  icon: const Icon(Icons.undo, size: 18),
                  label: Text(
                    S.t(context, 'Refund'),
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

class _DepositAmountDialog extends StatefulWidget {
  final String type;

  const _DepositAmountDialog({required this.type});

  @override
  State<_DepositAmountDialog> createState() => _DepositAmountDialogState();
}

class _DepositAmountDialogState extends State<_DepositAmountDialog> {
  final _amountCtrl = TextEditingController();

  String get _title {
    switch (widget.type) {
      case 'topup':
        return S.tn(context, 'Topup Saldo');
      case 'use':
        return S.tn(context, 'Pakai Saldo');
      default:
        return S.tn(context, 'Refund Saldo');
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title),
      content: TextField(
        controller: _amountCtrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: const [ThousandsInputFormatter()],
        decoration: InputDecoration(
          labelText: S.t(context, 'Nominal (Rp)'),
          prefixText: 'Rp ',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(S.t(context, 'Batal')),
        ),
        FilledButton(
          onPressed: () {
            final amount = Fmt.parseMoneyDigits(_amountCtrl.text).toDouble();
            if (amount <= 0) return;
            Navigator.pop(context, amount);
          },
          child: Text(S.t(context, 'Simpan')),
        ),
      ],
    );
  }
}
