import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../models/order.dart';
import '../../providers/order_provider.dart';
import '../../services/api_service.dart';
import '../../services/printer_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/confirmation_dialog.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/quantity_stepper.dart';
import '../../widgets/common/status_badge.dart';
import 'orders_screen.dart' show orderStatusLabel, paymentStatusLabel;

/// Detail transaksi lengkap: item, pembayaran, struk.
/// [initialOrder] dipakai untuk tampilan instan dari daftar; detail terbaru
/// tetap diambil dari server untuk memastikan data pembayaran utuh.
class OrderDetailScreen extends StatefulWidget {
  final int orderId;
  final Order? initialOrder;

  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.initialOrder,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final OrderProvider _op = OrderProvider();
  final PrinterService _printer = PrinterService();

  Order? _order;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
    if (widget.initialOrder != null) _loading = false;
    _load();
  }

  Future<void> _load() async {
    if (_order == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final order = await _op.getOrderDetail(widget.orderId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (order != null) _order = order;
        _error = order == null
            ? (_op.error ?? 'Pesanan tidak ditemukan.')
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Gagal memuat detail pesanan.';
      });
    }
  }

  List<Map<String, dynamic>> _receiptItems(Order order) {
    return order.items
            ?.map(
              (i) => {
                'name': i.productName,
                'qty': i.quantity,
                'price': i.unitPrice,
                'subtotal': i.subtotal,
              },
            )
            .toList() ??
        [];
  }

  double _paidAmount(Order order) =>
      order.payments?.fold<double>(0, (s, p) => s + p.amount) ?? 0;

  double _remaining(Order order) => (order.totalAmount - _paidAmount(order))
      .clamp(0, double.infinity)
      .toDouble();

  double _change(Order order) => (_paidAmount(order) - order.totalAmount)
      .clamp(0, double.infinity)
      .toDouble();

  Future<void> _print(Order order) async {
    if (!_printer.isConnected) {
      showAppSnackbar(
        context,
        S.tn(
          context,
          'Printer belum terhubung. Hubungkan dari menu Lainnya → Printer.',
        ),
        type: SnackType.warning,
      );
      return;
    }
    final paid = _paidAmount(order);
    try {
      await _printer.printReceipt(
        orderNumber: order.orderNumber,
        date: Fmt.parseIsoToLocal(order.createdAt) ?? DateTime.now(),
        cashier: order.cashierName ?? '-',
        outletName: order.outletName,
        items: _receiptItems(order),
        subtotal: order.subtotal,
        discount: order.discountAmount,
        tax: order.taxAmount,
        total: order.totalAmount,
        paid: paid,
        change: _change(order),
        remaining: _remaining(order),
        customerName: order.customerName,
      );
      if (mounted) {
        showAppSnackbar(
          context,
          S.tn(context, 'Struk dikirim ke printer Bluetooth.'),
          type: SnackType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        showAppSnackbar(
          context,
          S.tn(context, 'Gagal mencetak struk. Periksa printer.'),
          type: SnackType.error,
        );
      }
    }
  }

  Future<void> _sharePdf(Order order) async {
    final paid = _paidAmount(order);
    try {
      final bytes = await _printer.generatePdfReceipt(
        orderNumber: order.orderNumber,
        date: Fmt.parseIsoToLocal(order.createdAt) ?? DateTime.now(),
        cashier: order.cashierName ?? '-',
        outletName: order.outletName,
        items: _receiptItems(order),
        subtotal: order.subtotal,
        discount: order.discountAmount,
        tax: order.taxAmount,
        total: order.totalAmount,
        paid: paid,
        change: _change(order),
        remaining: _remaining(order),
        customerName: order.customerName,
      );
      await _printer.shareReceiptPdf(bytes, orderNumber: order.orderNumber);
    } catch (_) {
      if (mounted) {
        showAppSnackbar(
          context,
          S.tn(context, 'Gagal membuat PDF struk.'),
          type: SnackType.error,
        );
      }
    }
  }

  /// Refund parsial: pilih item + qty yang dikembalikan → server membuat
  /// Retur, memulihkan stok, dan mencatat kas keluar di shift bila ada.
  /// Izin dikendalikan server (butuh izin hapus-transaksi).
  Future<void> _openRefund(Order order) async {
    final selection = await showModalBottomSheet<_RefundSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RefundSheet(items: order.items ?? const []),
    );
    if (selection == null || !mounted) return;

    final totalQty = selection.quantities.values.fold<int>(0, (s, q) => s + q);
    final ok = await confirmDialog(
      context,
      title: S.tn(context, 'Proses refund?'),
      message:
          '${S.tn(context, 'Dikembalikan')}: $totalQty ${S.tn(context, 'item')}. '
          '${S.tn(context, 'Stok akan ditambahkan kembali dan transaksi retur tercatat di server.')}',
      confirmLabel: S.tn(context, 'Refund'),
      destructive: true,
    );
    if (!ok || !mounted) return;

    try {
      final response = await ApiService().post(
        '/orders/${order.id}/refund',
        body: {
          'items': selection.quantities.entries
              .map((e) => {'order_item_id': e.key, 'quantity': e.value})
              .toList(),
          'reason': selection.reason.isEmpty
              ? 'Refund parsial POS'
              : selection.reason,
        },
      );
      if (!mounted) return;
      final data = response is Map ? response['data'] : null;
      final returnNumber = data is Map
          ? data['return_number']?.toString()
          : null;
      showAppSnackbar(
        context,
        returnNumber != null
            ? '${S.tn(context, 'Refund berhasil')} · $returnNumber'
            : S.tn(context, 'Refund berhasil diproses.'),
        type: SnackType.success,
        duration: const Duration(seconds: 5),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        e.message,
        type: SnackType.error,
        duration: const Duration(seconds: 6),
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Refund gagal. Coba lagi.'),
        type: SnackType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;

    return Scaffold(
      appBar: AppBar(
        title: Text(order?.orderNumber ?? S.t(context, 'Detail Pesanan')),
        actions: [
          if (order != null) ...[
            IconButton(
              tooltip: S.t(context, 'Cetak Bluetooth'),
              onPressed: () => _print(order),
              icon: const Icon(Icons.print_outlined),
            ),
            IconButton(
              tooltip: S.t(context, 'Share PDF'),
              onPressed: () => _sharePdf(order),
              icon: const Icon(Icons.share_outlined),
            ),
            if (order.orderStatus == 'completed' &&
                (order.items?.isNotEmpty ?? false))
              IconButton(
                tooltip: S.t(context, 'Refund'),
                onPressed: () => _openRefund(order),
                icon: const Icon(Icons.assignment_return_outlined),
              ),
          ],
        ],
      ),
      body: _buildBody(order),
    );
  }

  Widget _buildBody(Order? order) {
    if (_loading && order == null) {
      return const LoadingSkeleton(items: 5, itemHeight: 64);
    }
    if (order == null) {
      return ErrorState(
        message: _error ?? S.tn(context, 'Pesanan tidak ditemukan.'),
        icon: Icons.receipt_long_outlined,
        onRetry: _load,
      );
    }

    final theme = Theme.of(context);
    final paid = _paidAmount(order);

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
                          order.orderNumber,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                          ),
                        ),
                      ),
                      StatusBadge(
                        orderStatusLabel(context, order.orderStatus),
                        tone: toneForOrderStatus(order.orderStatus),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      StatusBadge(
                        paymentStatusLabel(context, order.paymentStatus),
                        tone: toneForPaymentStatus(order.paymentStatus),
                      ),
                    ],
                  ),
                  if (order.queueNumber != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    StatusBadge(
                      '${S.t(context, 'Antrian')} ${order.queueNumber}',
                      tone: BadgeTone.info,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  _infoRow(
                    S.t(context, 'Tanggal'),
                    Fmt.dateTime(order.createdAt),
                  ),
                  _infoRow(
                    S.t(context, 'Customer'),
                    (order.customerName?.isNotEmpty ?? false)
                        ? order.customerName!
                        : S.t(context, 'Walk-in'),
                  ),
                  _infoRow(S.t(context, 'Outlet'), order.outletName ?? '-'),
                  if (order.cashierName?.isNotEmpty ?? false)
                    _infoRow(S.t(context, 'Kasir'), order.cashierName!),
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
                    S.t(context, 'Items'),
                    style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (order.items == null || order.items!.isEmpty)
                    Text(
                      S.t(context, 'Detail item tidak tersedia.'),
                      style: theme.textTheme.bodySmall,
                    )
                  else
                    ...order.items!.map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName.isNotEmpty
                                        ? item.productName
                                        : S.t(context, 'Item'),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${item.quantity} × ${Fmt.rupiah(item.unitPrice)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              Fmt.rupiah(item.subtotal),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Divider(height: AppSpacing.xl),
                  _totalRow(S.t(context, 'Subtotal'), order.subtotal),
                  if (order.discountAmount > 0)
                    _totalRow(
                      S.t(context, 'Diskon'),
                      -order.discountAmount,
                      color: AppColors.error,
                    ),
                  if (order.taxAmount > 0)
                    _totalRow(S.t(context, 'Pajak'), order.taxAmount),
                  _totalRow(
                    S.t(context, 'Total'),
                    order.totalAmount,
                    emphasize: true,
                  ),
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
                    S.t(context, 'Pembayaran'),
                    style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (order.payments == null || order.payments!.isEmpty)
                    Text(
                      S.t(context, 'Data pembayaran tidak tersedia.'),
                      style: theme.textTheme.bodySmall,
                    )
                  else
                    ...order.payments!.map(
                      (p) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.payments_outlined,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                p.methodName?.isNotEmpty == true
                                    ? p.methodName!
                                    : '${S.t(context, 'Metode')} #${p.paymentMethodId}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              Fmt.rupiah(p.amount),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Divider(height: AppSpacing.xl),
                  _totalRow(S.t(context, 'Dibayar'), paid),
                  if (paid > order.totalAmount)
                    _totalRow(
                      S.t(context, 'Kembalian'),
                      paid - order.totalAmount,
                      color: AppColors.success,
                    ),
                  if (paid > 0 && paid < order.totalAmount)
                    _totalRow(
                      S.t(context, 'Sisa Tagihan'),
                      order.totalAmount - paid,
                      color: AppColors.warning,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
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

  Widget _totalRow(
    String label,
    double amount, {
    bool emphasize = false,
    Color? color,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: emphasize
                  ? const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)
                  : theme.textTheme.bodySmall?.copyWith(fontSize: 12.5),
            ),
          ),
          Text(
            Fmt.rupiah(amount),
            style: TextStyle(
              fontSize: emphasize ? 15.5 : 12.5,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              color: color ?? (emphasize ? theme.colorScheme.primary : null),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hasil pilihan refund dari sheet.
class _RefundSelection {
  final Map<int, int> quantities; // order_item_id → qty
  final String reason;

  _RefundSelection({required this.quantities, required this.reason});
}

/// Sheet pemilihan item + qty yang akan direfund.
class _RefundSheet extends StatefulWidget {
  final List<OrderItem> items;

  const _RefundSheet({required this.items});

  @override
  State<_RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends State<_RefundSheet> {
  final Map<int, int> _quantities = {};
  final TextEditingController _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  int get _totalSelected =>
      _quantities.values.fold<int>(0, (sum, qty) => sum + qty);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            Text(
              S.t(context, 'Refund Item'),
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              S.t(
                context,
                'Pilih item dan jumlah yang dikembalikan. Stok akan ditambahkan kembali oleh server.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final item in widget.items)
              Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName.isNotEmpty
                                  ? item.productName
                                  : S.t(context, 'Item'),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${S.t(context, 'Terjual')}: ${item.quantity} · '
                              '${Fmt.rupiah(item.unitPrice)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      QuantityStepper(
                        value: _quantities[item.id] ?? 0,
                        min: 0,
                        max: item.quantity,
                        compact: true,
                        onChanged: (qty) =>
                            setState(() => _quantities[item.id] = qty),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _reasonCtrl,
              decoration: InputDecoration(
                labelText: S.t(context, 'Alasan (opsional)'),
                hintText: S.t(
                  context,
                  'mis. barang rusak, salah ukuran, pelanggan membatalkan',
                ),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: _totalSelected == 0
                    ? null
                    : () => Navigator.pop(
                        context,
                        _RefundSelection(
                          quantities: Map.of(_quantities)
                            ..removeWhere((_, qty) => qty <= 0),
                          reason: _reasonCtrl.text.trim(),
                        ),
                      ),
                icon: const Icon(Icons.assignment_return_outlined, size: 18),
                label: Text(
                  _totalSelected == 0
                      ? S.t(context, 'Pilih item untuk direfund')
                      : '${S.t(context, 'Refund')} $_totalSelected '
                            '${S.t(context, 'item')}',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
