import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../models/customer.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/order_provider.dart';
import '../../services/api_service.dart';
import '../../services/offline_sync_service.dart';
import '../../services/printer_service.dart';
import '../../widgets/cart_item_tile.dart';
import '../../widgets/product_card.dart';
import '../../widgets/payment_dialog.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();
  final PrinterService _printer = PrinterService();
  final OfflineSyncService _offline = OfflineSyncService();
  List<Product> _products = [];
  bool _isScanning = false;
  String _orderType = 'dine_in';
  String _queueNumber = '';
  List<Map<String, dynamic>> _tables = [];
  int? _tableId;
  bool _isInstallment = false;
  String _installmentPeriod = 'monthly';
  int _installmentCount = 1;
  Customer? _selectedCustomer;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _offline.init();
    _isOnline = _offline.isOnline;
    _offline.addListener((online) {
      if (mounted) setState(() => _isOnline = online);
      if (online) _offline.syncPendingOrders();
    });
    _loadProducts();
    _loadTables();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _offline.removeListener((_) {});
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      await _loadProducts();
      return;
    }
    if (_isOnline) {
      try {
        final response = await _api.get('/products?search=$query');
        final data = response['data'] ?? response;
        setState(() => _products = (data as List).map((j) => Product.fromJson(j)).toList());
        _offline.cacheProducts(data.cast<Map<String, dynamic>>());
      } catch (_) {
        await _searchOffline(query);
      }
    } else {
      await _searchOffline(query);
    }
  }

  Future<void> _loadProducts() async {
    if (_isOnline) {
      try {
        final response = await _api.get('/products?per_page=50');
        final data = response['data'] ?? response;
        setState(() => _products = (data as List).map((j) => Product.fromJson(j)).toList());
        _offline.cacheProducts(data.cast<Map<String, dynamic>>());
      } catch (_) {
        await _searchOffline(null);
      }
    } else {
      await _searchOffline(null);
    }
  }

  Future<void> _searchOffline(String? query) async {
    final results = await _offline.searchProducts(query);
    setState(() => _products = results.map((m) => Product(
      id: m['id'],
      name: m['name'] ?? '',
      sku: m['sku'],
      barcode: m['barcode'],
      sellingPrice: (m['selling_price'] ?? 0).toDouble(),
      currentStock: m['current_stock'] ?? 0,
      image: m['image'],
      categoryName: m['category_name'],
    )).toList());
  }

  Future<void> _loadTables() async {
    try {
      final response = await _api.get('/tables');
      final data = response['data'] ?? response;
      setState(() => _tables = (data as List).map((j) => j as Map<String, dynamic>).toList());
    } catch (_) {}
  }

  Future<void> _scanBarcode(String barcode) async {
    try {
      Map<String, dynamic>? productData;
      if (_isOnline) {
        final response = await _api.post('/products/barcode', body: {'barcode': barcode});
        productData = (response['data'] ?? response);
      } else {
        productData = await _offline.getProductByBarcode(barcode);
      }

      if (productData != null && productData.isNotEmpty) {
        final product = Product.fromJson(productData);
        if (!mounted) return;
        context.read<CartProvider>().addItem(product);
        setState(() => _isScanning = false);
      } else {
        _showError('Produk tidak ditemukan: $barcode');
      }
    } catch (e) {
      _showError('Produk tidak ditemukan: $barcode');
    }
  }

  Future<void> _checkout() async {
    final cart = context.read<CartProvider>();
    if (cart.items.isEmpty) return;

    final result = await showDialog<List<PaymentEntry>>(
      context: context,
      builder: (_) => const PaymentDialog(),
    );

    if (result != null && result.isNotEmpty && mounted) {
      _processOrder(result);
    }
  }

  Future<void> _processOrder(List<PaymentEntry> paymentEntries) async {
    final cart = context.read<CartProvider>();
    final orderProvider = context.read<OrderProvider>();
    final auth = context.read<AuthProvider>();

    final payload = cart.toOrderPayload();
    payload['outlet_id'] = 1;
    payload['order_type'] = _orderType;
    payload['table_id'] = _tableId;
    payload['employee_id'] = auth.user?.id;
    payload['is_installment'] = _isInstallment;
    payload['installment_period'] = _isInstallment ? _installmentPeriod : null;
    payload['installment_count'] = _isInstallment ? _installmentCount : 1;
    payload['payments'] = paymentEntries.map((e) => {
      'payment_method_id': e.method.id,
      'amount': e.amount,
    }).toList();

    if (!_isOnline) {
      await _offline.queueOrder(payload);
      cart.clear();
      _selectedCustomer = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pesanan disimpan offline, akan dikirim saat online'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    final order = await orderProvider.createOrder(payload);

    if (order != null && mounted) {
      cart.clear();
      _selectedCustomer = null;
      _queueNumber = order.orderNumber;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pesanan ${order.orderNumber} berhasil!${order.queueNumber != null ? " Antrian: ${order.queueNumber}" : ""}'),
          backgroundColor: Colors.green,
        ),
      );
      _showPrintReceiptDialog(order);
    }
  }

  Future<void> _showPrintReceiptDialog(dynamic order) async {
    final auth = context.read<AuthProvider>();
    final items = (order.items as List?)?.map((i) => {
      'name': i.productName as String,
      'qty': i.quantity as int,
      'price': i.unitPrice as double,
      'subtotal': i.subtotal as double,
    }).toList() ?? [];

    final paid = (order.payments as List?)?.fold<double>(0, (s, p) => s + (p.amount as double)) ?? order.totalAmount;
    final change = paid - order.totalAmount;

    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Cetak Struk', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            if (_printer.isConnected)
              ListTile(
                leading: const Icon(Icons.bluetooth),
                title: const Text('Print Bluetooth'),
                subtitle: const Text('Cetak ke printer thermal Bluetooth'),
                onTap: () {
                  Navigator.pop(context, 'bluetooth');
                },
              ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Share / Print PDF'),
              subtitle: const Text('Share via WhatsApp, simpan ke HP, atau print'),
              onTap: () {
                Navigator.pop(context, 'pdf');
              },
            ),
            ListTile(
              leading: const Icon(Icons.print),
              title: const Text('Print Langsung'),
              subtitle: const Text('Print ke printer via sistem Android'),
              onTap: () {
                Navigator.pop(context, 'printer');
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Nanti Saja'),
              onTap: () {
                Navigator.pop(context, null);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;

    final pdfBytes = await _printer.generatePdfReceipt(
      orderNumber: order.orderNumber,
      date: DateTime.now(),
      cashier: auth.user?.name ?? 'Kasir',
      items: items,
      subtotal: order.subtotal,
      discount: order.discountAmount,
      tax: order.taxAmount,
      total: order.totalAmount,
      paid: paid,
      change: change,
      customerName: order.customerName,
    );

    switch (result) {
      case 'bluetooth':
        await _printReceipt(order);
      case 'pdf':
      case 'printer':
        await _printer.shareReceiptPdf(pdfBytes, orderNumber: order.orderNumber);
        return;
    }
  }

  Future<void> _printReceipt(dynamic order) async {
    final auth = context.read<AuthProvider>();
    await _printer.printReceipt(
      orderNumber: order.orderNumber,
      date: DateTime.now(),
      cashier: auth.user?.name ?? 'Kasir',
      items: (order.items as List?)?.map((i) => {
        'name': i.productName,
        'qty': i.quantity,
        'price': i.unitPrice,
        'subtotal': i.subtotal,
      }).toList() ?? [],
      subtotal: order.subtotal,
      discount: order.discountAmount,
      tax: order.taxAmount,
      total: order.totalAmount,
      paid: (order.payments as List?)?.fold<double>(0, (s, p) => s + (p.amount as double)) ?? order.totalAmount,
      change: ((order.payments as List?)?.fold<double>(0, (s, p) => s + (p.amount as double)) ?? order.totalAmount) - order.totalAmount,
      customerName: order.customerName,
    );
  }

  Future<void> _selectCustomer() async {
    final customer = await showDialog<Customer>(
      context: context,
      builder: (_) => const CustomerSearchDialog(),
    );
    if (customer != null) {
      if (!mounted) return;
      setState(() => _selectedCustomer = customer);
      context.read<CartProvider>().setCustomer(customer.id, customer.name);
    }
  }

  Future<void> _connectPrinter() async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Printer Bluetooth'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: FutureBuilder(
            future: _printer.scanDevices(),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final devices = snapshot.data ?? [];
              if (devices.isEmpty) {
                return const Center(child: Text('Tidak ada printer ditemukan.\nPastikan Bluetooth aktif.'));
              }
              return ListView.builder(
                itemCount: devices.length,
                itemBuilder: (_, i) {
                  final d = devices[i];
                  return ListTile(
                    leading: const Icon(Icons.print),
                    title: Text(d.platformName.isNotEmpty ? d.platformName : d.remoteId.toString()),
                    subtitle: Text(d.remoteId.toString()),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await _printer.connect(d);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(ok ? 'Terhubung ke printer' : 'Gagal terhubung')),
                        );
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
      ),
    );
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final theme = Theme.of(context);
    final format = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          color: theme.colorScheme.surfaceContainerHighest,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Cari produk atau scan barcode...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchCtrl.clear(); _loadProducts(); })
                              : null,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: theme.colorScheme.surface,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        ),
                        onChanged: (v) => _search(v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      icon: Icon(_isScanning ? Icons.close : Icons.qr_code_scanner),
                      onPressed: () => setState(() => _isScanning = !_isScanning),
                    ),
                    IconButton.filled(
                      icon: const Icon(Icons.bluetooth_connected),
                      onPressed: _connectPrinter,
                    ),
                    IconButton.filled(
                      icon: const Icon(Icons.person_add),
                      onPressed: _selectCustomer,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _orderTypeChip('dine_in', 'Dine In', Icons.table_restaurant),
                    const SizedBox(width: 4),
                    _orderTypeChip('takeaway', 'Takeaway', Icons.takeout_dining),
                    const SizedBox(width: 4),
                    _orderTypeChip('delivery', 'Delivery', Icons.delivery_dining),
                    if (!_isOnline) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('OFFLINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.orange)),
                      ),
                    ],
                    const Spacer(),
                    if (_orderType == 'dine_in') ...[
                      SizedBox(
                        width: 130,
                        child: DropdownButtonFormField<int?>(
                          initialValue: _tableId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Meja',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          ),
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('Tanpa Meja', style: TextStyle(fontSize: 12))),
                            ..._tables.map((t) => DropdownMenuItem<int?>(
                              value: t['id'] as int?,
                              child: Text('${t['name']} (${t['capacity']} org)', style: const TextStyle(fontSize: 12)),
                            )),
                          ],
                          onChanged: (v) => setState(() => _tableId = v),
                        ),
                      ),
                    ],
                    if (_queueNumber.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Antrian: $_queueNumber',
                            style: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.onPrimaryContainer)),
                      ),
                    ],
                  ],
                ),
                Row(
                  children: [
                    if (_selectedCustomer != null) ...[
                      Chip(
                        avatar: const Icon(Icons.person, size: 16),
                        label: Text(_selectedCustomer!.name, style: const TextStyle(fontSize: 11)),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () {
                          setState(() => _selectedCustomer = null);
                          context.read<CartProvider>().setCustomer(null, null);
                        },
                      ),
                      const SizedBox(width: 4),
                    ],
                    FilterChip(
                      label: const Text('Cicilan/Kasbon', style: TextStyle(fontSize: 11)),
                      selected: _isInstallment,
                      onSelected: (v) => setState(() => _isInstallment = v),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (_isInstallment) ...[
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 90,
                        child: DropdownButtonFormField<String>(
                          initialValue: _installmentPeriod,
                          isDense: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          ),
                          style: const TextStyle(fontSize: 12),
                          items: const [
                            DropdownMenuItem(value: 'weekly', child: Text('Mingguan', style: TextStyle(fontSize: 11))),
                            DropdownMenuItem(value: 'biweekly', child: Text('2 Minggu', style: TextStyle(fontSize: 11))),
                            DropdownMenuItem(value: 'monthly', child: Text('Bulanan', style: TextStyle(fontSize: 11))),
                          ],
                          onChanged: (v) => setState(() => _installmentPeriod = v!),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 60,
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Jml',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 12),
                          onChanged: (v) => _installmentCount = int.tryParse(v) ?? 1,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),

        if (_isScanning)
          SizedBox(
            height: 180,
            child: MobileScanner(
              onDetect: (capture) {
                final barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final barcode = barcodes.first.rawValue;
                  if (barcode != null) _scanBarcode(barcode);
                }
              },
            ),
          ),

        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: _buildProductGrid(),
              ),
              Container(
                width: 300,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  border: Border(left: BorderSide(color: theme.dividerColor)),
                ),
                child: _buildCartPanel(cart, theme, format),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductGrid() {
    if (_products.isEmpty) {
      return const Center(child: Text('Tidak ada produk'));
    }
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisExtent: 110,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _products.length,
      itemBuilder: (_, i) => ProductCard(
        product: _products[i],
        onTap: () => context.read<CartProvider>().addItem(_products[i]),
      ),
    );
  }

  Widget _buildCartPanel(CartProvider cart, ThemeData theme, NumberFormat format) {
    if (cart.items.isEmpty) {
      return const Center(child: Text('Keranjang kosong', style: TextStyle(color: Colors.grey)));
    }

    final items = cart.items;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Keranjang (${cart.itemCount})',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(format.format(cart.totalAmount),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: theme.colorScheme.primary)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: items.length + 1,
            itemBuilder: (_, i) {
              if (i < items.length) {
                return CartItemTile(
                  item: items[i],
                  index: i,
                  onQuantityChanged: (idx, qty) => cart.updateQuantity(idx, qty),
                  onDiscountChanged: (idx, pct) => cart.updateDiscount(idx, pct),
                  onRemove: () => cart.removeItem(i),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _checkout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Bayar ${format.format(cart.totalAmount)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _orderTypeChip(String type, String label, IconData icon) {
    final selected = _orderType == type;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
      selected: selected,
      onSelected: (v) {
        setState(() {
          _orderType = type;
          if (type != 'dine_in') _tableId = null;
        });
      },
    );
  }
}

class CustomerSearchDialog extends StatefulWidget {
  const CustomerSearchDialog({super.key});

  @override
  State<CustomerSearchDialog> createState() => _CustomerSearchDialogState();
}

class _CustomerSearchDialogState extends State<CustomerSearchDialog> {
  final ApiService _api = ApiService();
  final TextEditingController _ctrl = TextEditingController();
  List<Customer> _customers = [];
  bool _loading = false;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _showAddForm = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final response = await _api.get('/customers?search=$q');
      final data = response['data'] ?? response;
      setState(() => _customers = (data as List).map((j) => Customer.fromJson(j)).toList());
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _addCustomer() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final response = await _api.post('/customers', body: {
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
      });
      final data = response['data'] ?? response;
      final customer = Customer.fromJson(data);
      if (mounted) Navigator.of(context).pop(customer);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
        );
      }
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('Pilih Customer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _showAddForm = !_showAddForm),
                  child: Text(_showAddForm ? 'Batal' : '+ Baru'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_showAddForm) ...[
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: 'Telepon', border: OutlineInputBorder(), isDense: true),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loading ? null : _addCustomer,
                child: const Text('Simpan Customer'),
              ),
            ] else ...[
              TextField(
                controller: _ctrl,
                decoration: const InputDecoration(
                  hintText: 'Cari nama atau telepon...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: _search,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 250,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _customers.isEmpty
                        ? const Center(child: Text('Tidak ada customer', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: _customers.length,
                            itemBuilder: (_, i) {
                              final c = _customers[i];
                              return ListTile(
                                leading: CircleAvatar(child: Text(c.name[0].toUpperCase())),
                                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(c.phone ?? '-'),
                                trailing: c.totalPoints != null
                                    ? Chip(label: Text('${c.totalPoints} pts', style: const TextStyle(fontSize: 10)))
                                    : null,
                                onTap: () => Navigator.of(context).pop(c),
                              );
                            },
                          ),
              ),
            ],
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Skip / Walk-in')),
          ],
        ),
      ),
    );
  }
}
