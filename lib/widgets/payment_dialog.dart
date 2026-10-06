import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../l10n/s.dart';
import '../../models/payment_method.dart';
import '../../providers/cart_provider.dart';
import '../../services/api_service.dart';

class PaymentEntry {
  PaymentMethod method;
  double amount;

  PaymentEntry({required this.method, this.amount = 0});
}

class PaymentDialog extends StatefulWidget {
  final Function(List<PaymentEntry>)? onPaymentComplete;

  const PaymentDialog({super.key, this.onPaymentComplete});

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final ApiService _api = ApiService();
  List<PaymentMethod> _methods = [];
  List<PaymentEntry> _entries = [PaymentEntry(method: PaymentMethod(id: 0, name: '', code: ''))];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMethods();
  }

  String? _loadError;

  Future<void> _loadMethods() async {
    try {
      final response = await _api.get('/payment-methods');
      final data = response['data'] ?? response;
      final list = (data as List)
          .whereType<Map<String, dynamic>>()
          .map(PaymentMethod.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _methods = list;
        if (list.isNotEmpty) {
          _entries = [PaymentEntry(method: list.first)];
        } else {
          _loadError = 'Metode pembayaran belum tersedia';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString());
    }
  }

  double get _totalPaid => _entries.fold(0, (s, e) => s + e.amount);
  double get _remaining => context.read<CartProvider>().totalAmount - _totalPaid;

  void _addEntry() {
    if (_methods.isEmpty) return;
    setState(() => _entries.add(PaymentEntry(method: _methods.first)));
  }

  void _removeEntry(int index) {
    if (_entries.length <= 1) return;
    setState(() => _entries.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final format = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(S.t(context, 'Pembayaran'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text('${S.t(context, 'Total')}: ${format.format(cart.totalAmount)}',
                style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800, color: theme.colorScheme.primary)),
            if (_loadError != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_loadError!, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
              ),
            ],
            const SizedBox(height: 16),

            ..._entries.asMap().entries.map((e) {
              final i = e.key;
              final entry = e.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<PaymentMethod>(
                        initialValue: _methods.contains(entry.method) ? entry.method : (_methods.isNotEmpty ? _methods.first : null),
                        items: _methods.map((m) => DropdownMenuItem(value: m, child: Text(m.name, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _entries[i].method = v);
                        },
                        decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Rp',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          isDense: true,
                          suffixText: i == _entries.length - 1 ? null : null,
                        ),
                        onChanged: (v) {
                          final amt = double.tryParse(v) ?? 0;
                          setState(() => _entries[i].amount = amt);
                        },
                      ),
                    ),
                    if (_entries.length > 1)
                      IconButton(
                        icon: Icon(Icons.remove_circle, color: Colors.red.shade400, size: 20),
                        onPressed: () => _removeEntry(i),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                  ],
                ),
              );
            }),

            TextButton.icon(
              onPressed: _addEntry,
              icon: const Icon(Icons.add, size: 16),
              label: Text(S.t(context, 'Tambah Metode Bayar'), style: const TextStyle(fontSize: 12)),
            ),

            if (_totalPaid > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(S.t(context, 'Total Dibayar:'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(format.format(_totalPaid), style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(S.t(context, 'Kembalian/Kurang:')),
                  Text(
                    _remaining <= 0 ? format.format(_remaining.abs()) : format.format(_remaining),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _remaining <= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading || _entries.every((e) => e.method.id == 0) || _totalPaid < cart.totalAmount
                    ? null
                    : _prosesPembayaran,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : Text(S.t(context, 'Proses Pembayaran'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _prosesPembayaran() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      Navigator.of(context).pop(_entries);
      widget.onPaymentComplete?.call(_entries);
    }
  }
}
