# TEST RESULTS — 19 Okt 2026 (sesi E2E + refresh)

## Otomatis (repo Flutter)

| Perintah | Hasil |
|----------|-------|
| `dart format lib test` | 0 changed |
| `flutter analyze` | 0 issue |
| `flutter test` | **54/54 pass** (11 file: cart, cart_variant, formatters, models, order_parse, api_service_query, offline_sync, report_provider, payment_dialog, login, widget) |
| `flutter build apk --debug` (+dart-define lokal) | sukses, terpasang emulator |
| `flutter build apk --release` | sukses (baseline; rebuild final sebelum push) |

Regresi penting: cache `payment_methods` round-trip (baru); anti double-tap;
idempotensi duplicate; 401 debounce; backoff tanpa penalti jaringan.

## E2E emulator → backend `pos_retail_e2e` (bukti: proxy log + DB + screenshot)

| Skenario | Hasil | Bukti |
|----------|-------|-------|
| Login + pilih outlet + dashboard data nyata | PASS | `POST login 200`, omzet 1.714.681/6 txn |
| POS: produk 50 + kategori + search | PASS | `products 200 56334B`, search "E2E" 1 hasil |
| Checkout tunai pas | PASS | order **501** (order+item+payment Tunai+stok 120→119+mutasi out) |
| Riwayat + detail (badge antrean 007) | PASS | `orders/history 200`, nama metode "Tunai" |
| Refund parsial owner | PASS | `POST refund 201` → **RT-20261019-0001**, stok 119→120, mutasi `in via return` |
| Shift open → close + selisih | PASS | shift **13**: 100rb→112rb, difference 12000 |
| Pelanggan create + deposit topup | PASS | customer **201**, balance 0→50.000 |
| Checkout offline → antrean → auto-sync idempoten | PASS | pending badge 1 → `sync-batch 200` ×2 → order **502** tunggal, stok→119 |
| Laporan (termasuk order sync) | PASS | omzet 1.726.681; metode ter-mapping |
| Token dihapus → 401 → login | PASS | `/user 401` → logout → LoginScreen |
| Deposit `use` | **FAIL (server)** | `500 Data truncated type`; saldo −12rb tanpa jejak (D18) |
| Cetak fisik Bluetooth | BLOCKED | tanpa perangkat (PDF/share teruji UI) |
| Scan barcode kamera | NOT VERIFIED | endpoint ada; tanpa label uji fisik |

## Backend (read-only)

Tidak menjalankan `php artisan test`/migrasi destruktif di repo pengguna.
Verifikasi kontrak via baca kode + perilaku E2E. `migrate:status` hanya
untuk konfirmasi isolasi DB.
