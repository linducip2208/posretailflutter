import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/lang_provider.dart';
import '../../l10n/s.dart';
import '../../models/category.dart';
import '../../models/customer.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/order_provider.dart';
import '../../services/api_service.dart';
import '../../services/offline_sync_service.dart';
import '../../services/printer_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/cart_item_tile.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/payment_dialog.dart';
import '../../widgets/product_card.dart';
import '../orders/orders_screen.dart';
import '../outlet/outlet_selection_screen.dart';

/// Layar kasir (POS) — diprioritaskan untuk kecepatan operasional:
/// - satu tangan: checkout bar selalu terjangkau di bawah
/// - tablet: keranjang panel samping
/// - hasil transaksi hanya tampil setelah server mengonfirmasi
///   (atau dicatat eksplisit sebagai antrean offline).
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
  List<Category> _categories = [];
  int? _categoryId;
  bool _isLoadingProducts = false;
  String? _productError;

  bool _isScanning = false;
  String _queueNumber = '';
  bool _isInstallment = false;
  String _installmentPeriod = 'monthly';
  int _installmentCount = 1;
  Customer? _selectedCustomer;
  bool _isOnline = true;
  bool _isProcessing = false;
  bool _isSyncing = false;
  int _pendingSyncCount = 0;
  int _failedSyncCount = 0;
  String? _lastBarcode;
  DateTime? _lastScanAt;
  late final void Function(bool) _connectivityListener;
  String? _clientUuid;
  String? _clientUuidFingerprint;
  Timer? _searchDebounce;

  static const Duration _searchDebounceDelay = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _offline.init();
    _isOnline = _offline.isOnline;
    _connectivityListener = (online) {
      // `mounted` State masih true pada jendela unmount (elemen defunct);
      // `context.mounted` menutup celah itu agar setState tidak melempar.
      if (!mounted || !context.mounted) return;
      setState(() => _isOnline = online);
      if (online) {
        _syncPending(force: false);
        _refreshQueueCounts();
      }
    };
    _offline.addListener(_connectivityListener);
    _loadCategories();
    _loadProducts();
    _refreshQueueCounts();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _offline.removeListener(_connectivityListener);
    super.dispose();
  }

  int? get _outletId => context.read<AuthProvider>().currentOutletId;

  // ---------------------------------------------------------------- produk

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDelay, () {
      _loadProducts(search: value.trim());
    });
  }

  Future<void> _loadCategories() async {
    try {
      final response = await _api.get('/categories');
      final dynamic data = response is Map
          ? (response['categories'] ?? response['data'] ?? response)
          : response;
      if (!mounted || data is! List) return;
      final parsed = data
          .whereType<Map<String, dynamic>>()
          .map(Category.fromJson)
          .toList();
      setState(() => _categories = parsed);
    } catch (_) {
      // Kategori pelengkap — kegagalan tidak memblokir kasir.
    }
  }

  /// Daftar kategori datar (induk + anak) untuk chip filter.
  List<Category> get _flatCategories {
    final out = <Category>[];
    for (final c in _categories) {
      out.add(c);
      out.addAll(c.children);
    }
    return out;
  }

  Future<void> _loadProducts({String? search}) async {
    final query = search ?? _searchCtrl.text.trim();
    setState(() {
      _isLoadingProducts = true;
      _productError = null;
    });

    if (_isOnline) {
      try {
        final response = await _api.get(
          '/products',
          query: {
            'search': query.isEmpty ? null : query,
            'category_id': _categoryId?.toString(),
            'per_page': '50',
          },
        );
        final dynamic data = response is Map
            ? (response['data'] ?? response)
            : response;
        final list = data is List
            ? data.whereType<Map<String, dynamic>>().toList()
            : <Map<String, dynamic>>[];
        if (!mounted) return;
        setState(() {
          _products = list.map(Product.fromJson).toList();
          _isLoadingProducts = false;
        });
        final outletId = _outletId;
        if (outletId != null && list.isNotEmpty) {
          await _offline.cacheProducts(list, outletId: outletId);
        }
        return;
      } on ApiException catch (e) {
        // Jaringan bermasalah → fallback cache lokal (tetap outlet-aware).
        if (e is! ApiNetworkException) {
          if (mounted) {
            setState(() {
              _productError = e.message;
              _isLoadingProducts = false;
            });
          }
          return;
        }
      } catch (_) {
        // jatuh ke cache lokal
      }
    }
    await _searchOffline(query);
  }

  Future<void> _searchOffline(String query) async {
    final outletId = _outletId;
    if (outletId == null) {
      if (mounted) {
        setState(() {
          _products = [];
          _isLoadingProducts = false;
          _productError = S.tn(
            context,
            'Pilih outlet dulu untuk memuat produk offline.',
          );
        });
      }
      return;
    }
    try {
      final results = await _offline.searchProducts(
        query.isEmpty ? null : query,
        outletId: outletId,
      );
      if (!mounted) return;
      setState(() {
        _products = results.map(Product.fromJson).toList();
        _isLoadingProducts = false;
        _productError = results.isEmpty
            ? S.tn(
                context,
                'Tidak ada cache produk untuk outlet ini. Sambungkan ke internet untuk memuat katalog.',
              )
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingProducts = false;
        _productError = S.tn(context, 'Gagal membaca cache produk.');
      });
    }
  }

  Future<void> _scanBarcode(String barcode) async {
    final now = DateTime.now();
    if (_lastBarcode == barcode &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!).inMilliseconds < 1500) {
      return;
    }
    _lastBarcode = barcode;
    _lastScanAt = now;

    try {
      Map<String, dynamic>? productData;
      if (_isOnline) {
        final response = await _api.post(
          '/products/barcode',
          body: {'barcode': barcode},
        );
        final dynamic data = response is Map
            ? (response['data'] ?? response)
            : response;
        productData = data is Map<String, dynamic> ? data : null;
      } else {
        final outletId = _outletId;
        productData = outletId == null
            ? null
            : await _offline.getProductByBarcode(barcode, outletId: outletId);
      }

      if (!mounted) return;
      if (productData != null && productData.isNotEmpty) {
        final product = Product.fromJson(productData);
        _addToCart(product, scannedBarcode: barcode);
        setState(() => _isScanning = false);
      } else {
        _showSnack('Produk tidak ditemukan: $barcode', SnackType.error);
      }
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        _showSnack('Produk tidak ditemukan: $barcode', SnackType.error);
      } else if (e is ApiNetworkException) {
        final outletId = _outletId;
        final cached = outletId == null
            ? null
            : await _offline.getProductByBarcode(barcode, outletId: outletId);
        if (!mounted) return;
        if (cached != null) {
          _addToCart(Product.fromJson(cached), scannedBarcode: barcode);
          setState(() => _isScanning = false);
        } else {
          _showSnack(e.message, SnackType.error);
        }
      } else {
        _showSnack(e.message, SnackType.error);
      }
    } catch (_) {
      _showSnack('Gagal memproses barcode: $barcode', SnackType.error);
    }
  }

  void _addToCart(Product product, {String? scannedBarcode}) {
    if (product.hasVariants) {
      _pickVariant(product, scannedBarcode: scannedBarcode);
      return;
    }
    if (product.currentStock <= 0) {
      _showSnack(
        'Stok "${product.name}" habis di outlet ini.',
        SnackType.warning,
      );
      return;
    }
    context.read<CartProvider>().addItem(product);
  }

  /// Pilih varian sebelum masuk keranjang (harga & stok per varian
  /// divalidasi server saat checkout).
  Future<void> _pickVariant(Product product, {String? scannedBarcode}) async {
    final theme = Theme.of(context);
    int? preselectedId;
    if (scannedBarcode != null) {
      for (final v in product.variants) {
        if (v.barcode == scannedBarcode) {
          preselectedId = v.id;
          break;
        }
      }
    }

    final variant = await showModalBottomSheet<ProductVariant>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 16),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  S.t(sheetContext, 'Pilih varian'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: product.variants.length,
              itemBuilder: (_, i) {
                final variant = product.variants[i];
                final soldOut = variant.currentStock <= 0;
                final isPreselected = variant.id == preselectedId;
                return ListTile(
                  enabled: !soldOut,
                  leading: CircleAvatar(
                    backgroundColor: soldOut
                        ? AppColors.errorSoft
                        : AppColors.primarySoft,
                    child: Icon(
                      soldOut ? Icons.block : Icons.inventory_2_outlined,
                      size: 18,
                      color: soldOut ? AppColors.error : AppColors.primaryDark,
                    ),
                  ),
                  title: Text(
                    variant.name,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    soldOut
                        ? S.t(sheetContext, 'Stok habis')
                        : '${S.t(sheetContext, 'Stok')}: ${variant.currentStock}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: soldOut ? AppColors.error : null,
                    ),
                  ),
                  trailing: Text(
                    Fmt.rupiah(
                      variant.sellingPrice > 0
                          ? variant.sellingPrice
                          : product.sellingPrice,
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  selected: isPreselected,
                  onTap: soldOut
                      ? null
                      : () => Navigator.pop(sheetContext, variant),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );

    if (variant == null || !mounted) return;
    context.read<CartProvider>().addItem(product, variant: variant);
  }

  // -------------------------------------------------------------------- cart

  Future<void> _refreshQueueCounts() async {
    final pending = await _offline.getPendingCount();
    final failed = await _offline.getFailedCount();
    if (!mounted || !context.mounted) return;
    setState(() {
      _pendingSyncCount = pending;
      _failedSyncCount = failed;
    });
  }

  /// UUID checkout stabil: satu isi keranjang = satu client_uuid sehingga
  /// retry setelah timeout / fallback offline tidak membuat order ganda.
  String _clientUuidFor(Map<String, dynamic> payload) {
    final fingerprint = jsonEncode(payload['items']);
    if (_clientUuid == null || _clientUuidFingerprint != fingerprint) {
      _clientUuid = const Uuid().v4();
      _clientUuidFingerprint = fingerprint;
    }
    return _clientUuid!;
  }

  Future<void> _syncPending({bool force = true}) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    final en = context.read<LangProvider>().isEnglish;
    final sent = await _offline.syncPendingOrders(force: force);
    await _refreshQueueCounts();
    if (!mounted) return;
    setState(() => _isSyncing = false);
    if (sent > 0) {
      _showSnack(
        S.e(en, '{n} transaksi offline berhasil dikirim', {'n': '$sent'}),
        SnackType.success,
      );
    } else if (_pendingSyncCount > 0) {
      _showSnack(
        S.tn(context, 'Belum ada transaksi yang berhasil dikirim.'),
        SnackType.warning,
      );
    }
  }

  // ---------------------------------------------------------------- checkout

  Future<void> _checkout() async {
    if (_isProcessing) return;
    final cart = context.read<CartProvider>();
    if (cart.items.isEmpty) return;

    if (_isInstallment && _selectedCustomer == null) {
      _showSnack(
        'Pilih pelanggan dulu untuk transaksi cicilan/kasbon.',
        SnackType.warning,
      );
      return;
    }

    final entries = await PaymentDialog.show(
      context,
      total: cart.totalAmount,
      allowPartial: _isInstallment,
    );
    if (entries == null || entries.isEmpty || !mounted) return;
    await _processOrder(entries);
  }

  Future<void> _processOrder(List<PaymentEntry> paymentEntries) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    final en = context.read<LangProvider>().isEnglish;

    try {
      final cart = context.read<CartProvider>();
      final orderProvider = context.read<OrderProvider>();
      final auth = context.read<AuthProvider>();

      final outletId = auth.currentOutletId;
      if (outletId == null) {
        _showSnack(
          S.e(en, 'Pilih outlet dulu sebelum transaksi'),
          SnackType.error,
        );
        return;
      }

      final payload = cart.toOrderPayload();
      payload['client_uuid'] = _clientUuidFor(payload);
      payload['outlet_id'] = outletId;
      payload['employee_id'] = auth.user?.id;
      payload['is_installment'] = _isInstallment;
      payload['installment_period'] = _isInstallment
          ? _installmentPeriod
          : null;
      payload['installment_count'] = _isInstallment ? _installmentCount : 1;
      payload['payments'] = paymentEntries
          .map((e) => {'payment_method_id': e.method.id, 'amount': e.amount})
          .toList();

      if (!_isOnline) {
        await _queueOffline(payload, cart);
        return;
      }

      final order = await orderProvider.createOrder(payload);

      if (order == null && orderProvider.lastErrorOffline) {
        await _queueOffline(payload, cart);
        return;
      }

      if (order != null) {
        _clientUuid = null;
        _clientUuidFingerprint = null;
      }

      if (!mounted) return;
      if (order != null) {
        cart.clear();
        setState(() {
          _selectedCustomer = null;
          _isInstallment = false;
          _queueNumber = order.orderNumber;
        });
        _showSnack(
          S.e(en, 'Pesanan {no} berhasil!{antri}', {
            'no': order.orderNumber,
            'antri': order.queueNumber != null
                ? ' ${S.e(en, 'Antrian')}: ${order.queueNumber}'
                : '',
          }),
          SnackType.success,
        );
        // Stok server berkurang — segarkan badge stok di background
        // (tidak ditunggu agar struk langsung tampil).
        unawaited(_loadProducts());
        await _showReceiptSheet(order);
      } else {
        _showSnack(
          orderProvider.error ??
              S.e(en, 'Transaksi gagal, tidak ada order dibuat'),
          SnackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Simpan transaksi ke antrean offline — TIDAK diklaim lunas oleh server.
  Future<void> _queueOffline(
    Map<String, dynamic> payload,
    CartProvider cart,
  ) async {
    final en = context.read<LangProvider>().isEnglish;
    await _offline.queueOrder(payload);
    _clientUuid = null;
    _clientUuidFingerprint = null;
    cart.clear();
    await _refreshQueueCounts();
    if (!mounted) return;
    setState(() => _selectedCustomer = null);
    _showSnack(
      S.e(
        en,
        'Pesanan tersimpan di perangkat ({n} menunggu kirim). Bukan bukti lunas server.',
        {'n': '$_pendingSyncCount'},
      ),
      SnackType.warning,
      duration: const Duration(seconds: 5),
    );
  }

  // ------------------------------------------------------------------ receipt

  Future<void> _showReceiptSheet(Order order) async {
    final auth = context.read<AuthProvider>();
    final outletName = auth.currentOutlet?.name;
    final cashier = auth.user?.name ?? 'Kasir';

    double safeNum(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0;
    }

    final items =
        order.items
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

    final paid = order.payments?.fold<double>(0, (s, p) => s + p.amount) ?? 0;
    final total = safeNum(order.totalAmount);
    final remaining = (total - paid).clamp(0, double.infinity).toDouble();
    final change = (paid - total).clamp(0, double.infinity).toDouble();

    final result = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 40,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  S.t(sheetContext, 'Transaksi Berhasil'),
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  '${order.orderNumber}${order.queueNumber != null ? ' · ${S.t(sheetContext, 'Antrian')} ${order.queueNumber}' : ''}',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
                if (remaining > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warningSoft,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      '${S.t(sheetContext, 'Sisa tagihan (kasbon)')}: '
                      '${Fmt.rupiah(remaining)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(S.t(sheetContext, 'Lihat Detail Transaksi')),
            onTap: () => Navigator.pop(sheetContext, 'detail'),
          ),
          if (_printer.isConnected)
            ListTile(
              leading: const Icon(Icons.bluetooth),
              title: Text(S.t(sheetContext, 'Print Bluetooth')),
              subtitle: Text(
                S.t(sheetContext, 'Cetak ke printer thermal Bluetooth'),
              ),
              onTap: () => Navigator.pop(sheetContext, 'bluetooth'),
            ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(S.t(sheetContext, 'Share / Print PDF')),
            subtitle: Text(
              S.t(sheetContext, 'Share via WhatsApp, simpan ke HP, atau print'),
            ),
            onTap: () => Navigator.pop(sheetContext, 'pdf'),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: Text(S.t(sheetContext, 'Selesai')),
            onTap: () => Navigator.pop(sheetContext, null),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );

    if (result == null || !mounted) return;

    if (result == 'detail') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrdersScreen(initialOrderId: order.id),
        ),
      );
      return;
    }

    final pdfBytes = await _printer.generatePdfReceipt(
      orderNumber: order.orderNumber,
      date: DateTime.now(),
      cashier: cashier,
      outletName: outletName,
      items: items,
      subtotal: safeNum(order.subtotal),
      discount: safeNum(order.discountAmount),
      tax: safeNum(order.taxAmount),
      total: total,
      paid: paid,
      change: change,
      remaining: remaining,
      customerName: order.customerName,
    );

    if (result == 'bluetooth') {
      await _printer.printReceipt(
        orderNumber: order.orderNumber,
        date: DateTime.now(),
        cashier: cashier,
        outletName: outletName,
        items: items,
        subtotal: safeNum(order.subtotal),
        discount: safeNum(order.discountAmount),
        tax: safeNum(order.taxAmount),
        total: total,
        paid: paid,
        change: change,
        remaining: remaining,
        customerName: order.customerName,
      );
      if (mounted) {
        _showSnack(
          S.tn(context, 'Struk dikirim ke printer Bluetooth.'),
          SnackType.info,
        );
      }
    } else if (result == 'pdf') {
      await _printer.shareReceiptPdf(pdfBytes, orderNumber: order.orderNumber);
    }
  }

  // ---------------------------------------------------------------- customer

  Future<void> _selectCustomer() async {
    final customer = await showDialog<Customer>(
      context: context,
      builder: (_) => const CustomerSearchDialog(),
    );
    if (customer != null && mounted) {
      setState(() => _selectedCustomer = customer);
      context.read<CartProvider>().setCustomer(customer.id, customer.name);
    }
  }

  // ----------------------------------------------------------------- printer

  Future<void> _connectPrinter() async {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.t(dialogContext, 'Printer Bluetooth')),
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
                return Center(
                  child: Text(
                    S.t(
                      ctx,
                      'Tidak ada printer ditemukan.\nPastikan Bluetooth aktif.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return ListView.builder(
                itemCount: devices.length,
                itemBuilder: (_, i) {
                  final d = devices[i];
                  return ListTile(
                    leading: const Icon(Icons.print),
                    title: Text(
                      d.platformName.isNotEmpty
                          ? d.platformName
                          : d.remoteId.toString(),
                    ),
                    subtitle: Text(d.remoteId.toString()),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await _printer.connect(d);
                      if (!mounted) return;
                      _showSnack(
                        ok
                            ? 'Terhubung ke printer'
                            : 'Gagal terhubung ke printer',
                        ok ? SnackType.success : SnackType.error,
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(S.t(dialogContext, 'Tutup')),
          ),
        ],
      ),
    );
  }

  void _showSnack(
    String message,
    SnackType type, {
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!mounted) return;
    showAppSnackbar(context, message, type: type, duration: duration);
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        return Column(
          children: [
            _buildHeader(context),
            if (_isScanning) _buildScannerPanel(context),
            Expanded(
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _buildProductArea()),
                        _buildCartPanel(context, wide: true),
                      ],
                    )
                  : _buildProductArea(),
            ),
            if (!isWide) _buildCheckoutBar(context),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: S.t(
                        context,
                        'Cari produk atau scan barcode...',
                      ),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                _loadProducts(search: '');
                              },
                            )
                          : null,
                    ),
                    onChanged: _onSearchChanged,
                    onSubmitted: (v) {
                      _searchDebounce?.cancel();
                      _loadProducts(search: v.trim());
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton.filled(
                  tooltip: S.t(context, 'Scan barcode'),
                  icon: Icon(_isScanning ? Icons.close : Icons.qr_code_scanner),
                  onPressed: () => setState(() => _isScanning = !_isScanning),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Flexible(
                  child: ActionChip(
                    avatar: const Icon(Icons.store, size: 16),
                    label: Text(
                      context.watch<AuthProvider>().currentOutlet?.name ??
                          S.t(context, 'Pilih outlet'),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const OutletSelectionScreen(),
                        ),
                      );
                      // Outlet bisa berubah — muat ulang katalog outlet baru.
                      _categoryId = null;
                      await _loadProducts();
                      _refreshQueueCounts();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                if (!_isOnline)
                  const Padding(
                    padding: EdgeInsets.only(right: AppSpacing.xs),
                    child: StatusChipOffline(),
                  ),
                if (_pendingSyncCount > 0)
                  Flexible(
                    child: ActionChip(
                      avatar: _isSyncing
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _failedSyncCount > 0
                                  ? Icons.sync_problem
                                  : Icons.sync,
                              size: 14,
                            ),
                      label: Text(
                        '$_pendingSyncCount ${S.t(context, 'menunggu kirim')}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: _isOnline && !_isSyncing
                          ? () => _syncPending(force: true)
                          : null,
                    ),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: S.t(context, 'Riwayat transaksi'),
                  icon: const Icon(Icons.receipt_long_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OrdersScreen()),
                  ),
                ),
                IconButton(
                  tooltip: S.t(context, 'Cetak / printer'),
                  icon: const Icon(Icons.print_outlined),
                  onPressed: _connectPrinter,
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  tooltip: S.t(context, 'Pilih pelanggan'),
                  icon: const Icon(Icons.person_outline, size: 20),
                  onPressed: _selectCustomer,
                ),
                if (_selectedCustomer != null)
                  Expanded(
                    child: Chip(
                      avatar: const Icon(Icons.person, size: 16),
                      label: Text(
                        _selectedCustomer!.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        setState(() => _selectedCustomer = null);
                        context.read<CartProvider>().setCustomer(null, null);
                      },
                    ),
                  )
                else
                  Expanded(
                    child: Text(
                      S.t(context, 'Walk-in (tanpa pelanggan)'),
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                    ),
                  ),
                FilterChip(
                  label: Text(
                    S.t(context, 'Cicilan/Kasbon'),
                    style: const TextStyle(fontSize: 11),
                  ),
                  selected: _isInstallment,
                  onSelected: (v) => setState(() => _isInstallment = v),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (_isInstallment)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _installmentPeriod,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: 'Periode',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.sm,
                          ),
                        ),
                        style: const TextStyle(fontSize: 12),
                        items: [
                          DropdownMenuItem(
                            value: 'weekly',
                            child: Text(
                              S.t(context, 'Mingguan'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'biweekly',
                            child: Text(
                              S.t(context, '2 Minggu'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'monthly',
                            child: Text(
                              S.t(context, 'Bulanan'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _installmentPeriod = v ?? 'monthly'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Jumlah',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.sm,
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 12),
                        onChanged: (v) => _installmentCount =
                            int.tryParse(v)?.clamp(1, 60) ?? 1,
                      ),
                    ),
                  ],
                ),
              ),
            if (_queueNumber.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      '${S.t(context, 'Antrian')}: $_queueNumber',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerPanel(BuildContext context) {
    return Container(
      height: 220,
      color: Colors.black,
      child: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isEmpty) return;
              final barcode = barcodes.first.rawValue;
              if (barcode != null && barcode.isNotEmpty) _scanBarcode(barcode);
            },
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'Kamera tidak dapat dibuka. Periksa izin kamera di pengaturan Android.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white),
                ),
              ),
            ),
            placeholderBuilder: (context) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: IconButton.filledTonal(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _isScanning = false),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: AppSpacing.sm,
            child: Text(
              S.t(context, 'Arahkan kamera ke barcode produk'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductArea() {
    if (_isLoadingProducts && _products.isEmpty) {
      return const LoadingSkeleton(items: 6, itemHeight: 72);
    }
    if (_productError != null && _products.isEmpty) {
      return ErrorState(
        message: _productError!,
        icon: Icons.inventory_2_outlined,
        onRetry: () => _loadProducts(),
      );
    }
    if (_products.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: S.t(context, 'Tidak ada produk'),
        message: S.t(
          context,
          'Coba kata kunci lain atau ubah filter kategori.',
        ),
      );
    }

    return Column(
      children: [
        if (_flatCategories.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    label: Text(S.t(context, 'Semua')),
                    selected: _categoryId == null,
                    onSelected: (_) {
                      setState(() => _categoryId = null);
                      _loadProducts();
                    },
                  ),
                ),
                for (final category in _flatCategories)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ChoiceChip(
                      label: Text(category.name),
                      selected: _categoryId == category.id,
                      onSelected: (_) {
                        setState(
                          () => _categoryId = _categoryId == category.id
                              ? null
                              : category.id,
                        );
                        _loadProducts();
                      },
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadProducts(),
            child: GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.sm),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                mainAxisExtent: 158,
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing: AppSpacing.sm,
              ),
              itemCount: _products.length,
              itemBuilder: (_, i) => ProductCard(
                product: _products[i],
                onTap: () => _addToCart(_products[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Panel keranjang untuk layar lebar (tablet).
  Widget _buildCartPanel(BuildContext context, {required bool wide}) {
    final theme = Theme.of(context);
    final cart = context.watch<CartProvider>();
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${S.t(context, 'Keranjang')} (${cart.itemCount})',
                    style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
                  ),
                ),
                if (cart.items.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      final ok = await confirmClearCart(context);
                      if (ok) cart.clear();
                    },
                    child: Text(
                      S.t(context, 'Kosongkan'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: cart.items.isEmpty
                ? EmptyState(
                    icon: Icons.shopping_cart_outlined,
                    title: S.t(context, 'Keranjang kosong'),
                    message: S.t(
                      context,
                      'Ketuk produk untuk menambahkan ke keranjang.',
                    ),
                  )
                : _cartList(cart),
          ),
          _cartTotals(context, cart),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: cart.items.isEmpty || _isProcessing
                    ? null
                    : _checkout,
                child: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        '${S.t(context, 'Bayar')} · ${Fmt.rupiah(cart.totalAmount)}',
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartList(CartProvider cart) {
    final items = cart.items;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      itemCount: items.length,
      itemBuilder: (_, i) => CartItemTile(
        item: items[i],
        index: i,
        onQuantityChanged: (idx, qty) => cart.updateQuantity(idx, qty),
        onDiscountChanged: (idx, pct) => cart.updateDiscount(idx, pct),
        onRemove: () => cart.removeItem(i),
      ),
    );
  }

  Widget _cartTotals(BuildContext context, CartProvider cart) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          _totalRow(context, S.t(context, 'Subtotal'), cart.subtotal),
          if (cart.totalDiscountAmount > 0)
            _totalRow(
              context,
              S.t(context, 'Diskon'),
              -cart.totalDiscountAmount,
              color: AppColors.error,
            ),
          if (cart.taxAmount > 0)
            _totalRow(context, S.t(context, 'Pajak'), cart.taxAmount),
          _totalRow(
            context,
            S.t(context, 'Total'),
            cart.totalAmount,
            emphasize: true,
          ),
        ],
      ),
    );
  }

  Widget _totalRow(
    BuildContext context,
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
                  ? theme.textTheme.titleSmall?.copyWith(fontSize: 14)
                  : theme.textTheme.bodySmall?.copyWith(fontSize: 12.5),
            ),
          ),
          Text(
            Fmt.rupiah(amount),
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              fontSize: emphasize ? 15 : 12.5,
              color: color ?? (emphasize ? theme.colorScheme.primary : null),
            ),
          ),
        ],
      ),
    );
  }

  /// Bar checkout layar kecil: selalu terlihat selama keranjang terisi.
  Widget _buildCheckoutBar(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final theme = Theme.of(context);
    if (cart.items.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${cart.totalQuantity} ${S.t(context, 'item')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                      ),
                    ),
                    Text(
                      Fmt.rupiah(cart.totalAmount),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _openCartSheet(),
                icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                label: Text('${cart.itemCount}'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: _isProcessing ? null : _checkout,
                child: _isProcessing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(S.t(context, 'Bayar')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCartSheet() async {
    final shouldCheckout = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return Consumer<CartProvider>(
          builder: (context, cart, _) {
            final maxHeight = MediaQuery.sizeOf(context).height * 0.75;
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${S.t(context, 'Keranjang')} (${cart.itemCount})',
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium?.copyWith(fontSize: 16),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final ok = await confirmClearCart(context);
                            if (ok) cart.clear();
                          },
                          child: Text(
                            S.t(context, 'Kosongkan'),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(child: _cartList(cart)),
                  _cartTotals(context, cart),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: cart.items.isEmpty
                            ? null
                            : () => Navigator.pop(sheetContext, true),
                        child: Text(
                          '${S.t(context, 'Bayar')} · ${Fmt.rupiah(cart.totalAmount)}',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (shouldCheckout == true && mounted) {
      await _checkout();
    }
  }

  Future<bool> confirmClearCart(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t(ctx, 'Kosongkan keranjang?')),
        content: Text(S.t(ctx, 'Semua item di keranjang akan dihapus.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t(ctx, 'Batal')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t(ctx, 'Kosongkan')),
          ),
        ],
      ),
    ).then((value) => value ?? false);
  }
}

class StatusChipOffline extends StatelessWidget {
  const StatusChipOffline({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: const Text(
        'OFFLINE',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Color(0xFFB45309),
        ),
      ),
    );
  }
}

/// Dialog pencarian + tambah pelanggan cepat dari POS.
class CustomerSearchDialog extends StatefulWidget {
  const CustomerSearchDialog({super.key});

  @override
  State<CustomerSearchDialog> createState() => _CustomerSearchDialogState();
}

class _CustomerSearchDialogState extends State<CustomerSearchDialog> {
  final ApiService _api = ApiService();
  final TextEditingController _ctrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  List<Customer> _customers = [];
  bool _loading = false;
  String? _error;
  bool _showAddForm = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _search(value.trim());
    });
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.get(
        '/customers',
        query: {'search': q.isEmpty ? null : q, 'per_page': '50'},
      );
      final dynamic data = response is Map
          ? (response['data'] ?? response)
          : response;
      if (!mounted) return;
      setState(() {
        _customers = data is List
            ? data
                  .whereType<Map<String, dynamic>>()
                  .map(Customer.fromJson)
                  .toList()
            : [];
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Gagal mencari pelanggan. Coba lagi.');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addCustomer() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      if (mounted) {
        setState(() => _error = 'Nama pelanggan wajib diisi.');
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.post(
        '/customers',
        body: {'name': name, 'phone': _phoneCtrl.text.trim()},
      );
      final dynamic data = response is Map
          ? (response['data'] ?? response)
          : response;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('respons tidak dikenali');
      }
      final customer = Customer.fromJson(data);
      if (mounted) Navigator.of(context).pop(customer);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Gagal menyimpan pelanggan. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    S.t(context, 'Pilih Customer'),
                    style: theme.textTheme.titleMedium?.copyWith(fontSize: 17),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _showAddForm = !_showAddForm),
                  child: Text(
                    _showAddForm
                        ? S.t(context, 'Batal')
                        : S.t(context, '+ Baru'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(_error!, style: const TextStyle(fontSize: 12)),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            if (_showAddForm) ...[
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: S.t(context, 'Nama'),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _phoneCtrl,
                decoration: InputDecoration(
                  labelText: S.t(context, 'Telepon'),
                  isDense: true,
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _loading ? null : _addCustomer,
                child: Text(S.t(context, 'Simpan Customer')),
              ),
            ] else ...[
              TextField(
                controller: _ctrl,
                decoration: InputDecoration(
                  hintText: S.t(context, 'Cari nama atau telepon...'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                ),
                onChanged: _onQueryChanged,
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 260,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _customers.isEmpty
                    ? EmptyState(
                        icon: Icons.people_outline,
                        title: S.t(context, 'Tidak ada customer'),
                        message: S.t(
                          context,
                          'Tambahkan pelanggan baru dengan tombol + Baru.',
                        ),
                      )
                    : ListView.builder(
                        itemCount: _customers.length,
                        itemBuilder: (_, i) {
                          final c = _customers[i];
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                c.name.isNotEmpty
                                    ? c.name[0].toUpperCase()
                                    : '?',
                              ),
                            ),
                            title: Text(
                              c.name.isNotEmpty
                                  ? c.name
                                  : S.t(context, '(tanpa nama)'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(c.phone ?? '-'),
                            trailing: c.totalPoints != null
                                ? Text(
                                    '${c.totalPoints} pts',
                                    style: const TextStyle(fontSize: 11.5),
                                  )
                                : null,
                            onTap: () => Navigator.of(context).pop(c),
                          );
                        },
                      ),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(S.t(context, 'Skip / Walk-in')),
            ),
          ],
        ),
      ),
    );
  }
}
