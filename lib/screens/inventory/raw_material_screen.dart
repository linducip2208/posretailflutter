import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../../l10n/s.dart';
import '../../models/inventory_ops.dart';
import '../../services/api_service.dart';
import '../../services/secure_token_storage.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';

/// PUT bahan baku belum tersedia di [ApiService], jadi update
/// dilakukan lewat [ApiService.client] langsung (pola supplier).
Future<dynamic> _sendPut(String path, Map<String, dynamic> body) async {
  String? token;
  try {
    token = await SecureTokenStorage().readToken();
  } catch (_) {
    token = null;
  }
  final uri = Uri.parse('${ApiConfig.baseUrl}$path');
  final headers = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };
  http.Response response;
  try {
    response = await ApiService.client
        .put(uri, headers: headers, body: jsonEncode(body))
        .timeout(ApiConfig.requestTimeout);
  } on TimeoutException {
    throw ApiNetworkException(
      'Koneksi ke server timeout. Periksa jaringan lalu coba lagi.',
    );
  } on SocketException {
    throw ApiNetworkException(
      'Tidak dapat terhubung ke server. Periksa jaringan Anda.',
    );
  } on http.ClientException {
    throw ApiNetworkException(
      'Koneksi ke server gagal. Periksa jaringan Anda.',
    );
  }
  dynamic decoded;
  try {
    decoded = response.body.isNotEmpty ? jsonDecode(response.body) : {};
  } catch (_) {
    decoded = {};
  }
  if (response.statusCode >= 200 && response.statusCode < 300) return decoded;
  throw ApiException(
    statusCode: response.statusCode,
    message:
        (decoded is Map && decoded['message'] != null
            ? decoded['message'].toString()
            : null) ??
        'Request gagal.',
    errors: decoded is Map ? decoded['errors'] : null,
  );
}

/// Bahan baku & resep: daftar (badge stok menipis), tambah/ubah,
/// dan lihat/simpan resep per produk.
class RawMaterialScreen extends StatefulWidget {
  const RawMaterialScreen({super.key});

  @override
  State<RawMaterialScreen> createState() => _RawMaterialScreenState();
}

class _RawMaterialScreenState extends State<RawMaterialScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _debounce;

  List<RawMaterial> _materials = [];
  bool _loading = true;
  String? _error;
  bool _lowOnly = false;

  // Resep per produk.
  final TextEditingController _productSearchCtrl = TextEditingController();
  Timer? _productDebounce;
  List<Map<String, dynamic>> _foundProducts = [];
  bool _searchingProduct = false;
  Map<String, dynamic>? _selectedProduct;
  Recipe? _recipe;
  bool _loadingRecipe = false;
  String? _recipeError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _productDebounce?.cancel();
    _searchCtrl.dispose();
    _productSearchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _refresh);
  }

  void _onProductSearchChanged(String _) {
    _productDebounce?.cancel();
    _productDebounce = Timer(
      const Duration(milliseconds: 350),
      _searchProducts,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.get(
        '/raw-materials',
        query: {
          if (_searchCtrl.text.trim().isNotEmpty)
            'search': _searchCtrl.text.trim(),
          if (_lowOnly) 'low_stock': '1',
        },
      );
      final data = response is Map ? response['data'] : response;
      if (!mounted) return;
      setState(() {
        _materials = data is List
            ? data
                  .whereType<Map<String, dynamic>>()
                  .map(RawMaterial.fromJson)
                  .toList()
            : [];
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = S.tn(context, 'Gagal memuat bahan baku.');
      });
    }
  }

  Future<void> _searchProducts() async {
    final q = _productSearchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _foundProducts = []);
      return;
    }
    setState(() => _searchingProduct = true);
    try {
      final response = await _api.get('/products', query: {'search': q});
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      setState(() {
        _foundProducts = data is List
            ? data.whereType<Map<String, dynamic>>().toList()
            : [];
        _searchingProduct = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searchingProduct = false);
    }
  }

  static int _asId(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  Future<void> _selectProduct(Map<String, dynamic> raw) async {
    setState(() {
      _selectedProduct = raw;
      _foundProducts = [];
      _productSearchCtrl.clear();
      _recipe = null;
      _recipeError = null;
      _loadingRecipe = true;
    });
    try {
      final id = _asId(raw['id']);
      final response = await _api.get(
        '/recipes',
        query: {'product_id': '$id'},
      );
      final data = response is Map ? response['data'] : response;
      if (!mounted) return;
      setState(() {
        if (data is Map<String, dynamic>) {
          _recipe = Recipe.fromJson(data);
        } else if (data is List && data.isNotEmpty) {
          final first = data.first;
          _recipe = first is Map<String, dynamic>
              ? Recipe.fromJson(first)
              : Recipe(productId: id, items: const []);
        } else {
          _recipe = Recipe(productId: id, items: const []);
        }
        _loadingRecipe = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRecipe = false;
        // 404 = belum ada resep: anggap kosong agar bisa dibuat baru.
        if (e.statusCode == 404) {
          _recipe = Recipe(
            productId: _asId(_selectedProduct?['id']),
            items: const [],
          );
        } else {
          _recipeError = e.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingRecipe = false;
        _recipeError = S.tn(context, 'Gagal memuat resep.');
      });
    }
  }

  Future<void> _openMaterialDialog({RawMaterial? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _MaterialFormDialog(existing: existing),
    );
    if (saved == true && mounted) {
      showAppSnackbar(
        context,
        S.tn(context, 'Bahan baku tersimpan di server.'),
        type: SnackType.success,
      );
      await _refresh();
    }
  }

  Future<void> _openRecipeEditor() async {
    final product = _selectedProduct;
    if (product == null) return;
    final productId = _asId(product['id']);
    if (productId == 0) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RecipeFormDialog(
        productId: productId,
        productName:
            product['name']?.toString() ?? 'Produk #$productId',
        materials: _materials,
        initial: _recipe,
      ),
    );
    if (saved == true && mounted && _selectedProduct != null) {
      showAppSnackbar(
        context,
        S.tn(context, 'Resep tersimpan di server.'),
        type: SnackType.success,
      );
      await _selectProduct(_selectedProduct!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Bahan Baku & Resep')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Muat ulang'),
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openMaterialDialog(),
        icon: const Icon(Icons.add),
        label: Text(S.t(context, 'Tambah Bahan')),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: S.t(context, 'Cari bahan baku...'),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                FilterChip(
                  label: Text(S.t(context, 'Stok menipis')),
                  selected: _lowOnly,
                  onSelected: (v) {
                    setState(() => _lowOnly = v);
                    _refresh();
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildMaterialBody(),
            const Divider(height: AppSpacing.xl),
            Text(
              S.t(context, 'Resep per produk'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontSize: 14,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _productSearchCtrl,
              decoration: InputDecoration(
                labelText: S.t(context, 'Cari produk untuk lihat resep'),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
              ),
              onChanged: _onProductSearchChanged,
            ),
            if (_searchingProduct)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              ..._foundProducts.map(
                (p) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    p['name']?.toString() ?? '-',
                    style: const TextStyle(fontSize: 13),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _selectProduct(p),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            _buildRecipeBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialBody() {
    if (_loading) {
      return Column(
        children: List.generate(
          3,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: SkeletonBox(width: double.infinity, height: 64),
          ),
        ),
      );
    }
    if (_error != null) return ErrorState(message: _error!, onRetry: _refresh);
    if (_materials.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_outlined,
        title: S.t(context, 'Tidak ada bahan baku'),
        message: S.t(context, 'Tambah bahan baku dengan tombol di bawah.'),
      );
    }
    return Column(
      children: _materials.map((m) {
        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primaryContainer,
              child: const Icon(Icons.inventory_outlined, size: 20),
            ),
            title: Text(
              m.name,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${_fmtNum(m.stock)} ${m.unit ?? ''} · min ${_fmtNum(m.minStock)}',
              style: const TextStyle(fontSize: 11.5),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (m.isLow)
                  StatusBadge(
                    S.t(context, 'Menipis'),
                    tone: BadgeTone.warning,
                  )
                else
                  Text(
                    Fmt.rupiah(m.costPerUnit),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                IconButton(
                  tooltip: S.t(context, 'Ubah'),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _openMaterialDialog(existing: m),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRecipeBody() {
    if (_selectedProduct == null) {
      return Text(
        S.t(context, 'Cari produk di atas untuk melihat resepnya.'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    if (_loadingRecipe) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_recipeError != null) {
      return ErrorState(
        message: _recipeError!,
        onRetry: () => _selectProduct(_selectedProduct!),
      );
    }
    final recipe = _recipe;
    final productName =
        _selectedProduct?['name']?.toString() ?? S.t(context, 'Produk');
    if (recipe == null || recipe.items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                productName,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                S.t(context, 'Belum ada resep untuk produk ini.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _openRecipeEditor,
                icon: const Icon(Icons.add, size: 18),
                label: Text(S.t(context, 'Buat Resep')),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    productName,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _openRecipeEditor,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text(S.t(context, 'Ubah')),
                ),
              ],
            ),
            ...recipe.items.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (e.rawMaterialName?.isNotEmpty ?? false)
                            ? e.rawMaterialName!
                            : 'Bahan #${e.rawMaterialId}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      '× ${_fmtNum(e.qty)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtNum(double v) =>
      v == v.toInt() ? v.toInt().toString() : v.toString();
}

/// Form tambah/ubah bahan baku (POST /raw-materials, PUT /raw-materials/{id}).
class _MaterialFormDialog extends StatefulWidget {
  final RawMaterial? existing;

  const _MaterialFormDialog({this.existing});

  @override
  State<_MaterialFormDialog> createState() => _MaterialFormDialogState();
}

class _MaterialFormDialogState extends State<_MaterialFormDialog> {
  final ApiService _api = ApiService();
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _unitCtrl = TextEditingController(
    text: widget.existing?.unit ?? '',
  );
  late final TextEditingController _stockCtrl = TextEditingController(
    text: widget.existing == null ? '' : _num(widget.existing!.stock),
  );
  late final TextEditingController _minCtrl = TextEditingController(
    text: widget.existing == null ? '' : _num(widget.existing!.minStock),
  );
  late final TextEditingController _costCtrl = TextEditingController(
    text: widget.existing == null ? '' : _num(widget.existing!.costPerUnit),
  );

  bool _submitting = false;
  String? _error;

  static String _num(double v) =>
      v == v.toInt() ? v.toInt().toString() : v.toString();

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _unitCtrl.dispose();
    _stockCtrl.dispose();
    _minCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = S.tn(context, 'Nama wajib diisi.'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        'name': name,
        if (_unitCtrl.text.trim().isNotEmpty) 'unit': _unitCtrl.text.trim(),
        'stock': double.tryParse(_stockCtrl.text.trim().replaceAll(',', '.')) ?? 0,
        'min_stock': double.tryParse(_minCtrl.text.trim().replaceAll(',', '.')) ?? 0,
        'cost_per_unit':
            double.tryParse(_costCtrl.text.trim().replaceAll(',', '.')) ?? 0,
      };
      if (_isEdit) {
        await _sendPut('/raw-materials/${widget.existing!.id}', body);
      } else {
        await _api.post('/raw-materials', body: body);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = S.tn(context, 'Gagal menyimpan bahan baku.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEdit ? S.t(context, 'Ubah Bahan Baku') : S.t(context, 'Tambah Bahan Baku'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(_error!, style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '${S.t(context, 'Nama')} *',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _unitCtrl,
                    decoration: InputDecoration(
                      labelText: S.t(context, 'Satuan (kg/liter/pcs)'),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _stockCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: S.t(context, 'Stok'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: S.t(context, 'Stok minimum'),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _costCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: S.t(context, 'Biaya per satuan (Rp)'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: Text(S.t(context, 'Batal')),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(S.t(context, 'Simpan')),
        ),
      ],
    );
  }
}

/// Editor resep: pilih bahan + qty per baris, POST /recipes.
class _RecipeFormDialog extends StatefulWidget {
  final int productId;
  final String productName;
  final List<RawMaterial> materials;
  final Recipe? initial;

  const _RecipeFormDialog({
    required this.productId,
    required this.productName,
    required this.materials,
    this.initial,
  });

  @override
  State<_RecipeFormDialog> createState() => _RecipeFormDialogState();
}

class _RecipeFormDialogState extends State<_RecipeFormDialog> {
  final ApiService _api = ApiService();
  late final List<RecipeItem> _rows = (widget.initial?.items ?? const [])
      .map((e) => RecipeItem(
            rawMaterialId: e.rawMaterialId,
            rawMaterialName: e.rawMaterialName,
            qty: e.qty,
          ))
      .toList();
  int? _pickedMaterialId;
  final _qtyCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  String _materialName(int id) {
    for (final m in widget.materials) {
      if (m.id == id) return m.name;
    }
    for (final r in _rows) {
      if (r.rawMaterialId == id && (r.rawMaterialName?.isNotEmpty ?? false)) {
        return r.rawMaterialName!;
      }
    }
    return 'Bahan #$id';
  }

  void _addRow() {
    final qty =
        double.tryParse(_qtyCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    if (_pickedMaterialId == null || qty <= 0) {
      setState(
        () => _error = S.tn(context, 'Pilih bahan dan isi qty lebih dari 0.'),
      );
      return;
    }
    setState(() {
      _error = null;
      final i = _rows.indexWhere((e) => e.rawMaterialId == _pickedMaterialId);
      final row = RecipeItem(rawMaterialId: _pickedMaterialId!, qty: qty);
      if (i >= 0) {
        _rows[i] = row;
      } else {
        _rows.add(row);
      }
      _qtyCtrl.clear();
    });
  }

  Future<void> _submit() async {
    if (_rows.isEmpty) {
      setState(() => _error = S.tn(context, 'Tambahkan minimal satu bahan.'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _api.post(
        '/recipes',
        body: {
          'product_id': widget.productId,
          'items': _rows.map((e) => e.toJson()).toList(),
        },
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = S.tn(context, 'Gagal menyimpan resep.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        '${S.t(context, 'Resep')}: ${widget.productName}',
        style: const TextStyle(fontSize: 15),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.errorSoft,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(_error!, style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (widget.materials.isEmpty)
                Text(
                  S.t(context, 'Daftar bahan kosong. Tambah bahan dulu lewat tombol Tambah Bahan.'),
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                DropdownButtonFormField<int>(
                  initialValue: _pickedMaterialId,
                  decoration: InputDecoration(
                    labelText: S.t(context, 'Bahan baku'),
                  ),
                  items: widget.materials
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.id,
                          child: Text(m.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _pickedMaterialId = v),
                ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: S.t(context, 'Qty per produk'),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    tooltip: S.t(context, 'Tambah bahan'),
                    onPressed: _addRow,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_rows.isEmpty)
                Text(
                  S.t(context, 'Belum ada bahan di resep ini.'),
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                ..._rows.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _materialName(e.rawMaterialId),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '× ${_fmtNum(e.qty)}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => setState(() => _rows.remove(e)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: Text(S.t(context, 'Batal')),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(S.t(context, 'Simpan')),
        ),
      ],
    );
  }

  static String _fmtNum(double v) =>
      v == v.toInt() ? v.toInt().toString() : v.toString();
}
