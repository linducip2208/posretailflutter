# BACKEND PATCH (ADITIF, OPSIONAL) — Loyalty/Promo, Reports, System

> STATUS: sudah diimplementasikan di branch backend `mobile-parity-patch`
> (GET attendances/history + GET reports/purchases; test hijau).
> Tinggal push, merge (jalankan migrasi bila ada), deploy.
> Backend produksi live — JANGAN ubah enum/kolom/route yang ada.
> Dokumen ini hanya berisi usulan **aditif** (route + method baru) bila
> tim backend menginginkannya. **Layar Flutter sudah 100% cocok dengan
> endpoint yang ADA** tanpa patch ini; patch bersifat nice-to-have.

Kebenaran backend per 2026-10-28 (`routes/api.php` + controller + model):

| Kebutuhan mobile | Status backend | Keputusan Flutter |
|---|---|---|
| Katalog reward | `GET /loyalty/rewards` (envelope, `points_required`, `discount_type/value`, `active`) | ✅ dipakai langsung |
| Redeem + saldo | `POST /loyalty/redeem`, `GET /loyalty/summary?customer_id=` | ✅ dipakai langsung |
| CRUD reward (`POST/PUT /loyalty-rewards`) | ❌ tidak ada | Read-only jujur (kelola via web) |
| Template diskon | `GET /discounts` read-only (`buy_quantity`, `get_quantity`, `start_date/end_date`, outlet-scope) | ✅ read-only jujur, filter client-side |
| CRUD diskon (`POST/PUT /discounts`) | ❌ tidak ada | Read-only jujur (kelola via web) |
| Grup pelanggan | `GET /customer-groups` read-only | ✅ dipakai langsung |
| Laporan pembelian (`/reports/purchases`) | ❌ tidak ada | Agregasi client-side dari `GET /purchase-orders` (max 100 terbaru, banner jujur) |
| Laporan inventori (`/reports/inventory`) | ❌ tidak ada | `GET /reports/stock` (value + count) + `GET /stock-movements` |
| Daftar absensi (`GET /attendances`) | ❌ tidak ada | Fokus `GET /attendances/today` + clock-in/out; riwayat via web |
| CRUD pengguna (`POST/PUT /users`) | ❌ tidak ada (`GET /users?search=`, `GET /roles`) | Read-only jujur (kelola via web) |

## Opsi aditif 1 — riwayat absensi (tidak mengubah yang ada)

```php
// AttendanceController.php — method BARU, route BARU. Enum status
// (present|late) dan clock-in/out tidak disentuh.
public function history(Request $request): JsonResponse
{
    $request->validate([
        'outlet_id' => 'nullable|integer|exists:outlets,id',
        'from' => 'nullable|date',
        'to' => 'nullable|date|after_or_equal:from',
        'per_page' => 'nullable|integer|min:1',
    ]);
    $query = Attendance::with('user:id,name')
        ->whereIn('outlet_id', $this->outletIds($request))
        ->latest('date');
    if ($request->filled('outlet_id')) {
        $query->where('outlet_id', (int) $request->outlet_id);
    }
    if ($request->filled('from')) {
        $query->whereDate('date', '>=', $request->from);
    }
    if ($request->filled('to')) {
        $query->whereDate('date', '<=', $request->to);
    }
    return $this->envelope($query->paginate($this->perPage($request)));
}

// routes/api.php — tambah SATU baris (yang lain tidak diubah):
// Route::get('/attendances/history', [AttendanceController::class, 'history']);
```

Flutter saat ini TIDAK memanggil `/attendances/history`; bila suatu hari
live, layar absensi cukup menambah tab riwayat dengan fallback 404 jujur
+ retry seperti sekarang.

## Opsi aditif 2 — agregat laporan pembelian server-side (opsional)

Bila agregasi 100 PO di mobile dirasa kurang akurat untuk outlet besar,
backend bisa menambah SATU endpoint baca-saja (tabel `purchase_orders`
sudah ada; tanpa migrasi):

```php
// GET /reports/purchases?start_date=&end_date=&outlet_id= (max 93 hari,
// pola sama seperti ReportController::sales)
→ {start_date, end_date, total_cost, po_count, outstanding_po,
   top_suppliers: [{name, total}], trend: [{date, total}]}
```

Sampai endpoint itu ada, Flutter menghitung dari `/purchase-orders`
dengan banner keterbatasan yang jujur — tidak ada error 404.

## Yang SENGAJA tidak diusulkan

- CRUD diskon / reward / pengguna: data master sensitif → tetap via web
  admin (keputusan keamanan, bukan keterbatasan).
- Perubahan enum `present|late`, field `points_required`,
  `buy_quantity/get_quantity`: Flutter yang menyesuaikan, bukan backend.
