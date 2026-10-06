import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/s.dart';
import '../../services/api_service.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>>? _orders;
  String _period = 'today';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _endpointForPeriod() {
    final now = DateTime.now();
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    switch (_period) {
      case 'yesterday':
        final y = now.subtract(const Duration(days: 1));
        return '/orders/history?start_date=${fmt(y)}&end_date=${fmt(y)}';
      case 'this_week':
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return '/orders/history?start_date=${fmt(monday)}&end_date=${fmt(now)}';
      case 'this_month':
        final first = DateTime(now.year, now.month, 1);
        return '/orders/history?start_date=${fmt(first)}&end_date=${fmt(now)}';
      case 'today':
      default:
        return '/orders/today';
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final response = await _api.get(_endpointForPeriod());
      final data = response['data'] ?? response;
      if (data is List) {
        setState(() {
          _orders = data.cast<Map<String, dynamic>>();
          _summary = _calculateSummary(_orders!);
        });
      }
    } catch (_) {
      setState(() => _summary = {'total_orders': 0, 'total_revenue': 0});
      _orders = [];
    }
    setState(() => _loading = false);
  }

  Map<String, dynamic> _calculateSummary(List<Map<String, dynamic>> orders) {
    double asDouble(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;
    final totalOrders = orders.length;
    final totalRevenue = orders.fold<double>(0, (s, o) => s + asDouble(o['total_amount']));
    final paidOrders = orders.where((o) => o['payment_status'] == 'paid').length;
    final unpaidOrders = totalOrders - paidOrders;
    final avgOrder = totalOrders > 0 ? totalRevenue / totalOrders : 0;

    final paymentCounts = <String, int>{};
    for (final o in orders) {
      final payments = o['payments'] as List?;
      if (payments != null) {
        for (final p in payments) {
          final name = p['payment_method']?['name']?.toString() ??
              p['method_name']?.toString() ??
              'Lainnya';
          paymentCounts[name] = (paymentCounts[name] ?? 0) + 1;
        }
      }
    }

    return {
      'total_orders': totalOrders,
      'total_revenue': totalRevenue,
      'paid_orders': paidOrders,
      'unpaid_orders': unpaidOrders,
      'avg_order': avgOrder,
      'payment_counts': paymentCounts,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _periodChip('today', S.t(context, 'Hari Ini')),
                const SizedBox(width: 8),
                _periodChip('yesterday', S.t(context, 'Kemarin')),
                const SizedBox(width: 8),
                _periodChip('this_week', S.t(context, 'Minggu Ini')),
                const SizedBox(width: 8),
                _periodChip('this_month', S.t(context, 'Bulan Ini')),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Text(S.t(context, 'Ringkasan'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _statCard(theme, S.t(context, 'Total Transaksi'), '${_summary?['total_orders'] ?? 0}', Icons.receipt_long, Colors.blue)),
              const SizedBox(width: 12),
              Expanded(child: _statCard(theme, S.t(context, 'Total Revenue'), format.format((_summary?['total_revenue'] ?? 0).toDouble()), Icons.attach_money, Colors.green)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _statCard(theme, S.t(context, 'Lunas'), '${_summary?['paid_orders'] ?? 0}', Icons.check_circle, Colors.teal)),
              const SizedBox(width: 12),
              Expanded(child: _statCard(theme, S.t(context, 'Belum Lunas'), '${_summary?['unpaid_orders'] ?? 0}', Icons.pending, Colors.orange)),
            ],
          ),
          const SizedBox(height: 8),
          _statCard(theme, S.t(context, 'Rata-rata Order'), format.format((_summary?['avg_order'] ?? 0).toDouble()), Icons.trending_up, Colors.purple),

          const SizedBox(height: 24),
          Text(S.t(context, 'Metode Pembayaran'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_summary?['payment_counts'] != null)
            ...(_summary!['payment_counts'] as Map<String, int>).entries.map((e) => Card(
              margin: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: theme.colorScheme.primaryContainer, child: Text('${e.value}', style: TextStyle(fontSize: 12, color: theme.colorScheme.onPrimaryContainer))),
                title: Text(e.key),
              ),
            )),

          const SizedBox(height: 24),
          Text(S.t(context, 'Transaksi Terbaru'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_orders == null || _orders!.isEmpty)
            Center(child: Text(S.t(context, 'Belum ada transaksi'), style: const TextStyle(color: Colors.grey)))
          else
            ..._orders!.take(20).map((o) => Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: o['payment_status'] == 'paid' ? Colors.green.shade50 : Colors.orange.shade50,
                  child: Icon(o['payment_status'] == 'paid' ? Icons.check_circle : Icons.pending, color: o['payment_status'] == 'paid' ? Colors.green : Colors.orange, size: 20),
                ),
                title: Text(o['order_number'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text((o['customer_name']?.toString().isNotEmpty ?? false)
                    ? o['customer_name'].toString()
                    : S.t(context, 'Walk-in'), style: const TextStyle(fontSize: 12)),
                trailing: Text(format.format(double.tryParse((o['total_amount'] ?? 0).toString()) ?? 0), style: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.primary, fontSize: 13)),
              ),
            )),
        ],
      ),
    );
  }

  Widget _periodChip(String value, String label) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: _period == value,
      onSelected: (v) {
        setState(() => _period = value);
        _loadData();
      },
    );
  }

  Widget _statCard(ThemeData theme, String label, String value, IconData icon, MaterialColor color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: color.shade50, radius: 20, child: Icon(icon, color: color, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
