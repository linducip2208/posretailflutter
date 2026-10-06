import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../l10n/s.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../auth/login_screen.dart';
import '../pos/pos_screen.dart';
import '../orders/orders_screen.dart';
import '../reports/report_screen.dart';
import '../settings/settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  final int initialTab;
  const DashboardScreen({super.key, this.initialTab = 0});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OrderProvider>().fetchTodayOrders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final orderProvider = context.watch<OrderProvider>();
    final theme = Theme.of(context);
    final format = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

    final screens = [
      _buildHomeTab(theme, format, orderProvider),
      const PosScreen(),
      const OrdersScreen(),
      const ReportScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'POS Retail')),
        bottom: auth.currentOutlet == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(22),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${S.t(context, 'Outlet aktif')}: ${auth.currentOutlet!.name}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
        actions: [
          if (_currentIndex == 0) ...[
            IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: () => setState(() => _currentIndex = 1)),
            IconButton(icon: const Icon(Icons.refresh), onPressed: () => orderProvider.fetchTodayOrders()),
          ],
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle_outlined, size: 28),
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(auth.user?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(auth.user?.email ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Text(auth.role ?? '', style: TextStyle(fontSize: 11, color: Colors.indigo.shade700)),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                child: Row(children: [const Icon(Icons.logout, size: 18), const SizedBox(width: 8), Text(S.t(context, 'Keluar'))]),
                onTap: () async {
                  await auth.logout();
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.dashboard_outlined), selectedIcon: const Icon(Icons.dashboard), label: S.t(context, 'Beranda')),
          NavigationDestination(icon: const Icon(Icons.shopping_cart_outlined), selectedIcon: const Icon(Icons.shopping_cart), label: S.t(context, 'POS')),
          NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: S.t(context, 'Pesanan')),
          NavigationDestination(icon: const Icon(Icons.bar_chart_outlined), selectedIcon: const Icon(Icons.bar_chart), label: S.t(context, 'Laporan')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings), label: S.t(context, 'Atur')),
        ],
      ),
    );
  }

  Widget _buildHomeTab(ThemeData theme, NumberFormat format, OrderProvider op) {
    final orders = op.orders;
    final todayTotal = orders.fold<double>(0, (s, o) => s + o.totalAmount);
    final todayCount = orders.length;
    final paidCount = orders.where((o) => o.paymentStatus == 'paid').length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: _statCard(theme, S.t(context, 'Transaksi Hari Ini'), '$todayCount', Icons.receipt_long, Colors.blue)),
            const SizedBox(width: 12),
            Expanded(child: _statCard(theme, S.t(context, 'Total Hari Ini'), format.format(todayTotal), Icons.attach_money, Colors.green)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _statCard(theme, S.t(context, 'Lunas'), '$paidCount', Icons.check_circle, Colors.teal)),
            const SizedBox(width: 12),
            Expanded(child: _statCard(theme, S.t(context, 'Belum Lunas'), '${todayCount - paidCount}', Icons.pending, Colors.orange)),
          ],
        ),
        const SizedBox(height: 16),
        Text(S.t(context, 'Transaksi Terbaru'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (op.isLoading)
          const Center(child: CircularProgressIndicator())
        else if (orders.isEmpty)
          Center(child: Text(S.t(context, 'Belum ada transaksi hari ini')))
        else
          ...orders.take(10).map((order) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: order.orderStatus == 'completed' ? Colors.green.shade50 : Colors.orange.shade50,
                    child: Icon(
                      order.orderStatus == 'completed' ? Icons.check_circle : Icons.pending,
                      color: order.orderStatus == 'completed' ? Colors.green : Colors.orange,
                    ),
                  ),
                  title: Text(order.orderNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${(order.customerName?.isNotEmpty ?? false) ? order.customerName : S.t(context, 'Walk-in')} · ${order.items?.length ?? 0} ${S.t(context, 'item')}'),
                  trailing: Text(format.format(order.totalAmount), style: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
                ),
              )),
      ],
    );
  }

  Widget _statCard(ThemeData theme, String label, String value, IconData icon, MaterialColor color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: color.shade50, child: Icon(icon, color: color)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
