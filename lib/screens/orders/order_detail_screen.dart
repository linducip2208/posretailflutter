import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/s.dart';
import '../../models/order.dart';
import '../../providers/order_provider.dart';

class OrderDetailScreen extends StatefulWidget {
  final int orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final OrderProvider _op = OrderProvider();
  Order? _order;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final order = await _op.getOrderDetail(widget.orderId);
    if (!mounted) return;
    setState(() { _order = order; _loading = false; });
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return S.t(context, 'Selesai');
      case 'pending':
        return S.t(context, 'Menunggu');
      case 'processing':
        return S.t(context, 'Diproses');
      case 'cancelled':
        return S.t(context, 'Dibatalkan');
      default:
        return status;
    }
  }

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '-';
    return DateFormat('dd MMM yyyy, HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(title: Text(_order?.orderNumber ?? S.t(context, 'Detail Pesanan'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _order == null
              ? Center(child: Text(S.t(context, 'Pesanan tidak ditemukan')))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _infoRow(theme, S.t(context, 'Nomor'), _order!.orderNumber),
                    if (_order!.queueNumber != null)
                      _infoRow(theme, S.t(context, 'Antrian'), _order!.queueNumber!),
                    _infoRow(theme, S.t(context, 'Status'), _statusLabel(_order!.orderStatus)),
                    _infoRow(theme, S.t(context, 'Customer'),
                        (_order!.customerName?.isNotEmpty ?? false) ? _order!.customerName! : S.t(context, 'Walk-in')),
                    _infoRow(theme, S.t(context, 'Outlet'), _order!.outletName ?? '-'),
                    _infoRow(theme, S.t(context, 'Tanggal'), _formatDate(_order!.createdAt)),
                    const Divider(height: 32),

                    Text(S.t(context, 'Items'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (_order!.items != null)
                      ..._order!.items!.map((item) => Card(
                            margin: const EdgeInsets.only(bottom: 4),
                            child: ListTile(
                              title: Text(item.productName.isNotEmpty ? item.productName : S.t(context, 'Item'),
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${item.quantity} x ${format.format(item.unitPrice)}'),
                              trailing: Text(format.format(item.subtotal),
                                  style: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
                            ),
                          )),

                    const Divider(height: 32),
                    _totalRow(theme, S.t(context, 'Subtotal'), _order!.subtotal, format),
                    if (_order!.discountAmount > 0) _totalRow(theme, S.t(context, 'Diskon'), -_order!.discountAmount, format, color: Colors.red),
                    if (_order!.taxAmount > 0) _totalRow(theme, S.t(context, 'Pajak'), _order!.taxAmount, format),
                    const Divider(),
                    _totalRow(theme, S.t(context, 'Total'), _order!.totalAmount, format, bold: true),
                  ],
                ),
    );
  }

  Widget _infoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey))),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _totalRow(ThemeData theme, String label, double amount, NumberFormat format, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: (bold ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)?.copyWith(fontWeight: FontWeight.w700)),
          Text(format.format(amount),
              style: (bold ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)?.copyWith(
                fontWeight: FontWeight.w700,
                color: color ?? theme.colorScheme.primary,
              )),
        ],
      ),
    );
  }
}
