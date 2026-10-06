import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../l10n/s.dart';
import '../../models/order.dart';
import '../../providers/order_provider.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OrderProvider>().fetchTodayOrders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final op = context.watch<OrderProvider>();
    final theme = Theme.of(context);
    final format = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

    return RefreshIndicator(
      onRefresh: () => op.fetchTodayOrders(),
      child: op.isLoading
          ? const Center(child: CircularProgressIndicator())
          : op.orders.isEmpty
              ? ListView(children: [const SizedBox(height: 200), Center(child: Text(S.t(context, 'Belum ada pesanan'), style: const TextStyle(color: Colors.grey)))])
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: op.orders.length,
                  itemBuilder: (_, i) {
                    final order = op.orders[i];
                    final isCompleted = order.orderStatus == 'completed';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openDetail(order),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(order.orderNumber,
                                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isCompleted ? Colors.green.shade50 : Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _statusLabel(context, order.orderStatus),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isCompleted ? Colors.green.shade700 : Colors.orange.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                  '${S.t(context, 'Customer')}: ${(order.customerName?.isNotEmpty ?? false) ? order.customerName : S.t(context, 'Walk-in')}',
                                  style: theme.textTheme.bodySmall),
                              Text(format.format(order.totalAmount),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.primary,
                                  )),
                              Text(
                                _formatDate(order.createdAt),
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  void _openDetail(Order order) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id)),
    );
  }

  String _statusLabel(BuildContext context, String status) {
    switch (status) {
      case 'completed':
        return S.t(context, 'Selesai');
      case 'pending':
        return S.t(context, 'Menunggu');
      case 'processing':
        return S.t(context, 'Diproses');
      case 'cancelled':
        return S.t(context, 'Dibatalkan');
      case 'paid':
        return S.t(context, 'Lunas');
      case 'partial':
        return S.t(context, 'Sebagian');
      default:
        return status;
    }
  }

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '-';
    return DateFormat('dd MMM yyyy, HH:mm').format(dt);
  }
}
