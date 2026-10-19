# ARCHITECTURE — POS Retail Flutter

## Lapisan

```
UI (screens/ + widgets/common/)
  → Providers (ChangeNotifier; auth/cart/order/product/report/lang)
  → Services (ApiService, OfflineSyncService, AuthService,
               PrinterService, SecureTokenStorage)
  → Backend Laravel `/api/v1` · SQLite `pos_offline.db` (v5)
```

- State: `provider`; tidak ada BLoC/Riverpod — konsisten di seluruh app.
- Navigasi: `IndexedStack` 5 tab (state dijaga); `OutletGate` memisahkan
  alur outlet; 401 global → `expireSession` + kembali login (debounce 3 dtk).
- Satu sumber: `ApiConfig.baseUrl` (dart-define override),
  `AppColors/AppRadius/AppSpacing` + Material 3, `Fmt` format,
  `S.t/tn/e` i18n (id default + en).

## Data offline (sqlite v5)

`products(+varian, index outlet/barcode)` · `offline_orders`
(client_uuid, payload, synced, attempts≤10, backoff 5s..15m, batch 50,
loop ≤10 ronde; `created/duplicate→synced`, 422→attempts+error, network
tanpa penalti; tidak hapus sebelum konfirmasi) · `payment_methods`
(cache global untuk checkout offline). Migrasi v2–v5 idempoten.

## Invarian keamanan & konsistensi

- Token di secure storage; `_token` diisi saat login/restore SEBELUM
  request apapun; 401 → wipe + logout.
- Server sumber kebenaran: harga, pajak (=0 mobile), total, stok, refund,
  shift. Klien tak menghitung ulang angka resmi.
- Idempotensi ujung-ke-ujung: `client_uuid` dibuat klien → `duplicate`
  server → tidak ada order ganda (terbukti E2E: 2×sync-batch → 1 order).
- Outlet isolation: query + cache + shift + deposit selalu outlet-aware.
- Uang: `double` hanya untuk tampil; payload memakai nominal yang
  divalidasi server (aturan 7 dipenuhi via server-side pricing; klien
  tidak membulatkan total sendiri).

## Batasan arsitektur yang disadari

- `orders/today` tanpa pagination server → beban di outlet ramai (B6).
- `sync-batch` subset payload (B7) → selisih potensial kasbon/voucher.
- Truncation respons dev-server → rekomendasi D17 (parse-fail = error).
- Cetak fisik butuh perangkat; PDF/share sebagai fallback resmi.
