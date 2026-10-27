# Snippet Backend Laravel — Fase Purchasing (Supplier + PO + Mutasi)

Tempel ke backend Laravel yang sudah memakai **Sanctum** dengan prefix
`api/v1` + middleware `auth:sanctum`. Mengikuti persis kontrak
`docs/API_CONTRACT_MOBILE_PARITY.md` grup **1 (Supplier)**,
**2 (Purchase Order)**, **5 (Mutasi Stok)**.

Aturan yang dipatuhi snippet ini:

- Validasi gagal → `422 {message, errors}` (otomatis dari
  `$request->validate()` untuk request JSON).
- `outlet_id` selalu di-scope **server-side** (cek pivot `outlet_user`;
  bukan cuma percaya kiriman client). Tanpa akses → `403`.
- Status PO persis string web:
  `draft|dipesan|dikirim|diterima|cancelled`.
- Setiap perubahan qty menulis `stock_movements` (audit trail).
- Pagination `?page=&per_page=` (default `per_page=50`), envelope
  `{data, meta: {total, last_page}}`.

## Asumsi tabel yang sudah ada

- `users`, `outlets`, pivot `outlet_user(outlet_id, user_id)`.
- `products(id, ...)`.
- Stok per outlet di `product_stocks(product_id, outlet_id, stock)`.
  Jika belum ada, buat dulu migration prasyarat di bawah (lewati jika
  struktur stok outlet-mu berbeda — sesuaikan method `adjustStock`).

```php
// database/migrations/xxxx_create_product_stocks_table.php (PRASYARAT — lewati jika sudah ada)
Schema::create('product_stocks', function (Blueprint $table) {
    $table->id();
    $table->foreignId('product_id')->constrained()->cascadeOnDelete();
    $table->foreignId('outlet_id')->constrained()->cascadeOnDelete();
    $table->decimal('stock', 14, 2)->default(0);
    $table->timestamps();
    $table->unique(['product_id', 'outlet_id']);
});
```

## 1. Migration

```php
// database/migrations/2026_10_27_000001_create_suppliers_table.php
Schema::create('suppliers', function (Blueprint $table) {
    $table->id();
    $table->string('name');
    $table->string('phone')->nullable();
    $table->string('email')->nullable();
    $table->text('address')->nullable();
    $table->timestamps();
});

// database/migrations/2026_10_27_000002_create_purchase_orders_tables.php
Schema::create('purchase_orders', function (Blueprint $table) {
    $table->id();
    $table->foreignId('supplier_id')->constrained()->restrictOnDelete();
    $table->foreignId('outlet_id')->constrained()->restrictOnDelete();
    $table->string('status')->default('draft'); // draft|dipesan|dikirim|diterima|cancelled
    $table->decimal('total_cost', 15, 2)->default(0);
    $table->text('note')->nullable();
    $table->string('cancel_reason')->nullable();
    $table->timestamps();
    $table->index(['outlet_id', 'status']);
});

Schema::create('purchase_order_items', function (Blueprint $table) {
    $table->id();
    $table->foreignId('purchase_order_id')->constrained()->cascadeOnDelete();
    $table->foreignId('product_id')->constrained()->restrictOnDelete();
    $table->decimal('qty', 14, 2);
    $table->decimal('cost_price', 15, 2);
    $table->decimal('subtotal', 15, 2);
    $table->timestamps();
});

// database/migrations/2026_10_27_000003_create_stock_movements_table.php
Schema::create('stock_movements', function (Blueprint $table) {
    $table->id();
    $table->foreignId('product_id')->constrained()->restrictOnDelete();
    $table->foreignId('outlet_id')->constrained()->restrictOnDelete();
    $table->string('type'); // sale|purchase|transfer_in|transfer_out|opname|adjustment
    $table->decimal('qty_before', 14, 2)->default(0);
    $table->decimal('qty_after', 14, 2)->default(0);
    $table->decimal('qty_change', 14, 2)->default(0);
    $table->string('reference_type')->nullable();
    $table->string('reference_id')->nullable();
    $table->timestamps();
    $table->index(['outlet_id', 'type']);
    $table->index(['product_id']);
});
```

## 2. Models + relasi

```php
// app/Models/Supplier.php
class Supplier extends Model
{
    protected $fillable = ['name', 'phone', 'email', 'address'];

    public function purchaseOrders(): HasMany
    {
        return $this->hasMany(PurchaseOrder::class);
    }
}

// app/Models/PurchaseOrder.php
class PurchaseOrder extends Model
{
    protected $fillable = [
        'supplier_id', 'outlet_id', 'status',
        'total_cost', 'note', 'cancel_reason',
    ];

    public const STATUSES = ['draft', 'dipesan', 'dikirim', 'diterima', 'cancelled'];

    public function supplier(): BelongsTo
    {
        return $this->belongsTo(Supplier::class);
    }

    public function outlet(): BelongsTo
    {
        return $this->belongsTo(Outlet::class);
    }

    public function items(): HasMany
    {
        return $this->hasMany(PurchaseOrderItem::class);
    }
}

// app/Models/PurchaseOrderItem.php
class PurchaseOrderItem extends Model
{
    protected $fillable = [
        'purchase_order_id', 'product_id', 'qty', 'cost_price', 'subtotal',
    ];

    public function order(): BelongsTo
    {
        return $this->belongsTo(PurchaseOrder::class, 'purchase_order_id');
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }
}

// app/Models/StockMovement.php
class StockMovement extends Model
{
    protected $fillable = [
        'product_id', 'outlet_id', 'type',
        'qty_before', 'qty_after', 'qty_change',
        'reference_type', 'reference_id',
    ];

    public const TYPES = [
        'sale', 'purchase', 'transfer_in',
        'transfer_out', 'opname', 'adjustment',
    ];
}

// app/Models/User.php — tambahkan relasi outlet (jika belum ada)
public function outlets(): BelongsToMany
{
    return $this->belongsToMany(Outlet::class, 'outlet_user');
}
```

## 3. Concern outlet scoping (dipakai semua controller transaksional)

```php
// app/Http/Controllers/Api/V1/Concerns/ScopesOutlet.php
namespace App\Http\Controllers\Api\V1\Concerns;

trait ScopesOutlet
{
    protected function hasOutletAccess($user, int $outletId): bool
    {
        if (in_array($user->role ?? null, ['owner', 'admin'], true)) {
            return true;
        }
        return $user->outlets()->where('outlets.id', $outletId)->exists();
    }

    protected function requireOutlet($request, ?int $outletId)
    {
        if (!$outletId) {
            abort(response()->json(['message' => 'outlet_id wajib diisi.'], 422));
        }
        if (!$this->hasOutletAccess($request->user(), $outletId)) {
            abort(response()->json(['message' => 'Anda tidak memiliki akses ke outlet ini.'], 403));
        }
        return $outletId;
    }
}
```

## 4. Controllers

```php
// app/Http/Controllers/Api/V1/SupplierController.php
namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Supplier;
use Illuminate\Http\Request;

class SupplierController extends Controller
{
    public function index(Request $request)
    {
        $perPage = min((int) $request->input('per_page', 50), 100);
        $q = Supplier::query()->withCount('purchaseOrders as po_count')->latest();
        if ($search = $request->input('search')) {
            $q->where(fn ($w) => $w->where('name', 'like', "%{$search}%")
                ->orWhere('phone', 'like', "%{$search}%")
                ->orWhere('email', 'like', "%{$search}%"));
        }
        $page = $q->paginate($perPage);
        return response()->json([
            'data' => $page->items(),
            'meta' => ['total' => $page->total(), 'last_page' => $page->lastPage()],
        ]);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'phone' => 'nullable|string|max:50',
            'email' => 'nullable|email|max:255',
            'address' => 'nullable|string',
        ]);
        return response()->json(
            ['data' => Supplier::create($validated)], 201
        );
    }

    public function show(Supplier $supplier)
    {
        return response()->json(
            ['data' => $supplier->loadCount('purchaseOrders as po_count')]
        );
    }

    public function update(Request $request, Supplier $supplier)
    {
        $validated = $request->validate([
            'name' => 'sometimes|required|string|max:255',
            'phone' => 'nullable|string|max:50',
            'email' => 'nullable|email|max:255',
            'address' => 'nullable|string',
        ]);
        $supplier->update($validated);
        return response()->json(['data' => $supplier]);
    }

    public function destroy(Supplier $supplier)
    {
        if ($supplier->purchaseOrders()->exists()) {
            return response()->json(
                ['message' => 'Supplier masih memiliki purchase order.'], 409
            );
        }
        $supplier->delete();
        return response()->json(['message' => 'Supplier dihapus.']);
    }
}
```

```php
// app/Http/Controllers/Api/V1/PurchaseOrderController.php
namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Controllers\Api\V1\Concerns\ScopesOutlet;
use App\Models\ProductStock;
use App\Models\PurchaseOrder;
use App\Models\StockMovement;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PurchaseOrderController extends Controller
{
    use ScopesOutlet;

    public function index(Request $request)
    {
        $outletId = $this->requireOutlet($request, (int) $request->input('outlet_id'));
        $perPage = min((int) $request->input('per_page', 50), 100);
        $q = PurchaseOrder::query()->where('outlet_id', $outletId)
            ->with(['supplier:id,name', 'items'])
            ->latest();
        if ($request->filled('status')) {
            $request->validate(['status' => 'in:draft,dipesan,dikirim,diterima,cancelled']);
            $q->where('status', $request->input('status'));
        }
        if ($request->filled('supplier_id')) {
            $q->where('supplier_id', $request->input('supplier_id'));
        }
        $page = $q->paginate($perPage);
        return response()->json([
            'data' => $page->items(),
            'meta' => ['total' => $page->total(), 'last_page' => $page->lastPage()],
        ]);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'supplier_id' => 'required|exists:suppliers,id',
            'outlet_id' => 'required|exists:outlets,id',
            'items' => 'required|array|min:1',
            'items.*.product_id' => 'required|exists:products,id',
            'items.*.qty' => 'required|numeric|min:0.01',
            'items.*.cost_price' => 'required|numeric|min:0',
            'note' => 'nullable|string',
        ]);
        $this->requireOutlet($request, (int) $validated['outlet_id']);

        return DB::transaction(function () use ($validated) {
            $order = PurchaseOrder::create([
                'supplier_id' => $validated['supplier_id'],
                'outlet_id' => $validated['outlet_id'],
                'status' => 'draft',
                'note' => $validated['note'] ?? null,
                'total_cost' => 0,
            ]);
            $total = 0;
            foreach ($validated['items'] as $row) {
                $subtotal = $row['qty'] * $row['cost_price'];
                $order->items()->create([
                    'product_id' => $row['product_id'],
                    'qty' => $row['qty'],
                    'cost_price' => $row['cost_price'],
                    'subtotal' => $subtotal,
                ]);
                $total += $subtotal;
            }
            $order->update(['total_cost' => $total]);
            return response()->json(
                ['data' => $order->load(['supplier', 'items'])], 201
            );
        });
    }

    public function show(Request $request, PurchaseOrder $purchaseOrder)
    {
        $this->requireOutlet($request, $purchaseOrder->outlet_id);
        return response()->json(
            ['data' => $purchaseOrder->load(['supplier', 'items.product'])]
        );
    }

    public function ship(Request $request, PurchaseOrder $purchaseOrder)
    {
        $this->requireOutlet($request, $purchaseOrder->outlet_id);
        if ($purchaseOrder->status !== 'dipesan') {
            return response()->json(
                ['message' => 'Hanya PO berstatus dipesan yang bisa dikirim.'], 409
            );
        }
        $purchaseOrder->update(['status' => 'dikirim']);
        return response()->json(['data' => $purchaseOrder]);
    }

    public function receive(Request $request, PurchaseOrder $purchaseOrder)
    {
        $this->requireOutlet($request, $purchaseOrder->outlet_id);
        if ($purchaseOrder->status !== 'dikirim') {
            return response()->json(
                ['message' => 'Hanya PO berstatus dikirim yang bisa diterima.'], 409
            );
        }

        DB::transaction(function () use ($purchaseOrder) {
            $purchaseOrder->loadMissing('items');
            foreach ($purchaseOrder->items as $item) {
                $stock = ProductStock::firstOrCreate(
                    ['product_id' => $item->product_id, 'outlet_id' => $purchaseOrder->outlet_id],
                    ['stock' => 0]
                );
                $before = (float) $stock->stock;
                $after = $before + (float) $item->qty;
                $stock->update(['stock' => $after]);
                StockMovement::create([
                    'product_id' => $item->product_id,
                    'outlet_id' => $purchaseOrder->outlet_id,
                    'type' => 'purchase',
                    'qty_before' => $before,
                    'qty_after' => $after,
                    'qty_change' => (float) $item->qty,
                    'reference_type' => 'purchase_order',
                    'reference_id' => (string) $purchaseOrder->id,
                ]);
            }
            $purchaseOrder->update(['status' => 'diterima']);
        });

        return response()->json(
            ['data' => $purchaseOrder->load(['supplier', 'items'])]
        );
    }

    public function cancel(Request $request, PurchaseOrder $purchaseOrder)
    {
        $this->requireOutlet($request, $purchaseOrder->outlet_id);
        if (in_array($purchaseOrder->status, ['diterima', 'cancelled'], true)) {
            return response()->json(
                ['message' => 'PO yang sudah diterima tidak bisa dibatalkan.'], 409
            );
        }
        $validated = $request->validate(['reason' => 'nullable|string|max:255']);
        $purchaseOrder->update([
            'status' => 'cancelled',
            'cancel_reason' => $validated['reason'] ?? null,
        ]);
        return response()->json(['data' => $purchaseOrder]);
    }
}
```

> Catatan alur status: `store` membuat `draft`; transisi
> `draft → dipesan` mengikuti aksi web yang sudah ada.
> `ship` = `dipesan → dikirim`,
> `receive` = `dikirim → diterima` (+ tambah stok + tulis mutasi).

```php
// app/Http/Controllers/Api/V1/StockMovementController.php (READ-ONLY)
namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Controllers\Api\V1\Concerns\ScopesOutlet;
use App\Models\StockMovement;
use Illuminate\Http\Request;

class StockMovementController extends Controller
{
    use ScopesOutlet;

    public function index(Request $request)
    {
        $outletId = $this->requireOutlet($request, (int) $request->input('outlet_id'));
        $request->validate([
            'type' => 'nullable|in:sale,purchase,transfer_in,transfer_out,opname,adjustment',
            'start_date' => 'nullable|date_format:Y-m-d',
            'end_date' => 'nullable|date_format:Y-m-d,after_or_equal:start_date',
        ]);
        $perPage = min((int) $request->input('per_page', 50), 100);
        $q = StockMovement::query()->where('outlet_id', $outletId)->latest();
        if ($request->filled('product_id')) {
            $q->where('product_id', $request->input('product_id'));
        }
        if ($request->filled('type')) {
            $q->where('type', $request->input('type'));
        }
        if ($request->filled('start_date')) {
            $q->whereDate('created_at', '>=', $request->input('start_date'));
        }
        if ($request->filled('end_date')) {
            $q->whereDate('created_at', '<=', $request->input('end_date'));
        }
        $page = $q->paginate($perPage);
        return response()->json([
            'data' => $page->items(),
            'meta' => ['total' => $page->total(), 'last_page' => $page->lastPage()],
        ]);
    }
}
```

## 5. Routes

```php
// routes/api.php
use App\Http\Controllers\Api\V1\PurchaseOrderController;
use App\Http\Controllers\Api\V1\StockMovementController;
use App\Http\Controllers\Api\V1\SupplierController;

Route::prefix('v1')->middleware('auth:sanctum')->group(function () {
    Route::apiResource('suppliers', SupplierController::class);
    Route::get('purchase-orders', [PurchaseOrderController::class, 'index']);
    Route::post('purchase-orders', [PurchaseOrderController::class, 'store']);
    Route::get('purchase-orders/{purchaseOrder}', [PurchaseOrderController::class, 'show']);
    Route::post('purchase-orders/{purchaseOrder}/ship', [PurchaseOrderController::class, 'ship']);
    Route::post('purchase-orders/{purchaseOrder}/receive', [PurchaseOrderController::class, 'receive']);
    Route::post('purchase-orders/{purchaseOrder}/cancel', [PurchaseOrderController::class, 'cancel']);
    Route::get('stock-movements', [StockMovementController::class, 'index']); // read-only
});
```

## 6. Verifikasi

- [ ] Tanpa token → `401`; token valid tapi beda outlet → `403`.
- [ ] `POST /v1/purchase-orders/{id}/receive` menambah stok dan menulis
      1 baris `stock_movements` per item (`type=purchase`).
- [ ] `GET /v1/stock-movements` hanya membaca; filter `type`,
      `start_date`, `end_date` sesuai kontrak; Flutter
      `StockMovementScreen` langsung bisa pakai tanpa perubahan.
```
