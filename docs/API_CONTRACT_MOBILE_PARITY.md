# Kontrak API Mobile — POS Retail (Backend Live)

Dokumen ini menggambarkan **kebenaran backend produksi**
(`posretail.whitelabel.co.id/api/v1`, repo `linducip2208/posretail`).
Aplikasi Flutter **mengikuti backend** — bukan sebaliknya.
Jangan mengubah enum/status backend; web admin bergantung padanya.

Konvensi global (trait `ShopApi`):

- Auth: `Authorization: Bearer <token>` → middleware `auth:api`.
  Tanpa token → 401. Tanpa akses modul/outlet → 403
  (`denyGroup`: `Akses ditolak untuk modul ini.`).
- Envelope list: `{ "data": [...], "meta": { "current_page", "last_page",
  "per_page", "total" } }`. `per_page` default 50, maks 100.
- Scope outlet selalu dari token (`outletIds`), bukan dari client.
- Error validasi → 422 `{message, errors}`.

## 1. Supplier

```
GET  /suppliers?search=&page=&per_page=        // envelope
POST /suppliers {name, phone?, email?, address?, contact_person?} → 201
GET  /suppliers/{id}                           // {data} + po_count (tanpa daftar PO)
```

Riwayat PO supplier: `GET /purchase-orders?supplier_id=`.
Belum ada: PUT/DELETE → lihat `BACKEND_PATCH_PURCHASING.md`. UI tulis
tetap ada dengan 404 jujur.

## 2. Purchase Order

Status (Inggris, persis): `draft | ordered | received | cancelled`.

```
GET  /purchase-orders?search=&status=&supplier_id=&outlet_id=&page=
     // search → po_number
POST /purchase-orders
     {supplier_id, outlet_id, notes?, items:[{product_id, quantity, unit_price}]} → 201
GET  /purchase-orders/{id}   // + supplier, outlet, user, purchaseOrderItems.product
POST /purchase-orders/{id}/receive   // idempoten; status + jurnal (TANPA auto-stok,
                                     // stok dicatat manual seperti web)
```

Belum ada: `POST .../order` (kirim) dan `POST .../cancel` →
lihat `BACKEND_PATCH_PURCHASING.md`. Tombol aksi tetap ada dengan 404 jujur.
Respons: `po_number`, `total_amount`, `notes`, relasi `purchaseOrderItems`.

## 3. Stock Opname

Status: `pending → completed` via approve.

```
GET  /stock-opnames?outlet_id=&status=&page=
POST /stock-opnames {outlet_id, notes?, items:[{product_id, actual_stock}]} (item wajib)
POST /stock-opnames/{id}/approve
```

Item: `system_stock`, `actual_stock`, `difference`.
Belum ada: GET detail + tambah item per sesi → `BACKEND_PATCH_INVENTORY.md`.
UI detail memakai data daftar + banner jujur bila 404.

## 4. Transfer Stok

Status: `draft → sent → received`.

```
GET  /stock-transfers?outlet_id=&status=
POST /stock-transfers {from_outlet_id, to_outlet_id, notes?, items:[{product_id, quantity}]}
POST /stock-transfers/{id}/send      // bukan /ship
POST /stock-transfers/{id}/receive
```

Belum ada: GET detail → `BACKEND_PATCH_INVENTORY.md`.

## 5. Mutasi Stok (read-only)

```
GET /stock-movements?outlet_id=&product_id=&type=&page=
    // type: in | out. Kolom: quantity (tidak ada qty_before/after, tanpa filter tanggal)
```

## 6. Bahan Baku & Resep

```
GET  /raw-materials?search=&low_stock=
POST /raw-materials {name, outlet_id, code?, unit_id?, cost_per_unit?, current_stock?, min_stock?}
     // satuan via GET /units → unit_id
```

Belum ada: PUT bahan baku dan endpoint resep (`recipe_items` hanya
internal) → `BACKEND_PATCH_INVENTORY.md`. Editor resep tampil dengan
banner 404 jujur.

## 7. Retur

Status: `pending → completed` (approve).

```
GET  /returns?outlet_id=&status=&page=
POST /returns {order_id, items:[{product_id, quantity}], reason?}
POST /returns/{id}/approve
```

Respons: `return_number`, `returnItems` (+`quantity`), `total_amount`.
Belum ada: GET detail + `POST .../reject` → `BACKEND_PATCH_SALES.md`
(tombol Tolak tetap ada, 404 jujur sampai patch diterapkan).

## 8. Tahan Transaksi (Hold)

Path backend: `/held-carts` (bukan `/held-orders`).

```
GET    /held-carts?per_page=            // scope outlet+user dari token
POST   /held-carts {outlet_id, customer_id?, label?, items[]}  // items min 1
POST   /held-carts/{id}/resume          // → {data: heldCart}; lanjutkan di kasir
DELETE /held-carts/{id}
```

## 9. Cicilan & Pembayaran

Per-installment (tidak ada plan/count/DP sebagai kolom).

```
GET  /installments?status=&outlet_id=   // tanpa filter order_id (saring di klien)
POST /installments/{id}/pay {amount, payment_method_id}  // metode WAJIB
```

Field: `installment_number`, `amount`, `due_date`, `paid_date`,
`status: pending | paid | overdue`. Jadwal dibuat dari penjualan
kredit di kasir (tidak ada endpoint buat-jadwal).

## 10. Diskon (read-only)

```
GET /discounts   // hanya active=true; tanpa filter server (saring di klien)
```

Field: `buy_quantity`, `get_quantity`, `start_date`, `end_date`.
Kelola via web admin (banner jujur di aplikasi).

## 11. Loyalitas

```
GET  /loyalty/rewards?per_page=         // hanya active, envelope
POST /loyalty/redeem {customer_id, reward_id}   // validasi saldo+aktif, transaksional
GET  /loyalty/summary?customer_id=      // {customer_id, name, total_points,
                                        //  points_earned, points_redeemed, total_spent}
```

Reward: `points_required` (bukan `points_cost`), tanpa kolom stok.

## 12. Grup Pelanggan (read-only)

```
GET /customer-groups
```

## 13. Pengguna & Peran (read-only)

```
GET /users?search=      // read-only; filter peran di klien
GET /roles              // {id, name, slug, description} — pakai slug
```

## 14. Absensi

```
POST /attendances/clock-in {outlet_id, notes?} → 201 (idempoten harian)
POST /attendances/clock-out
GET  /attendances/today                       // milik user login
```

Status: `present | late` (terlambat bila clock-in > 08:00).
Belum ada: riwayat list (opsional) → `BACKEND_PATCH_SYSTEM.md`.
Aplikasi fokus ke today + tombol clock.

## 15. Laporan

```
GET /reports/sales?start_date=&end_date=&outlet_id=    // {revenue, transactions, average, top_products}
GET /reports/stock?outlet_id=                          // {inventory_value, low_stock, out_of_stock}
GET /reports/finance?start_date=&end_date=             // {income, expense, net}
```

Maks 93 hari (422 bila lebih). Laporan Pembelian di aplikasi diagregasi
client-side dari `GET /purchase-orders` (maks 100 PO per halaman, banner
jujur). Agregasi server opsional → `BACKEND_PATCH_SYSTEM.md`.
Export PDF/Excel tetap via web.

## 16. Katalog pelengkap

`GET /brands`, `/units`, `/customer-groups`, `/payment-methods`,
`/categories`, `/outlets`, `/user` — dipakai picker di aplikasi.

## Endpoint yang sengaja TIDAK ada (keputusan sadar)

- Buat jadwal cicilan manual (jadwal lahir dari penjualan kredit).
- CRUD diskon/reward/grup/role via mobile (kelola via web admin).
- Export PDF/Excel via mobile (via web).

## Cara pakai dokumen ini

1. Tambah endpoint baru? Ikuti pola `ShopApi` (denyGroup + outletIds +
   envelope + pesan Indonesia) dan daftarkan di `routes/api.php`
   dalam grup `auth:api`.
2. Aplikasi Flutter langsung memakai endpoint baru begitu live;
   sebelumnya layar menampilkan pesan jujur + retry.
   Daftar tambahan yang diusulkan ada di `docs/BACKEND_PATCH_*.md` —
   semuanya SUDAH diimplementasikan di branch backend
   `mobile-parity-patch` (14 route + 1 migrasi, test 17/17 hijau);
   tinggal push branch, merge, jalankan migrasi, dan deploy agar
   aplikasi langsung berfungsi penuh.
3. Setiap perubahan kontrak: perbarui fixture MockClient di
   `test/*_test.dart` + kunci EN baru di `lib/l10n/strings_en.dart`
   (dijaga `test/i18n_coverage_test.dart`).
