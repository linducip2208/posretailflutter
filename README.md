# POS Retail — Aplikasi Kasir (Flutter)

Aplikasi kasir Android untuk **POS Retail**: transaksi cepat, scan barcode,
mode offline dengan antrian sinkronisasi, cetak struk Bluetooth/PDF, dan
laporan per periode. Terhubung ke backend Laravel lewat **API v1**.

> Backend: `https://github.com/linducip2208/posretail` (`/api/v1`)

## Fitur

- Login kasir (Sanctum token, secure storage) + auto-login + logout
- Seleksi outlet (otomatis bila 1 outlet) — semua transaksi memakai outlet aktif
- POS: pencarian produk, scan barcode kamera (debounce), keranjang, diskon/item
- Checkout: tunai/split payment, cicilan/kasbon, customer, kembalian otomatis
- Anti double-tap: tombol bayar terkunci saat proses + `client_uuid` idempoten
- Offline-first: order antre di SQLite (`pos_offline.db`), terkirim via
  `POST /orders/sync-batch` saat online; badge "menunggu kirim" + retry
- Struk: PDF (58/80mm), share, print Bluetooth thermal
- Laporan: hari ini / kemarin / minggu ini / bulan ini (API nyata)
- Customer: cari, tambah, pilih + poin/loyalty
- Bahasa Indonesia / English (toggle di Pengaturan)

## Requirements

- Flutter 3.41+ (stable), Dart SDK `^3.11.4`
- Android SDK (minSdk/target lihat `android/app/build.gradle.kts`)
- Backend POS Retail berjalan & reachable (prod: `https://posretail.whitelabel.co.id`)

## Setup

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Konfigurasi base URL: `lib/config/api_config.dart` (`ApiConfig.baseUrl`) —
satu-satunya sumber URL API. Jangan hard-code URL di file lain.

## Arsitektur singkat

```
lib/
  main.dart                # providers + 401 → login + OutletGate
  config/api_config.dart   # SATU sumber base URL
  models/                  # parsing JSON null-safe (utils/safe_parse.dart)
  providers/               # AuthProvider (user+outlet), CartProvider, OrderProvider
  services/
    api_service.dart       # HTTP + pesan error manusiawi (ID/EN) + hook 401
    auth_service.dart      # login/user/outlets/logout + outlet tersimpan
    secure_token_storage.dart  # token di Keystore/Keychain (bukan prefs)
    offline_sync_service.dart  # SQLite queue + sync-batch idempoten
    printer_service.dart   # struk PDF + Bluetooth
  screens/
    auth/ pos/ orders/ customers/ reports/ settings/ outlet/
  l10n/                    # Indonesia (kunci) + English
  utils/safe_parse.dart
```

## Alur penting

1. Splash → auto-login → `OutletGate`: 1 outlet = otomatis, >1 = pilih,
   0 = hubungi admin. Pilihan tersimpan (`current_outlet_id`).
2. Semua checkout memakai outlet aktif. Server tetap memvalidasi akses outlet,
   harga, stok, diskon, pajak — client tidak dipercaya untuk total.
3. Offline: payload (termasuk `client_uuid`) antre lokal → `sync-batch`
   (maks 50/order batch, idempoten: retry mengembalikan order yang sama).
4. Token 401 (kedaluwarsa/dicabut) → otomatis logout + kembali ke login.

## Release build

```bash
flutter build apk --release
```

Jangan commit keystore. Signing release dikonfigurasi di
`android/app/build.gradle.kts` (baca komentar `signingConfigs` di sana).

## Troubleshooting

| Gejala | Penyebab umum |
|---|---|
| Login gagal padahal kredensial benar | Base URL salah / backend down / user nonaktif |
| "Pilih outlet dulu" | Akun tanpa akses outlet — atur di admin backend |
| Badge "menunggu kirim" tidak hilang | Validasi server gagal — cek `last_error` via log; data tetap aman lokal |
| Printer tidak ketemu | Nyalakan Bluetooth + pairing dulu di sistem Android |
| 422 saat checkout | Produk beda outlet / stok kurang / tipe order tak dikenal |
