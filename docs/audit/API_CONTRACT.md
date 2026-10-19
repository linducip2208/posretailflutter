# API CONTRACT — mobile `/api/v1` (diverifikasi dari kode backend)

Sumber: `routes/api.php:13-59`, `app/Http/Controllers/Api/V1/*`,
`config/auth.php:45-48`. Backend HEAD `6174114`. Guard SEMUA route mobile:
`auth:api` (driver **sanctum**) + `throttle:120,1`; login publik +
`throttle:10,1`. Tidak ada middleware `permission:` — cek manual per
controller (`hasPermission('*')`, `getAccessibleOutletIds()`,
`$token->can(...)`, `OrderPolicy@delete`).

## Konvensi

- Sukses: `{data: ...}` — KECUALI login (`{token, user}` root) dan
  categories (`{categories: ...}`). Klien menangani ketiga bentuk.
- Error: `{message, errors?}` + status tepat (401/403/422/429/500).
- Idempotensi: `client_uuid` (unique nullable) — `store` kembalikan
  `200 {duplicate:true}` bila sudah ada; `sync-batch` status per item.

## Endpoint yang dipakai Flutter (17)

| Method & path | Validasi kunci | Respons | Dipakai di |
|---------------|----------------|---------|------------|
| POST /login | email, password | 200 `{token, user{id,name,email,role,outlets[]}}`; abilities `['pos-access', role]` | AuthService |
| GET /user | — | 200 user + outlets | restore sesi |
| GET /outlets | — | 200 `{data[]}` (hak user) | seleksi outlet |
| POST /logout | — | 200 (hapus token aktif) | logout |
| GET /categories | — | 200 `{categories[]}` + children | POS, Produk |
| GET /products | search≤100, category_id exists, per_page (crop 1..100, default 50) | 200 `{data[], meta{current_page,last_page,total}}`; eager category,unit,variants; `active=true` | POS, Produk |
| GET /products/{id} | binding | 200 `{data}` | (cadangan detail) |
| POST /products/barcode | barcode required | 200 `{data}` (produk ATAU varian; TANPA filter active — B9) | scan POS |
| GET /customers | search, per_page d20 | 200 `{data[], meta}` + customerGroup; non-`*` difilter order outlet | Pelanggan |
| GET /customers/{id} | — | 200; 403 bila non-`*` tanpa order di outletnya | detail |
| POST /customers | name required; email unique; phone≤30 | 201 `{data}` (tanpa cek outlet — B11) | tambah |
| POST /customers/{id}/deposits | outlet_id required; **type∈topup,use,refund**; amount 1..1M | 201 + update balance. **⚠️ `use` = 500** (enum DB cuma topup/deduct/refund — D18) | deposit |
| POST /orders | items 1..200 (product exists, qty 1..1000, disc 0..100; **harga dari server**, unit_price diabaikan); outlet required; payments 1..10 wajib; client_uuid opsional | 201 `{data}` (`queue_number` harian/outlet; tax 0; paid/partial/pending). Efek: orders+items+payments(success)+stock out+decrement stok | checkout |
| POST /orders/sync-batch | orders 1..50; per item client_uuid required (TANPA deposit/cicilan/voucher/notes — B7) | 200 per item `{created/duplicate/failed}`; selalu 200 | antrean offline |
| GET /orders/today | outlet_id opsional | 200 array TANPA limit (B6); eager lengkap | Beranda |
| GET /orders/history | start/end Y-m-d; **maks 93 hari**; limit 500 | 200 array | Riwayat, Laporan |
| GET /orders/{id} | — | 200 + items.product,variant + payments.method + user/customer/outlet | detail |
| POST /orders/{id}/refund | items(order_item_id+qty), reason≤1000; butuh `hapus-transaksi`/`*` | 201 retur + restore stok + `cash_out` shift (⚠️ shift_id null → 500 bila migrasi B4 belum jalan) | refund |
| POST /shifts/open | outlet; starting_cash 0..1M | 201 (tolak bila masih open) | shift |
| POST /shifts/{id}/close | ending_cash | 200 (expected = awal+tunai_rentang+cash_in−cash_out; difference) | tutup shift |
| GET /inventory/forecast | weeks→clamp 4..24 (default 12); outlet opsional | 200 `{weeks, forecast[50], low_stock[50]}` | stok, beranda |
| GET /payment-methods | — | 200 `{data[]}` aktif | dialog bayar, laporan |
| POST /payment/create|status; GET /payment/presets | amount wajib == sisa server | gateway (TIDAK dipakai kasir — butuh kredensial) |

## Tidak dipakai Flutter (sengaja)

- `POST /orders/{id}/split` — alur kompleks; tercatat, tak diekspos.
- `POST /payment/*`, webhooks — butuh kredensial/signature; BLOCKED.
- CRUD produk/opname/transfer/hold/voucher-preview — TIDAK ADA endpoint
  mobile → tidak dibuat (aturan 13–14).

## Mismatch (pemilik: backend) — ringkas, detail di DEFECTS.md §C

B1 enum deposit · B2 refund=increment · B3 shift active/open ·
B4 shift_id nullable · B5 ability tak konsisten · B6 today tanpa limit ·
B7 syncBatch drop field · B8 pajak 0 · B9 byBarcode · B10 envelope ·
B11 customer outlet · B12 order_type dinamis · B13 uuid scope ·
B14 webhook auth · B15 policy outlet.
