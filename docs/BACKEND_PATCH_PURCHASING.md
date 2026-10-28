# Backend Patch — Modul Purchasing (aditif, tanpa ubah kontrak live)

> STATUS: sudah diimplementasikan di branch backend `mobile-parity-patch`
> (route order/cancel, supplier update/destroy, migrasi cancel_reason;
> `php artisan test --filter=MobileParity` 17/17 hijau). Tinggal push,
> merge, migrasi, deploy.

Dokumen ini berisi snippet **aditif** untuk repo backend
(`posretail-backend`, TIDAK diterapkan oleh tim mobile).
Tujuan: menyediakan endpoint yang sudah dipakai UI Flutter namun belum ada
di server, mengikuti pola yang sudah ada (`ShopApi`: `outletIds`,
`denyGroup`, envelope, pesan Indonesia, transaksi DB).

Status yang dipakai tetap kosakata backend yang live (JANGAN diubah):
`draft`, `ordered`, `received`, `cancelled`.

## 1. Route (`routes/api.php`, di dalam grup `auth:api`)

```php
// Mobile parity: purchasing — transisi status PO (aditif)
Route::post('/purchase-orders/{purchaseOrder}/order', [\App\Http\Controllers\Api\V1\PurchaseOrderController::class, 'order']);
Route::post('/purchase-orders/{purchaseOrder}/cancel', [\App\Http\Controllers\Api\V1\PurchaseOrderController::class, 'cancel']);

// Mobile parity: supplier — ubah & hapus (aditif)
Route::put('/suppliers/{supplier}', [\App\Http\Controllers\Api\V1\SupplierController::class, 'update']);
Route::delete('/suppliers/{supplier}', [\App\Http\Controllers\Api\V1\SupplierController::class, 'destroy']);
```

## 2. `PurchaseOrderController::order` — draft → ordered

```php
/**
 * Pesan PO ke supplier: draft → ordered.
 * Idempoten: PO yang sudah ordered/received dikembalikan apa adanya.
 */
public function order(Request $request, PurchaseOrder $purchaseOrder): JsonResponse
{
    if ($deny = $this->denyGroup($request, 'pembelian', 'edit')) {
        return $deny;
    }
    if (! in_array((int) $purchaseOrder->outlet_id, $this->outletIds($request), true)) {
        return response()->json(['message' => 'Akses ditolak untuk outlet ini.'], 403);
    }
    if ($purchaseOrder->status === 'cancelled') {
        return response()->json(['message' => 'PO yang sudah dibatalkan tidak bisa dipesan.'], 422);
    }
    if (in_array($purchaseOrder->status, ['ordered', 'received'], true)) {
        return response()->json(['data' => $purchaseOrder, 'message' => 'PO sudah dipesan sebelumnya.']);
    }

    $purchaseOrder->update(['status' => 'ordered']);

    return response()->json(['data' => $purchaseOrder->fresh()]);
}
```

## 3. `PurchaseOrderController::cancel` — → cancelled

```php
/**
 * Batalkan PO. Hanya dari status draft/ordered; PO received/cancelled
 * ditolak dengan 422 dan pesan Indonesia.
 */
public function cancel(Request $request, PurchaseOrder $purchaseOrder): JsonResponse
{
    if ($deny = $this->denyGroup($request, 'pembelian', 'edit')) {
        return $deny;
    }
    if (! in_array((int) $purchaseOrder->outlet_id, $this->outletIds($request), true)) {
        return response()->json(['message' => 'Akses ditolak untuk outlet ini.'], 403);
    }
    if (in_array($purchaseOrder->status, ['received', 'cancelled'], true)) {
        return response()->json(['message' => 'PO yang sudah diterima atau dibatalkan tidak bisa dibatalkan.'], 422);
    }

    $validated = $request->validate([
        'reason' => 'nullable|string|max:1000',
    ]);

    DB::transaction(function () use ($purchaseOrder, $validated) {
        $purchaseOrder->update([
            'status' => 'cancelled',
            'cancel_reason' => $validated['reason'] ?? null,
        ]);
    });

    return response()->json(['data' => $purchaseOrder->fresh(), 'message' => 'Purchase order berhasil dibatalkan.']);
}
```

Butuh kolom `cancel_reason` (aditif, nullable) — migrasi baru, JANGAN ubah
migrasi lama yang sudah live:

```php
// database/migrations/xxxx_xx_xx_xxxxxx_add_cancel_reason_to_purchase_orders_table.php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('purchase_orders', function (Blueprint $table) {
            $table->text('cancel_reason')->nullable()->after('notes');
        });
    }

    public function down(): void
    {
        Schema::table('purchase_orders', function (Blueprint $table) {
            $table->dropColumn('cancel_reason');
        });
    }
};
```

Dan tambahkan `'cancel_reason'` ke `$fillable` model `PurchaseOrder`.

## 4. `SupplierController::update` + `destroy`

```php
public function update(Request $request, Supplier $supplier): JsonResponse
{
    if ($deny = $this->denyGroup($request, 'master-data', 'edit')) {
        return $deny;
    }
    $data = $request->validate([
        'name' => 'sometimes|required|string|max:255',
        'contact_person' => 'nullable|string|max:255',
        'phone' => 'nullable|string|max:50',
        'email' => 'nullable|email|max:255',
        'address' => 'nullable|string|max:1000',
    ]);

    $supplier->update($data);

    return response()->json(['data' => $supplier->fresh()]);
}

public function destroy(Request $request, Supplier $supplier): JsonResponse
{
    if ($deny = $this->denyGroup($request, 'master-data', 'delete')) {
        return $deny;
    }
    if ($supplier->purchaseOrders()->exists()) {
        return response()->json(['message' => 'Supplier yang masih memiliki purchase order tidak bisa dihapus.'], 409);
    }

    $supplier->delete();

    return response()->json(['message' => 'Supplier berhasil dihapus.']);
}
```

## 5. Checklist verifikasi setelah patch

- [ ] `POST /v1/purchase-orders/{id}/order`: draft → `ordered`; diulang → 200 + pesan "sudah dipesan".
- [ ] `POST /v1/purchase-orders/{id}/cancel`: draft/ordered → `cancelled`; dari received → 422.
- [ ] `POST /v1/purchase-orders/{id}/receive` tetap satu-satunya yang memposting jurnal (tidak berubah).
- [ ] `PUT /v1/suppliers/{id}` + `DELETE /v1/suppliers/{id}`; hapus supplier ber-PO → 409.
- [ ] Flutter tidak perlu diubah lagi: path, field (`quantity`/`unit_price`/`notes`),
      dan status (`draft`/`ordered`/`received`/`cancelled`) sudah sesuai dokumen ini.
