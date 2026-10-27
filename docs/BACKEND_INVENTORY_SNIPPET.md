# Snippet Backend Laravel — Inventori (Opname, Transfer, Bahan Baku & Resep)

Tempel ke proyek Laravel `posretail` (route `api/v1`, middleware
`auth:sanctum` + scope outlet sama seperti endpoint lama).
Status string persis Flutter: opname `draft|counted|approved|cancelled`,
transfer `draft|dikirim|diterima|cancelled`.

## 1. Migrations

```php
// database/migrations/2026_10_27_000001_create_stock_opnames_table.php
Schema::create('stock_opnames', function (Blueprint $table) {
    $table->id();
    $table->foreignId('outlet_id')->constrained()->cascadeOnDelete();
    $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
    $table->string('status')->default('draft'); // draft|counted|approved|cancelled
    $table->text('note')->nullable();
    $table->timestamps();
    $table->index(['outlet_id', 'status']);
});

Schema::create('stock_opname_items', function (Blueprint $table) {
    $table->id();
    $table->foreignId('stock_opname_id')->constrained()->cascadeOnDelete();
    $table->foreignId('product_id')->constrained()->cascadeOnDelete();
    $table->decimal('system_qty', 14, 3)->default(0);
    $table->decimal('physical_qty', 14, 3)->default(0);
    $table->decimal('diff', 14, 3)->default(0); // physical - system
    $table->timestamps();
    $table->unique(['stock_opname_id', 'product_id']);
});
```

```php
// database/migrations/2026_10_27_000002_create_stock_transfers_table.php
Schema::create('stock_transfers', function (Blueprint $table) {
    $table->id();
    $table->foreignId('from_outlet_id')->constrained('outlets')->cascadeOnDelete();
    $table->foreignId('to_outlet_id')->constrained('outlets')->cascadeOnDelete();
    $table->string('status')->default('draft'); // draft|dikirim|diterima|cancelled
    $table->text('note')->nullable();
    $table->timestamps();
    $table->index(['from_outlet_id', 'status']);
    $table->index(['to_outlet_id', 'status']);
});

Schema::create('stock_transfer_items', function (Blueprint $table) {
    $table->id();
    $table->foreignId('stock_transfer_id')->constrained()->cascadeOnDelete();
    $table->foreignId('product_id')->constrained()->cascadeOnDelete();
    $table->integer('qty');
    $table->timestamps();
    $table->unique(['stock_transfer_id', 'product_id']);
});
```

```php
// database/migrations/2026_10_27_000003_create_raw_materials_table.php
Schema::create('raw_materials', function (Blueprint $table) {
    $table->id();
    $table->string('name');
    $table->string('unit')->nullable(); // kg|liter|pcs
    $table->decimal('stock', 14, 3)->default(0);
    $table->decimal('min_stock', 14, 3)->default(0);
    $table->decimal('cost_per_unit', 14, 2)->default(0);
    $table->timestamps();
    $table->index('name');
});

Schema::create('recipes', function (Blueprint $table) {
    $table->id();
    $table->foreignId('product_id')->constrained()->cascadeOnDelete();
    $table->timestamps();
    $table->unique('product_id');
});

Schema::create('recipe_items', function (Blueprint $table) {
    $table->id();
    $table->foreignId('recipe_id')->constrained()->cascadeOnDelete();
    $table->foreignId('raw_material_id')->constrained()->cascadeOnDelete();
    $table->decimal('qty', 14, 3); // qty bahan per 1 produk
    $table->timestamps();
    $table->unique(['recipe_id', 'raw_material_id']);
});
```

Stok produk per outlet diasumsikan di tabel `outlet_product_stock`
(`outlet_id`, `product_id`, `qty`) — sesuaikan dengan tabel yang sudah ada.
`stock_movements` mengikuti kontrak grup 5:
(`product_id`, `outlet_id`, `type`, `qty_before`, `qty_after`,
`qty_change`, `reference_type`, `reference_id`).

## 2. Routes (`routes/api.php`, grup `v1`)

```php
Route::prefix('v1')->middleware(['auth:sanctum'])->group(function () {
    Route::get('stock-opnames', [StockOpnameController::class, 'index']);
    Route::post('stock-opnames', [StockOpnameController::class, 'store']);
    Route::get('stock-opnames/{id}', [StockOpnameController::class, 'show']);
    Route::post('stock-opnames/{id}/items', [StockOpnameController::class, 'storeItems']);
    Route::post('stock-opnames/{id}/approve', [StockOpnameController::class, 'approve']);

    Route::get('stock-transfers', [StockTransferController::class, 'index']);
    Route::post('stock-transfers', [StockTransferController::class, 'store']);
    Route::get('stock-transfers/{id}', [StockTransferController::class, 'show']);
    Route::post('stock-transfers/{id}/ship', [StockTransferController::class, 'ship']);
    Route::post('stock-transfers/{id}/receive', [StockTransferController::class, 'receive']);

    Route::get('raw-materials', [RawMaterialController::class, 'index']);
    Route::post('raw-materials', [RawMaterialController::class, 'store']);
    Route::put('raw-materials/{id}', [RawMaterialController::class, 'update']);
    Route::get('recipes', [RecipeController::class, 'show']);
    Route::post('recipes', [RecipeController::class, 'store']);
});
```

## 3. StockOpnameController

```php
class StockOpnameController extends Controller
{
    public function index(Request $r)
    {
        $q = StockOpname::with('items.product:id,name')
            ->where('outlet_id', $r->query('outlet_id'))
            ->when($r->query('status'), fn ($qq, $s) => $qq->where('status', $s))
            ->latest()->paginate($r->query('per_page', 50));
        return response()->json([
            'data' => StockOpnameResource::collection($q->items()),
            'meta' => ['total' => $q->total(), 'last_page' => $q->lastPage()],
        ]);
    }

    public function store(Request $r)
    {
        $v = $r->validate(['outlet_id' => 'required|exists:outlets,id', 'note' => 'nullable|string']);
        $this->authorizeOutlet($v['outlet_id']);
        $opname = StockOpname::create($v + ['created_by' => $r->user()->id, 'status' => 'draft']);
        return response()->json(['data' => new StockOpnameResource($opname)], 201);
    }

    public function show($id)
    {
        $opname = StockOpname::with('items.product:id,name')->findOrFail($id);
        $this->authorizeOutlet($opname->outlet_id);
        return response()->json(['data' => new StockOpnameResource($opname)]);
    }

    public function storeItems(Request $r, $id)
    {
        $opname = StockOpname::findOrFail($id);
        $this->authorizeOutlet($opname->outlet_id);
        abort_if(! in_array($opname->status, ['draft', 'counted']), 422, 'Sesi sudah final.');
        $v = $r->validate(['items' => 'required|array|min:1', 'items.*.product_id' => 'required|exists:products,id', 'items.*.physical_qty' => 'required|numeric|min:0']);
        DB::transaction(function () use ($opname, $v) {
            foreach ($v['items'] as $row) {
                $system = OutletProductStock::where('outlet_id', $opname->outlet_id)->where('product_id', $row['product_id'])->value('qty') ?? 0;
                StockOpnameItem::updateOrCreate(
                    ['stock_opname_id' => $opname->id, 'product_id' => $row['product_id']],
                    ['system_qty' => $system, 'physical_qty' => $row['physical_qty'], 'diff' => $row['physical_qty'] - $system],
                );
            }
            if ($opname->status === 'draft') $opname->update(['status' => 'counted']);
        });
        return response()->json(['data' => new StockOpnameResource($opname->fresh('items.product:id,name'))]);
    }

    public function approve(Request $r, $id)
    {
        $opname = StockOpname::with('items')->findOrFail($id);
        $this->authorizeOutlet($opname->outlet_id);
        abort_if(! in_array($opname->status, ['draft', 'counted']), 422, 'Sesi sudah final.');
        DB::transaction(function () use ($opname) {
            foreach ($opname->items as $item) {
                $stock = OutletProductStock::firstOrCreate(
                    ['outlet_id' => $opname->outlet_id, 'product_id' => $item->product_id],
                    ['qty' => 0],
                );
                $before = (float) $stock->qty;
                $after = (float) $item->physical_qty;
                $stock->update(['qty' => $after]);
                StockMovement::create([
                    'product_id' => $item->product_id, 'outlet_id' => $opname->outlet_id,
                    'type' => 'opname', 'qty_before' => $before, 'qty_after' => $after,
                    'qty_change' => $after - $before,
                    'reference_type' => 'stock_opname', 'reference_id' => $opname->id,
                ]);
            }
            $opname->update(['status' => 'approved']);
        });
        return response()->json(['data' => new StockOpnameResource($opname->fresh('items.product:id,name'))]);
    }
}
```

## 4. StockTransferController

```php
class StockTransferController extends Controller
{
    public function index(Request $r)
    {
        $q = StockTransfer::with(['items.product:id,name', 'fromOutlet:id,name', 'toOutlet:id,name'])
            ->where(fn ($qq) => $qq->where('from_outlet_id', $r->query('outlet_id'))->orWhere('to_outlet_id', $r->query('outlet_id')))
            ->when($r->query('status'), fn ($qq, $s) => $qq->where('status', $s))
            ->latest()->paginate($r->query('per_page', 50));
        return response()->json([
            'data' => StockTransferResource::collection($q->items()),
            'meta' => ['total' => $q->total(), 'last_page' => $q->lastPage()],
        ]);
    }

    public function store(Request $r)
    {
        $v = $r->validate([
            'from_outlet_id' => 'required|exists:outlets,id|different:to_outlet_id',
            'to_outlet_id' => 'required|exists:outlets,id',
            'items' => 'required|array|min:1',
            'items.*.product_id' => 'required|exists:products,id',
            'items.*.qty' => 'required|integer|min:1',
            'note' => 'nullable|string',
        ]);
        $this->authorizeOutlet($v['from_outlet_id']);
        $t = DB::transaction(function () use ($v) {
            $t = StockTransfer::create($v + ['status' => 'draft']);
            foreach ($v['items'] as $row) $t->items()->create($row);
            return $t;
        });
        return response()->json(['data' => new StockTransferResource($t->load('items.product:id,name'))], 201);
    }

    public function show($id)
    {
        $t = StockTransfer::with(['items.product:id,name', 'fromOutlet:id,name', 'toOutlet:id,name'])->findOrFail($id);
        return response()->json(['data' => new StockTransferResource($t)]);
    }

    public function ship(Request $r, $id)
    {
        $t = StockTransfer::with('items')->findOrFail($id);
        $this->authorizeOutlet($t->from_outlet_id);
        abort_if($t->status !== 'draft', 422, 'Hanya draft yang bisa dikirim.');
        DB::transaction(function () use ($t) {
            foreach ($t->items as $item) {
                $stock = OutletProductStock::firstOrCreate(
                    ['outlet_id' => $t->from_outlet_id, 'product_id' => $item->product_id], ['qty' => 0]);
                abort_if($stock->qty < $item->qty, 422, 'Stok outlet asal tidak cukup.');
                $before = (float) $stock->qty;
                $stock->decrement('qty', $item->qty);
                StockMovement::create([
                    'product_id' => $item->product_id, 'outlet_id' => $t->from_outlet_id,
                    'type' => 'transfer_out', 'qty_before' => $before, 'qty_after' => $before - $item->qty,
                    'qty_change' => -$item->qty, 'reference_type' => 'stock_transfer', 'reference_id' => $t->id,
                ]);
            }
            $t->update(['status' => 'dikirim']);
        });
        return response()->json(['data' => new StockTransferResource($t->fresh('items.product:id,name'))]);
    }

    public function receive(Request $r, $id)
    {
        $t = StockTransfer::with('items')->findOrFail($id);
        $this->authorizeOutlet($t->to_outlet_id);
        abort_if($t->status !== 'dikirim', 422, 'Hanya yang dikirim yang bisa diterima.');
        DB::transaction(function () use ($t) {
            foreach ($t->items as $item) {
                $stock = OutletProductStock::firstOrCreate(
                    ['outlet_id' => $t->to_outlet_id, 'product_id' => $item->product_id], ['qty' => 0]);
                $before = (float) $stock->qty;
                $stock->increment('qty', $item->qty);
                StockMovement::create([
                    'product_id' => $item->product_id, 'outlet_id' => $t->to_outlet_id,
                    'type' => 'transfer_in', 'qty_before' => $before, 'qty_after' => $before + $item->qty,
                    'qty_change' => $item->qty, 'reference_type' => 'stock_transfer', 'reference_id' => $t->id,
                ]);
            }
            $t->update(['status' => 'diterima']);
        });
        return response()->json(['data' => new StockTransferResource($t->fresh('items.product:id,name'))]);
    }
}
```

## 5. RawMaterialController + RecipeController

```php
class RawMaterialController extends Controller
{
    public function index(Request $r)
    {
        $q = RawMaterial::query()
            ->when($r->query('search'), fn ($qq, $s) => $qq->where('name', 'like', "%$s%"))
            ->when($r->boolean('low_stock'), fn ($qq) => $qq->whereColumn('stock', '<=', 'min_stock'))
            ->orderBy('name')->get();
        return response()->json(['data' => $q]);
    }

    public function store(Request $r)
    {
        $v = $r->validate(['name' => 'required|string|max:255', 'unit' => 'nullable|string|max:32', 'stock' => 'numeric|min:0', 'min_stock' => 'numeric|min:0', 'cost_per_unit' => 'numeric|min:0']);
        return response()->json(['data' => RawMaterial::create($v)], 201);
    }

    public function update(Request $r, $id)
    {
        $m = RawMaterial::findOrFail($id);
        $m->update($r->validate(['name' => 'sometimes|string|max:255', 'unit' => 'nullable|string|max:32', 'stock' => 'sometimes|numeric|min:0', 'min_stock' => 'sometimes|numeric|min:0', 'cost_per_unit' => 'sometimes|numeric|min:0']));
        return response()->json(['data' => $m->fresh()]);
    }
}

class RecipeController extends Controller
{
    public function show(Request $r)
    {
        $r->validate(['product_id' => 'required|exists:products,id']);
        $recipe = Recipe::with('items.rawMaterial:id,name')->where('product_id', $r->query('product_id'))->first();
        abort_if(! $recipe, 404, 'Resep belum ada untuk produk ini.');
        return response()->json(['data' => new RecipeResource($recipe)]);
    }

    public function store(Request $r)
    {
        $v = $r->validate([
            'product_id' => 'required|exists:products,id',
            'items' => 'required|array|min:1',
            'items.*.raw_material_id' => 'required|exists:raw_materials,id',
            'items.*.qty' => 'required|numeric|min:0.001',
        ]);
        $recipe = DB::transaction(function () use ($v) {
            $recipe = Recipe::updateOrCreate(['product_id' => $v['product_id']], []);
            $recipe->items()->delete();
            foreach ($v['items'] as $row) $recipe->items()->create($row);
            return $recipe;
        });
        return response()->json(['data' => new RecipeResource($recipe->load('items.rawMaterial:id,name'))]);
    }
}
```

## 6. Contoh resource JSON (bentuk yang dibaca Flutter)

`StockOpnameResource`: `{id, outlet_id, status, note, created_at,
items: [{product_id, product_name, system_qty, physical_qty, diff}]}`.
`StockTransferResource`: `{id, from_outlet_id, to_outlet_id, from_name,
to_name, status, note, created_at, items: [{product_id, product_name, qty}]}`.
`RecipeResource`: `{product_id, product_name,
items: [{raw_material_id, raw_material_name, qty}]}`.
```

