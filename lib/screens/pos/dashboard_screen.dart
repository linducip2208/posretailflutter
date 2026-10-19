import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../home/home_screen.dart';
import '../more/more_screen.dart';
import '../pos/pos_screen.dart';
import '../products/product_list_screen.dart';
import '../reports/report_screen.dart';

/// Shell navigasi utama kasir: 5 tab dengan state yang dijaga
/// ([IndexedStack]) agar keranjang/transaksi tidak ter-reset saat berpindah.
class DashboardScreen extends StatefulWidget {
  final int initialTab;

  const DashboardScreen({super.key, this.initialTab = 0});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late int _currentIndex = widget.initialTab.clamp(0, 4);

  void _openTab(int tab) {
    if (tab < 0 || tab > 4) return;
    setState(() => _currentIndex = tab);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(onOpenTab: _openTab),
          const PosScreen(),
          const ProductListScreen(),
          const ReportScreen(),
          const MoreScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _openTab,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: S.t(context, 'Beranda'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.point_of_sale_outlined),
            selectedIcon: const Icon(Icons.point_of_sale),
            label: S.t(context, 'Transaksi'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.inventory_2_outlined),
            selectedIcon: const Icon(Icons.inventory_2),
            label: S.t(context, 'Produk'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            selectedIcon: const Icon(Icons.bar_chart),
            label: S.t(context, 'Laporan'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.more_horiz),
            selectedIcon: const Icon(Icons.more_horiz),
            label: S.t(context, 'Lainnya'),
          ),
        ],
      ),
    );
  }
}
