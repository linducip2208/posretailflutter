# Patch Backend Aditif — Modul Sales (Retur, Hold, Cicilan)

> STATUS: sudah diimplementasikan di branch backend `mobile-parity-patch`
> (GET retur detail + POST reject status 'rejected'; test hijau).
> Tinggal push, merge, deploy.
> Backend produksi (`posretail-backend`) adalah live — file ini HANYA berisi
> usulan **aditif** (route + method baru, gaya `ShopApi`, pesan Indonesia).
> Tidak ada perubahan enum/status/kolom yang sudah berjalan.
> Tempel manual oleh pemilik backend; Flutter sudah siap memakai endpoint
> ini dan menampilkan 404 jujur + retry selama belum tersedia.

Kebenaran backend yang sudah diverifikasi (JANGAN diubah):

| Area | Fakta backend |
|---|---|
| Retur | `GET /returns` (filter `status`, `outlet_id`), `POST /returns` (`order_id`, `reason`, `notes?`, `items[].{product_id, quantity, unit_price?}`), `POST /returns/{retur}/approve` → status `completed`. Status pact: `pending` → `completed`. |
| Hold | `GET|POST /held-carts` (`{outlet_id, customer_id?, label?, items[]}`), `POST /held-carts/{heldCart}/resume` → `{data}`, `DELETE /held-carts/{heldCart}`. Kolom: tanpa `expires_at`, items array top-level. |
| Cicilan | `GET /installments` (filter `status`, `outlet_id`; **tanpa** `order_id`), `POST /installments/{installment}/pay` (`amount` + `payment_method_id` wajib). Kolom: `order_id, installment_number, amount, due_date, paid_date, status (pending\|paid\|overdue)`. |

## 1. Detail retur — `GET /returns/{retur}` (belum ada)

Flutter `ReturnDetailScreen` memanggilnya; selama 404, layar menampilkan
data bawaan dari daftar + snackbar jujur.

```php
// app/Http/Controllers/Api/V1/ReturController.php

use App\Http\Controllers\Api\V1\Concerns\ShopApi;

public function show(Request $request, Retur $retur): JsonResponse
{
    if ($deny = $this->denyGroup($request, 'transaksi')) {
        return $deny;
    }
    if (! in_array((int) $retur->outlet_id, $this->outletIds($request), true)) {
        return response()->json(['message' => 'Akses ditolak untuk outlet ini.'], 403);
    }

    return response()->json([
        'data' => $retur->load(['returnItems.product', 'order']),
    ]);
}
```

```php
// routes/api.php (grup v1, auth:api) — TAMBAHKAN SATU BARIS INI SAJA:
Route::get('/returns/{retur}', [\App\Http\Controllers\Api\V1\ReturController::class, 'show']);
```

## 2. Tolak retur — `POST /returns/{retur}/reject` (belum ada)

Flutter sudah memanggil endpoint ini dari tombol "Tolak" (dengan alasan
opsional); selama 404, snackbar menampilkan pesan server apa adanya.
**CatatanSTATUS:** agar selaras dengan mesin produksi yang memakai
`completed` sebagai status akhir sukses, status tolak diusulkan
`cancelled`. Jika operasional menghendaki `rejected` (sesuai komentar
migrasi `pending, approved, completed, rejected`), ganti satu string di
bawah — Flutter menerima `rejected` sebagai label legacy ("Ditolak").

```php
// app/Http/Controllers/Api/V1/ReturController.php

public function reject(Request $request, Retur $retur): JsonResponse
{
    if ($deny = $this->denyGroup($request, 'transaksi', 'edit')) {
        return $deny;
    }
    if (! in_array((int) $retur->outlet_id, $this->outletIds($request), true)) {
        return response()->json(['message' => 'Akses ditolak untuk outlet ini.'], 403);
    }
    if ($retur->status !== 'pending') {
        return response()->json(['message' => 'Retur sudah diproses sebelumnya.'], 409);
    }
    $data = $request->validate([
        'reason' => 'nullable|string|max:1000',
    ]);

    $retur->update([
        'status' => 'cancelled',
        'notes' => $data['reason'] ?? $retur->notes,
    ]);

    return response()->json(['data' => $retur->fresh()->load('returnItems')]);
}
```

```php
// routes/api.php (grup v1, auth:api) — TAMBAHKAN SATU BARIS INI SAJA:
Route::post('/returns/{retur}/reject', [\App\Http\Controllers\Api\V1\ReturController::class, 'reject']);
```

## 3. Bukan endpoint (sengaja TIDAK diusulkan)

- `POST /orders/{id}/installments` (buat jadwal plan/count/DP): tabel
  `installments` produksi tidak punya kolom plan/count/DP; jadwal lahir
  dari alur order kredit di server. Flutter memakai alur list + bayar
  per-installment.
- Filter `GET /installments?order_id=`: backend mengabaikannya; Flutter
  menyaring `order_id` di sisi klien.
- Kolom `expires_at` hold & path `/held-orders`: tidak ada di backend;
  Flutter sudah pindah ke `/held-carts` + `items[]`.

## Checklist verifikasi setelah tempel

- [ ] Tanpa token → 401; outlet tak berhak → 403 "Akses ditolak untuk outlet ini."
- [ ] `GET /returns/5` mengembalikan `returnItems` + `order`.
- [ ] `POST /returns/5/reject` dua kali → kedua 409 "Retur sudah diproses sebelumnya."
- [ ] `POST /returns/5/approve` setelah reject → 200 tanpa efek ganda
      (guard `completed` + `completed_at` tetap berlaku apa adanya).
