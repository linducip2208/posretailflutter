import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/s.dart';
import '../../providers/auth_provider.dart';
import '../pos/dashboard_screen.dart';

class OutletGate extends StatelessWidget {
  const OutletGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.hasOutlet) return const DashboardScreen();
    return const OutletSelectionScreen();
  }
}

class OutletSelectionScreen extends StatelessWidget {
  const OutletSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(S.t(context, 'Pilih Outlet')), automaticallyImplyLeading: false),
      body: auth.outlets.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.store_outlined, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      S.t(context,
                          'Akun ini belum memiliki akses outlet.\nHubungi pemilik/admin untuk akses.'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        await auth.logout();
                      },
                      child: Text(S.t(context, 'Keluar')),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${S.t(context, 'Halo, ')}${auth.user?.name ?? ''}${S.t(context, '! Pilih outlet aktif untuk berjualan.')}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                ...auth.outlets.map(
                  (o) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: const Icon(Icons.store),
                      ),
                      title: Text(o.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: o.code != null ? Text(o.code!) : null,
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () async {
                        await auth.selectOutlet(o);
                        if (context.mounted) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => const DashboardScreen()),
                          );
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
