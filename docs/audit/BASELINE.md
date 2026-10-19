# BASELINE — POS Retail Flutter (Refresh E2E + Audit Penuh)

- Tanggal: 19 Okt 2026 (sesi lanjutan E2E lokal + refresh audit)
- Repo Flutter: `https://github.com/linducip2208/posretailflutter`
  - Lokal: `D:\project flutter\pos-retail`, branch `main`
  - HEAD saat refresh: `59cc79c` (sudah push: `origin/main` sinkron)
  - Perubahan tak-commit saat refresh: `lib/services/offline_sync_service.dart`,
    `lib/widgets/payment_dialog.dart`, `test/offline_sync_test.dart`
    (fitur cache metode pembayaran untuk checkout offline — lihat DEFECTS D16)
- Repo backend (read-only, TIDAK dimodifikasi): `D:\project laravel\pos-retail`
  - HEAD: `6174114` ("desain ulang semua halaman laporan + chart modern")
  - `git status` backend tidak dicek tulis — seluruh perintah artisan hanya
    `serve`/`migrate:status` dengan `DB_DATABASE=pos_retail_e2e`
- API produksi default: `https://posretail.whitelabel.co.id/api/v1`
  (hanya dari `lib/config/api_config.dart`; dapat dioverride via
  `--dart-define=API_BASE_URL=...`)
- DB uji E2E (isolasi penuh): MySQL `pos_retail_e2e`
  (DB `pos_retail` milik pengguna TIDAK PERNAH disentuh;
  seed: 5 role, 45 permission, 1000 produk, 500 orders, 200 customers)
- Kredensial demo: `owner@pos-retail.test` / `password`
  (juga manager/admin/kasir/gudang). Outlet: Toko Pusat id=1.

## Toolchain

| Komponen | Versi | Keterangan |
|----------|-------|------------|
| Flutter | 3.41.6 stable (rev db50e20168, 2026-03-25) | `flutter --version` |
| Dart | (mengikuti Flutter 3.41.6) | `dart --version` menyusul bila perlu |
| PHP CLI | 8.3.30 ZTS VC2019 x64 | `php -v` |
| Composer | 2.8.4 | `composer --version` |
| MySQL client | 8.4.9 Win64 | server: Laragon `mysql-8.4.3-winx64` |
| adb | D:\sdk\platform-tools | emulator `emulator-5554` (AVD `wasender_test`) |
| Node (infra uji) | v24.15.0 | proxy E2E + probe paralel (folder temp, bukan repo) |

## Baseline verifikasi (pre-perubahan sesi ini)

| Pemeriksaan | Hasil |
|-------------|-------|
| `dart format lib test` | 0 changed |
| `flutter analyze` | 0 issue |
| `flutter test` | 54/54 pass (53 lama + 1 cache-metode baru) |
| `flutter build apk --release` | sukses (baseline sebelumnya; rebuild di akhir sesi) |
| `flutter build apk --debug` (+dart-define lokal) | sukses, terpasang di emulator |

## Infrastruktur uji E2E lokal (sementara, di luar repo)

- Backend: `php artisan serve 127.0.0.1:8001` + `DB_DATABASE=pos_retail_e2e`
- Proxy normalisasi `127.0.0.1:8000 → 127.0.0.1:8001` (Node, log file):
  menyekuensialkan request ke server PHP single-thread, mengirim ulang
  respons dengan `Content-Length` + keep-alive, mencatat method/path/query/
  status/ukuran + ekor token (8 char) untuk diagnosis auth.
- APK debug menunjuk `http://10.0.2.2:8000/api/v1` (NAT emulator→host).
- Ditemukan & terbukti: respons `php artisan serve` bersifat
  `Connection: close` tanpa `Content-Length`; body besar terpotong lewat
  NAT emulator → JSON gagal parse → `_handleResponse` mengembalikan `{}`
  diam-diam (layar kosong tanpa error). Proxy meniadakan artefak ini.
  Rekomendasi permanen: perlakukan body 2xx yang tak-terparse sebagai
  error jaringan (bukan `{}`) — lihat DEFECTS D17.

## Batasan lingkungan yang terbukti

- Emulator kehabisan RAM (lowmemorykiller) → proses app dibunuh sistem
  saat cold start; BUKAN crash aplikasi. Mitigasi: reboot emulator.
- Panel "stylus" emulator menelan input teks → ketik via `adb input text`
  setelah dismiss; koordinat tombol dialog wajib deteksi piksel/uiautomator.
- Printer Bluetooth fisik: TIDAK TERSEDIA → status BLOCKED (bukan gagal).
- `curl` tidak ada di emulator → diagnosis jaringan via proxy log + probe host.
