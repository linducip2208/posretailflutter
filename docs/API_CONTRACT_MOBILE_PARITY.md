# Kontrak API Mobile Parity — POS Retail

Tujuan: menyamakan modul web (`posretail.whitelabel.co.id/admin/*`)
dengan aplikasi Flutter. Mobile saat ini hanya memakai ~12 endpoint;
dokumen ini mengusulkan 14 grup endpoint baru mengikuti konvensi yang
sudah ada.

## Konvensi yang diikuti

- Base: `https://posretail.whitelabel.co.id/api/v1`
- Auth: `Authorization: Bearer <sanctum>` (sama seperti `/products`).
  Tanpa token → `401 {"message":"Unauthenticated."}`.
- Envelope sukses: `{ "data": [...] | {...}, "meta": {...}?, "message": "..."? }`
- Pagination: `?page=&per_page=` (default `per_page=50`), meta:
  `{ "total": 0, "last_page": 1 }` — sama seperti `ProductProvider._fetch`.
- Scope outlet: `?outlet_id=` untuk semua data transaksional
  (sama seperti `/orders/today`, `/orders/history`, `/inventory/forecast`).
- Tanggal: `YYYY-MM-DD` (`Fmt.dateForApi`), waktu ISO-8601.
- Error: `422` validasi `{message, errors}`, `403` tanpa akses,
  `404` tidak ketemu — ditangani `ApiService._handleResponse`.

## Status saat ini (terverifikasi via probe tanpa token)

| Endpoint | Hasil | Keterangan |
|---|---|---|
| `GET /products`, `/customers`, `/categories`, `/payment-methods`, `/outlets`, `/user` | 401 | Ada, butuh token |
| `GET /orders/today`, `/orders/history`, `/inventory/forecast` | 401* | Ada (*dicek via kode, pola sama) |
| `POST /products/barcode`, `POST /orders`, `/orders/sync-batch`, `/shifts/open` | — | Ada (dipakai app) |
| Semua di bawah ini | 404 | Belum ada, perlu dibuat di Laravel |

## 1. Supplier — web `/admin/suppliers`

```
GET    /suppliers?search=&page=&per_page=
POST   /suppliers            {name, phone, email?, address?}
GET    /suppliers/{id}
PUT    /suppliers/{id}
DELETE /suppliers/{id}
```

`data[i]`: `{id, name, phone, email, address, po_count?, created_at}`.
Role: owner, admin, gudang (read), manager.

## 2. Purchase Order — web `/admin/purchase-orders`

Workflow web: `draft → dipesan → dikirim → diterima` (stok + saat diterima).

```
GET  /purchase-orders?outlet_id=&status=&supplier_id=&page=&per_page=
POST /purchase-orders
     {supplier_id, outlet_id, items:[{product_id, qty, cost_price}], note?}
GET  /purchase-orders/{id}        // items + supplier + riwayat status
POST /purchase-orders/{id}/ship   // dipesan → dikirim
POST /purchase-orders/{id}/receive // dikirim → diterima (tambah stok)
POST /purchase-orders/{id}/cancel {reason}
```

## 3. Stock Opname — web `/admin/stock-opnames`

```
GET  /stock-opnames?outlet_id=&status=&page=
POST /stock-opnames                {outlet_id, note?}          // buka sesi
POST /stock-opnames/{id}/items     {items:[{product_id, physical_qty}]}
POST /stock-opnames/{id}/approve   // terapkan koreksi, hitung surplus/deficit
GET  /stock-opnames/{id}
```

`item`: `{product_id, system_qty, physical_qty, diff}`.

## 4. Transfer Stok — web `/admin/stock-transfers`

```
GET  /stock-transfers?outlet_id=&status=
POST /stock-transfers  {from_outlet_id, to_outlet_id, items:[{product_id, qty}], note?}
POST /stock-transfers/{id}/ship
POST /stock-transfers/{id}/receive
GET  /stock-transfers/{id}
```

Status: `draft → dikirim → diterima`.

## 5. Mutasi Stok — web `/admin/stock-movements`

Read-only (ditulis server dari penjualan/pembelian/transfer/opname).

```
GET /stock-movements?outlet_id=&product_id=&type=&start_date=&end_date=&page=
```

`type`: `sale|purchase|transfer_in|transfer_out|opname|adjustment`.
`data[i]`: `{id, product_id, outlet_id, type, qty_before, qty_after, qty_change, reference_type, reference_id, created_at}`.

## 6. Retur — web `/admin/orders` (Retur)

```
GET  /returns?outlet_id=&status=&page=
POST /returns {order_id, items:[{product_id, qty}], reason}
POST /returns/{id}/approve   // stok auto-kembali
POST /returns/{id}/reject {reason}
```

`status`: `pending|approved|rejected`.

## 7. Tahan Transaksi (Hold) — web `/admin/orders` (Hold)

```
GET    /held-orders?outlet_id=
POST   /held-orders {outlet_id, label, cart:{items, customer_id?}}  // auto-expire 24 jam
POST   /held-orders/{id}/resume
DELETE /held-orders/{id}
```

## 8. Diskon — web `/admin/discounts`

```
GET /discounts?type=&active=
POST /discounts {name, type: percent|fixed|buy_x_get_y, value, min_purchase?, buy_qty?, get_qty?, start_at?, end_at?, active}
PUT /discounts/{id}
```

Dipakai POS saat checkout (per item + total).

## 9. Loyalitas — web `/admin/loyalty-rewards`

```
GET  /loyalty-rewards?active=
POST /loyalty-rewards {name, points_cost, stock, active}
GET  /loyalty-points?customer_id=          // earned/redeemed + saldo
POST /loyalty-points/redeem {customer_id, reward_id}
GET  /customer-groups                       // Regular/Member/Reseller + diskon
```

Aturan: poin auto-earned saat `POST /orders` lunas (server-side, sama seperti web).

## 10. Bahan Baku & Resep — web `/admin/raw-materials`

```
GET  /raw-materials?search=&low_stock=
POST /raw-materials {name, unit, stock, min_stock, cost_per_unit}
PUT  /raw-materials/{id}
GET  /recipes?product_id=
POST /recipes {product_id, items:[{raw_material_id, qty}]}
```

## 11. Cicilan & DP — bagian dari Order

```
GET  /installments?order_id=
POST /orders/{id}/installments {plan: weekly|biweekly|monthly, count, down_payment?}
POST /orders/{id}/payments {payment_method_id, amount}  // bayar cicilan/DP
```

Respons order menyertakan `due_amount`, `payment_status: paid|partial|pending`.

## 12. Pengguna & Peran — web `/admin/users`

```
GET /users?outlet_id=&role=
POST /users {name, email, password, role, outlet_ids:[]}
PUT  /users/{id} {name?, role?, active?, outlet_ids?}
GET /roles   // owner|admin|manager|kasir|gudang + permissions
```

Role matrix (sesuai halaman demo): kasir = POS saja; gudang = stok/PO/transfer;
manager = master+laporan+approval; admin = semua kecuali settings sistem;
owner = penuh.

## 13. Absensi — web Absensi Pegawai

```
GET  /attendances?outlet_id=&date=
POST /attendances/clock-in  {outlet_id}
POST /attendances/clock-out
```

`status`: `hadir|terlambat|izin|sakit`.

## 14. Laporan — web `/admin/laporan-*`

Mengikuti pola `GET /orders/history?start_date&end_date&outlet_id`
(max 93 hari, limit 500 terbaru + flag truncated).

```
GET /reports/purchases?start_date=&end_date=&outlet_id=
    // {total_cost, po_count, outstanding_po, top_suppliers[], trend[]}
GET /reports/inventory?outlet_id=
    // {low_stock[], overstock[], opname_accuracy, total_value, movements[]}
```

Export PDF/Excel tetap via web (mobile cukup tampil + share link file).

## Prioritas implementasi backend (usulan)

1. Supplier + PO + Mutasi (membuka menu Pembelian + membuat StockAlert bisa aksi).
2. Opname + Transfer (melengkapi Inventori).
3. Retur + Hold (melengkapi kasir).
4. Loyalty + Diskon + Grup (promo).
5. Cicilan/DP + Bahan baku.
6. Users + Absensi + Reports tambahan.

## Cara pakai dokumen ini

1. Backend Laravel: daftarkan route `api/v1` per grup di atas dengan
   middleware `auth:sanctum` + `scope outlet` yang sama dengan endpoint lama.
2. Setelah satu grup live (respons berubah 404 → 401/200),
   layar native Flutter modul tersebut langsung berfungsi penuh
   (daftar, buat, aksi workflow) tanpa update aplikasi;
   sebelum itu layar menampilkan pesan jujur + tombol coba lagi.
   Snippet siap-tempel per grup ada di `docs/BACKEND_*_SNIPPET.md`.
3. Setiap penambahan endpoint: tambahkan/perbarui widget test
   (`test/*_test.dart`) mengikuti pola `payment_dialog_test.dart`.

## Checklist verifikasi per endpoint baru

- [ ] Tanpa token → 401, dengan token salah outlet → 403/422 jujur
- [ ] `outlet_id` selalu di-scope server (jangan percaya client saja)
- [ ] Pagination + `search` konsisten dengan `/products`
- [ ] Status workflow persis string web (`draft`, `dipesan`, dst.)
- [ ] Mutasi stok tertulis untuk setiap perubahan qty (audit trail)
