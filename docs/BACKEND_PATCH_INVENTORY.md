# Patch Backend Aditif — Modul Inventory (untuk repo `posretail-backend`)

> STATUS: sudah diimplementasikan di branch backend `mobile-parity-patch`
> (show opname/transfer, PUT bahan baku, GET+POST recipes; test hijau).
> Tinggal push, merge, deploy.
> Usulan aditif, JANGAN ubah enum/status yang sudah live.
> Kebenaran live yang diverifikasi dari kode backend (Okt 2026):
> - Opname: `pending` → `completed` via `POST /stock-opnames/{id}/approve`;
>   store wajib `items: [{product_id, actual_stock}]`; relasi `stockOpnameItems`
>   (`system_stock`, `actual_stock`, `difference`); field `notes`, `opname_number`.
> - Transfer: `draft` → `sent` via `POST /stock-transfers/{id}/send` →
>   `received` via `POST .../receive`; store wajib
>   `items: [{product_id, quantity}]`; relasi `stockTransferItems`; field `notes`.
> - Mutasi: `GET /stock-movements` filter `product_id`, `type=in|out`,
>   `outlet_id`; kolom `quantity` (bukan `qty_before/after/change`).
> - Bahan baku: `GET` filter `search`, `low_stock`; `POST` wajib
>   `{name, outlet_id}` + opsional `{code, unit_id, cost_per_unit,
>   current_stock, min_stock}`. TIDAK ada PUT.
> - Resep: TIDAK ada endpoint (`recipe_items` hanya dipakai internal).
> - TIDAK ada `GET` detail untuk opname maupun transfer.
>
> Flutter sudah disesuaikan 100% ke kontrak di atas. Di bawah ini snippet
> **aditif** (route + method baru, tanpa mengubah yang live) agar UI Flutter
> yang kini menangani 404 secara jujur bisa berfungsi penuh.

Semua method memakai trait `ShopApi` yang sudah ada
(`outletIds`, `denyGroup`, `envelope`, `perPage`) dan menulis
`stock_movements` untuk tiap perubahan stok, seperti controller live.

## 1. Route tambahan (`routes/api.php`, dalam grup `auth:api`)

```php
// Detail (read-only, belum ada di live)
Route::get('/stock-opnames/{stockOpname}', [StockOpnameController::class, 'show']);
Route::get('/stock-transfers/{stockTransfer}', [StockTransferController::class, 'show']);

// Update bahan baku (belum ada di live)
Route::put('/raw-materials/{rawMaterial}', [InventoryReadController::class, 'updateRawMaterial']);

// Resep per produk (belum ada endpoint sama sekali di live)
Route::get('/recipes', [RecipeController::class, 'show']);
Route::post('/recipes', [RecipeController::class, 'store']);
```

## 2. `StockOpnameController::show`

```php
public function show(Request $request, StockOpname $stockOpname): JsonResponse
{
    if ($deny = $this->denyGroup($request, 'inventori')) {
        return $deny;
    }
    if (! in_array((int) $stockOpname->outlet_id, $this->outletIds($request), true)) {
        return response()->json(['message' => 'Akses ditolak untuk outlet ini.'], 403);
    }

    return response()->json([
        'data' => $stockOpname->load(['outlet', 'user', 'stockOpnameItems.product']),
    ]);
}
```

## 3. `StockTransferController::show`

```php
public function show(Request $request, StockTransfer $stockTransfer): JsonResponse
{
    if ($deny = $this->denyGroup($request, 'inventori')) {
        return $deny;
    }
    $ids = $this->outletIds($request);
    if (! in_array((int) $stockTransfer->from_outlet_id, $ids, true)
        && ! in_array((int) $stockTransfer->to_outlet_id, $ids, true)) {
        return response()->json(['message' => 'Akses ditolak untuk outlet ini.'], 403);
    }

    return response()->json([
        'data' => $stockTransfer->load(['fromOutlet', 'toOutlet', 'user', 'stockTransferItems.product']),
    ]);
}
```

## 4. `InventoryReadController::updateRawMaterial`

```php
public function updateRawMaterial(Request $request, RawMaterial $rawMaterial): JsonResponse
{
    if ($deny = $this->denyGroup($request, 'inventori', 'edit')) {
        return $deny;
    }
    $data = $request->validate([
        'name' => 'sometimes|required|string|max:255',
        'code' => 'nullable|string|max:50',
        'outlet_id' => 'sometimes|required|integer|exists:outlets,id',
        'unit_id' => 'nullable|integer|exists:units,id',
        'cost_per_unit' => 'nullable|numeric|min:0',
        'current_stock' => 'nullable|numeric|min:0',
        'min_stock' => 'nullable|numeric|min:0',
        'active' => 'nullable|boolean',
    ]);

    $ids = $this->outletIds($request);
    $targetOutlet = (int) ($data['outlet_id'] ?? $rawMaterial->outlet_id);
    if (! in_array((int) $rawMaterial->outlet_id, $ids, true)
        || ! in_array($targetOutlet, $ids, true)) {
        return response()->json(['message' => 'Anda tidak memiliki akses ke outlet ini.'], 403);
    }

    $rawMaterial->update($data);

    return response()->json([
        'data' => $rawMaterial->fresh()->load(['outlet', 'unit']),
        'message' => 'Bahan baku berhasil diperbarui.',
    ]);
}
```

## 5. `RecipeController` baru (baca + simpan resep per produk)

Tabel `recipe_items` sudah ada (`product_id`, `raw_material_id`, `quantity`).
`store` mengganti resep produk secara atomik (hapus + insert ulang dalam
transaksi) tanpa menyentuh stok — jadi tidak perlu `stock_movements`.

```php
<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\V1\Concerns\ShopApi;
use App\Http\Controllers\Controller;
use App\Models\Product;
use App\Models\RecipeItem;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class RecipeController extends Controller
{
    use ShopApi;

    public function show(Request $request): JsonResponse
    {
        if ($deny = $this->denyGroup($request, 'inventori')) {
            return $deny;
        }
        $data = $request->validate([
            'product_id' => 'required|integer|exists:products,id',
        ]);

        $items = RecipeItem::with('rawMaterial')
            ->where('product_id', $data['product_id'])
            ->get();

        if ($items->isEmpty()) {
            return response()->json(['message' => 'Resep belum tersedia untuk produk ini.'], 404);
        }

        return response()->json([
            'data' => [
                'product_id' => (int) $data['product_id'],
                'items' => $items,
            ],
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        if ($deny = $this->denyGroup($request, 'inventori', 'create')) {
            return $deny;
        }
        $data = $request->validate([
            'product_id' => 'required|integer|exists:products,id',
            'items' => 'required|array|min:1|max:200',
            'items.*.raw_material_id' => 'required|integer|exists:raw_materials,id',
            'items.*.quantity' => 'required|numeric|min:0.0001|max:1000000',
        ]);

        $product = Product::findOrFail($data['product_id']);
        if (! in_array((int) $product->outlet_id, $this->outletIds($request), true)) {
            return response()->json(['message' => 'Anda tidak memiliki akses ke outlet ini.'], 403);
        }

        DB::transaction(function () use ($data) {
            RecipeItem::where('product_id', $data['product_id'])->delete();
            foreach ($data['items'] as $i) {
                RecipeItem::create([
                    'product_id' => $data['product_id'],
                    'raw_material_id' => $i['raw_material_id'],
                    'quantity' => $i['quantity'],
                ]);
            }
        });

        return response()->json([
            'data' => [
                'product_id' => (int) $data['product_id'],
                'items' => RecipeItem::with('rawMaterial')
                    ->where('product_id', $data['product_id'])->get(),
            ],
            'message' => 'Resep berhasil disimpan.',
        ], 201);
    }
}
```

## 6. Verifikasi setelah tempel

1. `php artisan route:list --path=v1 | grep -E "stock-opnames|stock-transfers|raw-materials|recipes"`.
2. `GET /api/v1/stock-opnames/1` dengan user outlet terbatas → 200 + `stockOpnameItems`.
3. `PUT /api/v1/raw-materials/1` dengan outlet lain → 403 `Anda tidak memiliki akses ke outlet ini.`
4. `GET /api/v1/recipes?product_id=X` tanpa resep → 404 (Flutter menampilkan penanda jujur + retry).
5. `POST /api/v1/recipes` lalu `GET` lagi → 200, item memuat `raw_material`.
