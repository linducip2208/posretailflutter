import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../services/api_service.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();
  List<Customer> _customers = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await _api.get('/customers?per_page=100');
      final data = response['data'] ?? response;
      setState(() => _customers = (data as List).map((j) => Customer.fromJson(j)).toList());
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final response = await _api.get('/customers?search=$query');
      final data = response['data'] ?? response;
      setState(() => _customers = (data as List).map((j) => Customer.fromJson(j)).toList());
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Cari customer...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: _search,
          ),
        ),
        Expanded(
          child: RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _customers.isEmpty
              ? ListView(children: const [SizedBox(height: 200), Center(child: Text('Tidak ada customer', style: TextStyle(color: Colors.grey)))])
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _customers.length,
                  itemBuilder: (_, i) {
                    final c = _customers[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Text(c.name[0].toUpperCase(), style: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
                        ),
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(c.phone ?? '-'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (c.totalPoints != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
                                child: Text('${c.totalPoints} pts', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber.shade800)),
                              ),
                            if (c.groupName != null)
                              Text(c.groupName!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
        ),
      ],
    );
  }
}
