# Audit UI/UX & Implementasi — POS Retail Flutter

- Tanggal audit & implementasi: 19 Okt 2026
- Repo Flutter: `posretailflutter` (lokal `D:\project flutter\pos-retail`, HEAD `3147c5b` + perubahan sesi ini — belum di-commit)
- Backend (sumber kebenaran kontrak API): `D:\project laravel\pos-retail` (HEAD `ccca4ca` = GitHub main, worktree bersih)
- API produksi: `https://posretail.whitelabel.co.id/api/v1` (hanya dirujuk dari `lib/config/api_config.dart`)
- Toolchain: Flutter 3.41.6 / Dart 3.11.4
- Baseline pra-perubahan: `flutter analyze` bersih, `flutter test` 18/18 pass
- Hasil akhir: `dart format` OK · `flutter analyze` **0 issue** · `flutter test` **53/53 pass** · `flutter build apk --release` **sukses**
- Commit sesi ini: `26321a6` (feat UI/UX + test), `540d86c` (branding Android), `7508f57` (docs) — sudah di-push ke `origin/main`

## 1. Metode

1. Membaca seluruh source Flutter (30 file `lib/`), 5 file test, `pubspec.yaml`, konfigurasi Android.
2. Membaca `routes/api.php` backend, controller `Api/V1`, policy, service checkout, model — kontrak diverifikasi langsung dari kode server (bukan asumsi).
3. Memetakan setiap fitur ke status: **Didukung API & ada di Flutter** · **Didukung API, belum diekspos UI** · **Tidak didukung backend** · **Tidak terverifikasi**.
4. Menjalankan baseline `flutter analyze` + `flutter test` sebelum perubahan, dan seluruh verifikasi (format/analyze/test/build) di akhir.
5. Tidak menghapus/mematikan test lama; seluruh test lama tetap hijau dan test baru ditambahkan.

## 2. Kondisi Awal & Defect (dengan status akhir)

### 2.1 Screen awal (11) → kondisi akhir

| # | Screen awal | File | Kondisi akhir |
|---|-------------|------|---------------|
| 1 | Splash | `lib/main.dart` | Branding baru (logo, tagline, indikator), locale `id_ID` diinisialisasi, wiring `onUnauthorized` aman (tanpa rekursi) |
| 2 | Login | `lib/screens/auth/login_screen.dart` | Dipoles, validasi lokal, error inline + status loading pada tombol |
| 3 | Outlet gate + pemilihan outlet | `lib/screens/outlet/outlet_selection_screen.dart` | Dipertahankan (alur outlet aktif konsisten) |
| 4 | Dashboard shell | `lib/screens/pos/dashboard_screen.dart` | Ditulis ulang: shell 5 tab (Beranda/Transaksi/Produk/Laporan/Lainnya) dengan `IndexedStack` |
| 5 | POS/kasir | `lib/screens/pos/pos_screen.dart` | Responsif (panel samping di tablet, bottom-sheet di ponsel), debounce, kategori, varian, cicilan DP, struk |
| 6 | Riwayat pesanan | `lib/screens/orders/orders_screen.dart` | + pencarian debounce, filter periode, deep-link dari detail, label status terpusat |
| 7 | Detail pesanan | `lib/screens/orders/order_detail_screen.dart` | + bagian pembayaran (dibayar/sisa/kembalian), cetak/share ulang, **aksi Refund** (izin server dihormati) |
| 8 | Laporan | `lib/screens/reports/report_screen.dart` | 4 metrik, rekap per metode (id→nama), produk terlaris, error+retry nyata, catatan pemotongan 500 baris |
| 9 | Pengaturan | `lib/screens/settings/settings_screen.dart` | Dipertahankan sebagai layar mandiri (berbagi komponen dengan menu Lainnya) |
| 10 | Daftar pelanggan (orphan) | `lib/screens/customers/customer_list_screen.dart` | Diakses dari menu Lainnya; + create pelanggan, detail, aksi deposit (topup/pakai/refund) |
| 11 | Widget dialog | `lib/widgets/*` | PaymentDialog: preset "Uang Pas", kembalian realtime, split pembayaran, DP kasbon, anti double-tap |

### 2.2 Defect awal (D1–D15) dan status akhir

| ID | Severity | Defect | Status akhir |
|----|----------|--------|--------------|
| D1 | CRITICAL | Pajak default 11% di klien ≠ server (`use_tax=false`) | **Fixed** — `CartProvider` default pajak 0; POS tidak lagi menawarkan input pajak; payload tidak mengirim pajak; baris "Pajak" hanya tampil bila > 0 |
| D2 | CRITICAL | Diskon total transaksi tidak didukung API | **Fixed** — fitur dihapus dari klien; hanya diskon per item yang dikirim (`discount_percent`) |
| D3 | HIGH | Laporan/Beranda tanpa `outlet_id` | **Fixed** — `fetchTodayOrders({outletId})`, `ReportProvider.load(outletId:)` mengirim outlet aktif |
| D4 | HIGH | POS tidak responsif (panel 300px fixed) | **Fixed** — layout adaptif: lebar ≥ 900dp panel samping, selain itu bottom-sheet keranjang |
| D5 | HIGH | Tanpa debounce pencarian | **Fixed** — debounce di POS, Produk, dan Pelanggan |
| D6 | MEDIUM | Gambar produk path relatif tidak tampil | **Fixed** — `Fmt.productImageUrl` menyusun URL storage (relatif/absolut/null) + test |
| D7 | MEDIUM | Query string tidak di-encode | **Fixed** — `ApiService` menerima `query` map dan meng-encode via `Uri`; diuji karakter khusus |
| D8 | MEDIUM | Cast paksa `response['data'] as List` | **Fixed** — parsing defensif di provider (cek bentuk, pesan error manusiawi) |
| D9 | MEDIUM | Laporan error → angka 0 diam-diam | **Fixed** — error state + tombol coba lagi; angka di-reset jelas (diuji) |
| D10 | MEDIUM | Beranda tanpa error/retry/quick action/sync | **Fixed** — Beranda baru: ringkasan hari ini, kartu sinkronisasi, quick action, stok menipis, transaksi terakhir |
| D11 | MEDIUM | Pelanggan orphan + error ditelan | **Fixed** — menu aktif di Lainnya; error server ditampilkan (`catch (_) {}` dihapus pada alur ini) |
| D12 | LOW | Dialog bayar tanpa preset/kembalian | **Fixed** — preset uang, "Uang Pas", kembalian realtime, pemisah metode tunai/non-tunai |
| D13 | LOW | Cicilan dikirim walau server tak membuat jadwal | **Fixed (semantik)** — mode cicilan = DP via `allowPartial`; status `partial` di server; struk mencetak "SISA TAGIHAN" |
| D14 | LOW | Tanpa adaptive icon; splash putih polos | **Fixed** — adaptive icon + warna brand, splash biru brand + logo, `values-v31` untuk Android 12+ |
| D15 | LOW | Detail pesanan tanpa pembayaran/cetak ulang | **Fixed** — ringkasan pembayaran + cetak/share ulang + refund |

### 2.3 Matriks kemampuan backend vs aplikasi (final, terkoreksi dari kode)

> Catatan koreksi: temuan audit awal tentang refund/shift/deposit/split-bill/payment-gateway dinyatakan **superseded** — rute-rute tersebut ternyata ada di `routes/api.php` (grup POS P2). Status final di bawah diverifikasi ulang per baris.

| Fitur | API (bukti) | UI akhir | Catatan |
|-------|-------------|----------|---------|
| POS/checkout + idempotensi `client_uuid` + sync-batch | ✅ | ✅ | Payload hanya item+varian+diskon%; total dihitung server |
| Riwayat & detail pesanan | ✅ | ✅ | + filter periode & pencarian |
| Produk: list/search/barcode/kategori/detail/varian | ✅ | ✅ | Tab Produk read-only (sesuai keterbatasan API) |
| CRUD produk / stok opname / transfer stok | ❌ | ❌ | Tidak dibuat |
| Hold/recall order | ❌ | ❌ | Tidak dibuat |
| Refund | ✅ `POST /orders/{order}/refund` | ✅ | Butuh izin server `hapus-transaksi`; jika 403, pesan server ditampilkan apa adanya (lihat §5) |
| Voucher | ⚠️ hanya `voucher_code` saat checkout | ❌ | Tidak ada endpoint preview → risiko salah nominal → tidak dibuat |
| Pelanggan: list/create/detail | ✅ | ✅ | Update pelanggan tidak ada di API |
| Deposit pelanggan (manual) | ✅ `POST /customers/{id}/deposits` (`topup,use,refund`) | ✅ | Di layar Pelanggan (detail pelanggan) |
| Deposit sebagai alat bayar checkout | ⚠️ | ❌ | **Bug server**: `deposit_amount` tercatat di order tapi saldo tidak dipotong; cancel malah menambah saldo (bukti §5) |
| Loyalty | ❌ (baca `total_points` saja) | Read-only | Ditampilkan di detail pelanggan |
| Shift kasir | ✅ `POST /shifts/open`, `POST /shifts/{id}/close` (tanpa GET) | ✅ | Layar Shift Kasir; id shift diingat lokal per perangkat |
| Inventory forecast / low stock | ✅ `/inventory/forecast` | ✅ | Beranda (preview) + Peringatan Stok (lengkap) |
| Laporan tersimpan | ❌ | Hitung klien | Dari `/orders/history` + `/payment-methods`; jendela ≤ 93 hari, limit 500 (ditandai UI) |
| Split bill | ✅ `POST /orders/{order}/split` | ❌ | Tidak diekspos (alur kompleks; didokumentasikan) |
| Serial number item | ✅ kolom didukung | ❌ | Tidak ada input UI; tidak diekspos |
| Payment gateway QRIS | ⚠️ `/payment/create`, `/payment/status` | ❌ | Butuh kredensial provider + bentuk respons belum terverifikasi → BLOCKED |
| Notifikasi / supplier / purchasing | ❌ | ❌ | Tidak dibuat |

Kontrak server yang wajib dipegang klien (terbukti dari kode):

- Pajak order dari API mobile **selalu 0** (`use_tax=false`) → klien default 0.
- `payments` di `/orders/today|history` **tanpa relasi metode** → nama metode dipetakan klien via `GET /payment-methods`.
- Jendela `/orders/history` ≤ 93 hari, `limit(500)` → UI menandai bila terpotong.
- `payments` wajib ≥ 1 saat create (amount ≥ 0) → "bayar nanti" tidak diformalkan; DP kasbon memakai `is_installment`.
- Nomor antrean per outlet per hari; `client_uuid` untuk idempotensi antrean offline.

## 3. Struktur Navigasi Final

Bottom navigation (5): **Beranda · Transaksi · Produk · Laporan · Lainnya**

- **Beranda** — ringkasan hari ini (omzet, transaksi, lunas, rata-rata) outlet aktif, kartu status sinkronisasi + antrean, quick action (Transaksi Baru, Scan, Riwayat, Pelanggan, Sinkronkan), peringatan stok menipis, transaksi terakhir.
- **Transaksi** — layar POS: pencarian debounce, kategori, scan barcode (termasuk varian), keranjang adaptif, checkout aman, struk (cetak/share/PDF).
- **Produk** — daftar + pencarian + filter kategori + infinite scroll + bottom-sheet detail read-only (harga, stok, varian).
- **Laporan** — periode (hari ini/kemarin/7 hari/bulan ini/rentang kustom), 4 metrik, metode pembayaran (id→nama), produk terlaris, daftar transaksi, catatan pemotongan.
- **Lainnya** — hub dengan pencarian menu & header profil:
  - Operasional: Pelanggan, Peringatan Stok, Sinkronisasi, Shift Kasir
  - Perangkat & Akun: Printer, Ganti Outlet, Bahasa, Profil
  - Informasi: Bantuan & Tentang, Keluar

## 4. Registri Perubahan Kode

### 4.1 Design system (baru)

| File | Isi |
|------|-----|
| `lib/theme/app_theme.dart` | `AppColors` (Primary `#2563EB`, Primary dark `#1D4ED8`, Accent `#F59E0B`, Success `#10B981`, Warning `#F59E0B`, Error `#EF4444`, Background `#F8FAFC`, Surface `#FFFFFF`, Text `#0F172A`, Secondary `#64748B` + varian soft/dark), `AppRadius`, `AppSpacing`, `AppTheme.light()/dark()` (Material 3) |
| `lib/utils/formatters.dart` | `Fmt`: rupiah, thousand, dateTime/date/time, `parseMoneyDigits`, `dateForApi`, `productImageUrl`, `compactCount` — satu-satunya tempat format angka/tanggal |
| `lib/widgets/common/` (11 file) | `price_text`, `metric_card`, `status_badge` (+`BadgeTone`), `section_header`, `empty_state`, `error_state` (retry), `loading_skeleton`, `quantity_stepper`, `app_snackbar`, `confirmation_dialog`, `sync_status_card` |

### 4.2 Data layer

| File | Perubahan |
|------|-----------|
| `lib/services/api_service.dart` | `get/post` dengan `query` map (encode aman), `ApiException(statusCode, message, errors)`, pesan Indonesia per status, penanganan 401 global (debounce 3 dtk) + `onUnauthorized` |
| `lib/services/offline_sync_service.dart` | + `resetFailedAttempts`, `deleteQueueItem`, `getQueueSummary` (pending/failed); batas 10 percobaan; antrean tidak pernah dihapus sebelum server konfirmasi |
| `lib/providers/order_provider.dart` | `fetchTodayOrders({outletId})` outlet-aware, parsing defensif |
| `lib/providers/report_provider.dart` | Agregasi klien (`maxRangeDays=93`, `historyLimit=500`), `BestSeller`, `PaymentBreakdown`, flag `truncated` |
| `lib/providers/product_provider.dart` | List/search/kategori/paginasi + guard |
| `lib/providers/cart_provider.dart` | Pajak default 0, diskon total dihapus, varian (`lineKey`, `unitPrice`, `displayName`), `toOrderPayload` ramping |
| `lib/models/category.dart` | Baru (kategori bersarang aman) |
| `lib/models/order.dart` / `product.dart` / `customer.dart` / `user.dart` | + `cashierName`; + `ProductVariant`/`sellableStock`; + `depositBalance`/`creditLimit`/`outstandingBalance`; perbaikan parsing |
| `lib/main.dart` | `MultiProvider` lengkap (+`ProductProvider`), theme, locale `id_ID`, `onUnauthorized` → `expireSession` + clear cart + navigasi login, splash branding |

### 4.3 Layar & widget

| Area | File |
|------|------|
| Shell | `screens/pos/dashboard_screen.dart` (5 tab `IndexedStack` + `NavigationBar`) |
| Beranda | `screens/home/home_screen.dart` |
| POS | `screens/pos/pos_screen.dart`, `widgets/payment_dialog.dart`, `widgets/cart_item_tile.dart`, `widgets/product_card.dart` |
| Produk | `screens/products/product_list_screen.dart` |
| Pesanan | `screens/orders/orders_screen.dart` (export `orderStatusLabel`/`paymentStatusLabel`), `screens/orders/order_detail_screen.dart` (+refund `_RefundSheet`) |
| Laporan | `screens/reports/report_screen.dart` |
| Lainnya | `screens/more/more_screen.dart`, `shift_screen.dart`, `stock_alert_screen.dart`, `sync_screen.dart`, `printer_screen.dart`, `profile_screen.dart`, `about_screen.dart` |
| Pelanggan | `screens/customers/customer_list_screen.dart` (+create & deposit) |
| Auth | `screens/auth/login_screen.dart`, `services/auth_service.dart` (+`logoutLocal`), `providers/auth_provider.dart` (+`expireSession`) |
| Printer | `services/printer_service.dart` (struk/PDF + baris "SISA TAGIHAN" bila ada sisa) |

### 4.4 Aset branding (Android)

| Aset | File |
|------|------|
| Master icon 1024px (dibuat dari `assets/app_icon.png`, HighQualityBicubic) | `android/icon/app_icon.png` |
| Skrip regenerasi deterministik | `android/icon/generate_icons.ps1` (jalankan: `powershell -File android/icon/generate_icons.ps1`) |
| Ikon legacy API<26 | `res/mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png` (48→192px) |
| Layer depan adaptive + ikon splash | `res/mipmap-*/ic_launcher_foreground.png` (108–432px), `res/drawable-*/launch_logo.png` (96–384px) |
| Adaptive icon API≥26 | `res/mipmap-anydpi-v26/ic_launcher.xml` (background `@color/ic_launcher_background`) |
| Warna brand | `res/values/colors.xml` (`ic_launcher_background`, `launch_background` = `#0258E3`) |
| Splash proses start | `res/drawable/launch_background.xml`, `res/drawable-v21/launch_background.xml` (biru brand + logo) |
| Splash Android 12+ | `res/values-v31/styles.xml` (`windowSplashScreenBackground`/`AnimatedIcon`) |

Catatan: `flutter_launcher_icons` **tidak dipakai** — versi yang kompatibel dengan `image ^3.3.0` (0.11.0) tidak membaca konfigurasi pubspec; generasi dilakukan via skrip agar deterministik tanpa mengubah dependency.

### 4.5 Test

6 file test baru (§6.3), 5 file test lama dipertahankan penuh.

## 5. Blocker / Tidak Didukung (eksplisit, dengan bukti)

| Item | Bukti / Alasan | Tindakan UI |
|------|----------------|-------------|
| Deposit sebagai alat bayar checkout | `CheckoutService.php:174,202-207` memakai `deposit_amount` untuk total/status, **tetapi tidak ada** pemotongan `deposit_balance` saat checkout; sebaliknya `Order.php:146-160` (cancel) menambah saldo sebesar `deposit_amount` → uang hantu. | Klien **sengaja tidak mengirim** `deposit_amount`. Deposit manual (topup/pakai/refund) tetap tersedia karena endpoint `PosExtraController.deposit` konsisten. Rekomendasi: perbaiki pemotongan saldo di checkout sebelum mengaktifkan. |
| Refund untuk role non-owner | `OrderPolicy::delete` butuh permission `hapus-transaksi`, tapi seeder hanya membuat `delete-transaksi` (`RolePermissionSeeder.php:24`) → efektif hanya user `*`/owner. | Aksi Refund tetap tersedia; pesan 403 server ditampilkan apa adanya (tidak menelan error). Rekomendasi backend: samakan slug. |
| Payment gateway QRIS | `routes/api.php:49-50` (`/payment/create`, `/payment/status`); butuh kredensial provider + bentuk respons belum terverifikasi. | Tidak dibuat (BLOCKED). |
| Voucher | Hanya `voucher_code` saat checkout; tidak ada endpoint preview/validasi nominal. | Tidak dibuat — salah ketik berisiko 422 membatalkan seluruh checkout. |
| Split bill | `routes/api.php:38` ada; alur multi-order kompleks dan tidak diminta. | Tidak diekspos di UI. |
| Serial number | Kolom didukung `CheckoutService`; tidak ada UI input. | Tidak diekspos. |
| CRUD produk/harga/stok/opname/transfer; hold/recall; notifikasi; supplier | Tidak ada endpoint. | Tidak dibuat; tab Produk read-only + keterangan. |
| Shift lintas perangkat/restart | Tidak ada endpoint GET shift → id shift diingat lokal (SharedPreferences) per perangkat; jika outlet masih punya shift terbuka dari perangkat lain, server 422 dan pesan dipetakan ke arahan "tutup dari admin web". | Layar Shift Kasir tetap tersedia dengan risiko terdokumentasi. |
| Pelanggan baru tidak muncul untuk kasir tertentu | Server membatasi daftar pelanggan non-`*` via `whereHas orders` → pelanggan tanpa order tidak tampil. | Dicatat; pencarian tetap memakai server. |

## 6. Testing (hasil akhir)

### 6.1 Perintah wajib

| Perintah | Hasil |
|----------|-------|
| `flutter pub get` | ✅ sukses |
| `dart format lib test` | ✅ dijalankan (68 file; 0 perubahan pada verifikasi akhir) |
| `flutter analyze` | ✅ **No issues found** |
| `flutter test` | ✅ **53/53 pass** (18 test lama tetap hijau + 35 test baru) |
| `flutter build apk --release` | ✅ `build\app\outputs\flutter-apk\app-release.apk` (71,9 MB, fat APK semua ABI) |
| `flutter build apk --release --split-per-abi` | ✅ `app-armeabi-v7a-release.apk` 22,9 MB · `app-arm64-v8a-release.apk` 26,5 MB · `app-x86_64-release.apk` 28,8 MB (rekomendasi distribusi) |

### 6.2 Cakupan test per file (11 file, 53 test)

| File | Test | Cakupan |
|------|------|---------|
| `cart_test.dart` | 4 | Matematika keranjang, payload minimal, kasus rusak |
| `login_test.dart` | 2 | Form login (2 field + 1 tombol), toggle visibilitas |
| `models_test.dart` | 5 | Parsing model tahan data aneh |
| `offline_sync_test.dart` | 6 | Antrean offline: idempotensi `client_uuid`, retry, batas percobaan (DB in-memory) |
| `widget_test.dart` | 1 | Splash branding |
| `api_service_query_test.dart` | 4 | Encode query (spasi/`&`/kosong/null), pesan 422 dari server, default 500, respons list |
| `cart_variant_test.dart` | 6 | Baris per varian, harga varian, batas 999, payload `product_variant_id`, clear |
| `formatters_test.dart` | 11 | Rupiah/pemisah ribuan, `parseMoneyDigits`, tanggal & fallback, URL gambar storage/absolut/null |
| `order_parse_test.dart` | 4 | `cashier_name` + fallback `user.name`, id item (untuk refund), payments, status tak dikenal |
| `report_provider_test.dart` | 4 | Agregasi omzet/status/rata-rata, produk terlaris, rekap metode (id→nama), tolak rentang >93 hari, error mereset angka |
| `payment_dialog_test.dart` | 6 | Metode dari server, tombol terkunci sebelum nominal, "Uang Pas" + hasil submit, **anti double-tap**, kasbon DP + sisa tagihan, gagal muat → error + terkunci |

### 6.3 Batasan pengujian (jujur, tanpa klaim palsu)

- Test otomatis memakai **mock HTTP** (`MockClient`) dan DB in-memory — **bukan** integrasi nyata ke backend produksi.
- Uji asap **perangkat nyata (emulator)** sudah dilakukan: splash → layar Masuk → percobaan login nyata ke API produksi (§6.5). Ini membuktikan aplikasi release berjalan di Android — **bukan** klaim integrasi checkout end-to-end.
- Alur end-to-end penuh (login sukses → outlet → checkout → cetak struk) **BLOCKED**: butuh kredensial staging dan printer.
- Bluetooth printer tidak dapat diuji di sini → BLOCKED.

### 6.4 Bug yang ditemukan & diperbaiki selama verifikasi

| Bug | Ditemukan oleh | Perbaikan |
|-----|----------------|-----------|
| `PaymentDialog` melempar `RangeError` saat daftar metode pembayaran kosong/gagal dimuat (`_active` mengakses `_entries[0]` yang kosong) | Test baru `payment_dialog_test.dart` (skenario gagal muat) | `_active` dibuat nullable + seluruh pemakaian dijaga; test hijau |
| Tombol "Masuk" (CTA utama) tampak **pucat** — `ElevatedButton` memakai default Material 3 (latar terang + teks primary), bukan warna brand | Uji asap emulator (§6.5) — terlihat pada screenshot login | `elevatedButtonTheme`/`filledButtonTheme` kini eksplisit `scheme.primary` + `scheme.onPrimary`; spinner tombol saat loading diubah ke `AppColors.primary` agar tetap terlihat pada state disabled |

### 6.5 Uji asap perangkat nyata (emulator Android)

Perangkat: emulator **Android 17 / SDK 37** (x86_64, AVD `wasender_test`), APK **release** `app-x86_64-release.apk` (bertanda tangan release key) dipasang via `adb install`, diluncurkan seperti aplikasi biasa.

| # | Langkah | Hasil | Bukti |
|---|---------|-------|-------|
| 1 | Luncurkan aplikasi | Splash native Android 12+ (biru brand + logo) → lanjut ke layar Masuk, **tanpa crash** | `docs/screenshots/emulator-1-splash-native.png` |
| 2 | Layar Masuk | Logo, judul, tagline, dua field, tombol Masuk, teks bantuan — render benar di layar 1080×2400 | `docs/screenshots/emulator-2-login.png` |
| 3 | Isi kredensial salah → tekan Masuk | Permintaan nyata ke API produksi; banner merah **"Kredensial tidak valid."** tampil rapi (pesan manusiawi, tanpa kebocoran data). Satu percobaan saja untuk menghindari rate-limit | `docs/screenshots/emulator-3-login-gagal.png` |
| 4 | Setelah perbaikan tema tombol (§6.4) + APK dibangun ulang & dipasang ulang | Tombol "Masuk" kini **biru solid** `#2563EB` dengan teks putih — sesuai design system | `docs/screenshots/emulator-4-login-tombol-final.png` |

Kesimpulan: aplikasi release **berjalan nyata di Android** — render UI, validasi input, panggilan jaringan, dan penanganan error terbukti bekerja. Login sukses, pemilihan outlet, checkout, dan cetak struk tetap **BLOCKED** (butuh kredensial staging + printer — §8.6).

## 7. Scorecard per Screen

Legenda: **PASS** = terverifikasi otomatis (test/analyze/build) dan/atau di perangkat nyata (§6.5) · **BLOCKED** = butuh perangkat/backend/kredensial · **NOT TESTED** = terkompilasi & analyze bersih, belum diuji manual (tanpa perangkat/backend).

| # | Screen/Area | Status | Basis |
|---|-------------|--------|-------|
| 1 | Splash | **PASS** | `widget_test.dart` + emulator nyata (§6.5): splash native Android 12+ & splash Flutter |
| 2 | Login | **PASS** | `login_test.dart` (2) + emulator nyata (§6.5): render, validasi, respons API produksi (gagal login → pesan server) |
| 3 | Outlet gate & pemilihan outlet | NOT TESTED | Kompilasi+analyze; butuh backend untuk alur nyata |
| 4 | Dashboard shell 5 tab | NOT TESTED | Kompilasi+analyze |
| 5 | Beranda | NOT TESTED | Data dari `/orders/today` & `/inventory/forecast` (butuh backend) |
| 6 | Transaksi (POS) | NOT TESTED (parsial PASS) | Logika keranjang+payload & dialog bayar PASS via test; layar penuh butuh backend |
| 7 | Dialog Pembayaran | **PASS** | `payment_dialog_test.dart` (6) — termasuk anti double-tap |
| 8 | Produk (list/detail) | NOT TESTED | Kompilasi+analyze |
| 9 | Laporan | PASS (logika) / NOT TESTED (layar) | `report_provider_test.dart` (4); layar butuh backend |
| 10 | Riwayat transaksi | NOT TESTED | Kompilasi+analyze |
| 11 | Detail pesanan + Refund | NOT TESTED | Butuh backend + izin user untuk verifikasi |
| 12 | Lainnya (hub menu) | NOT TESTED | Kompilasi+analyze |
| 13 | Pelanggan + deposit | NOT TESTED | Butuh backend |
| 14 | Shift kasir | NOT TESTED | Butuh backend |
| 15 | Sinkronisasi | PASS (logika) / NOT TESTED (layar) | `offline_sync_test.dart` (6) |
| 16 | Peringatan stok | NOT TESTED | Butuh backend |
| 17 | Printer (cetak/PDF) | **BLOCKED** | Butuh perangkat Bluetooth |
| 18 | Profil / Pengaturan / Bantuan | NOT TESTED | Kompilasi+analyze |
| 19 | Formatter & util uang/tanggal | **PASS** | `formatters_test.dart` (11) |
| 20 | API client (encode & error) | **PASS** | `api_service_query_test.dart` (4) |

## 8. Laporan Akhir

### 8.1 Menu final

**Bottom nav 5 tab:** Beranda · Transaksi · Produk · Laporan · Lainnya.
**Lainnya →** Pelanggan · Peringatan Stok · Sinkronisasi · Shift Kasir · Printer · Ganti Outlet · Bahasa · Profil · Bantuan & Tentang · Keluar.
Semua menu di atas punya alur bisnis + endpoint nyata; tidak ada tombol mati. Fitur tanpa dukungan API/berisiko (voucher, QRIS gateway, deposit sebagai alat bayar, split bill, CRUD produk) tidak ditampilkan dan didokumentasikan di §5.

### 8.2 Komponen design system

`AppColors`/`AppRadius`/`AppSpacing`/`AppTheme` (satu sumber) + 11 komponen common (`PriceText`, `MetricCard`, `StatusBadge`, `SectionHeader`, `EmptyState`, `ErrorState`, `LoadingSkeleton`, `QuantityStepper`, `AppSnackbar`, `ConfirmationDialog`, `SyncStatusCard`) yang dipakai lintas layar — tidak ada duplikasi warna/format di screen.

### 8.3 Aset branding

Adaptive icon (background warna brand + layer depan logo, `mipmap-anydpi-v26`), ikon legacy semua densitas, splash branded untuk API < 31 dan ≥ 31, master 1024px + skrip regenerasi. AndroidManifest tetap `android:label="POS Retail"` dengan `@mipmap/ic_launcher`.

### 8.4 Perubahan API

- **Tidak ada perubahan kontrak server** (Laravel tidak disentuh).
- Endpoint yang kini dipakai klien: `POST /login`, `GET /user`, `POST /logout`, `GET /outlets`, `GET /products`, `/products/search`, `GET /categories`, `GET /payment-methods`, `GET /orders/today?outlet_id`, `GET /orders/history?start_date&end_date&outlet_id`, `POST /orders`, `POST /orders/sync-batch`, `GET /orders/{id}`, `POST /orders/{order}/refund`, `POST /shifts/open`, `POST /shifts/{shift}/close`, `GET/POST /customers`, `POST /customers/{id}/deposits`, `GET /inventory/forecast`.
- Rekomendasi backend (tidak diubah di sesi ini): (1) perbaiki pemotongan `deposit_balance` saat checkout; (2) samakan slug permission refund (`hapus-transaksi` vs `delete-transaksi`); (3) sediakan endpoint preview voucher bila fitur voucher ingin diaktifkan.

### 8.5 Risiko tersisa

| Risiko | Dampak | Mitigasi saat ini |
|--------|--------|-------------------|
| Integrasi end-to-end belum diuji penuh (login sukses → checkout) | Alur penuh belum terbukti | Uji asap emulator (§6.5) membuktikan jalur jaringan nyata & penanganan error; alur penuh wajib divalidasi di staging (§8.6) |
| Bug deposit di server | Uang hantu bila diaktifkan | Klien tidak mengirim `deposit_amount` |
| Izin refund tidak ter-seed | Refund 403 untuk non-owner | Pesan server ditampilkan; fix disarankan |
| Shift id lokal per perangkat | Ganti perangkat/hapus data → shift "yatim" | Petunjuk tutup dari admin web pada 422 |
| Pelanggan baru tak tampil untuk kasir (scoping server) | Kasir bingung saat cari pelanggan baru | Dicatat; pelanggan tetap dibuat |
| APK 71,9 MB (fat) | Unduhan besar | Gunakan `--split-per-abi` (22,9–28,8 MB per ABI) untuk distribusi |

### 8.6 Checklist verifikasi wajib di staging (belum bisa dilakukan di sesi ini — BLOCKED)

1. Login nyata + expired token → kembali ke login tanpa crash (uji cabut token di server).
2. Pemilihan outlet ganda → pilih outlet → cek outlet_id di riwayat & laporan.
3. Checkout tunai (uang pas, kembalian), non-tunai, split pembayaran, kasbon DP → cocokkan total & status dengan server.
4. Antrean offline: matikan jaringan → checkout → nyalakan → cek tersinkron tanpa duplikat (`client_uuid`).
5. Refund dengan user owner → sukses; dengan user biasa → pesan 403 terbaca.
6. Shift buka/tutup + hitung kas; uji 422 shift ganda.
7. Pelanggan: create, topup, pakai, refund deposit → cocokkan saldo.
8. Printer Bluetooth: struk normal + struk dengan sisa tagihan.
9. Laporan rentang > 93 hari ditolak; > 500 order menampilkan catatan pemotongan.
10. Adaptive icon & splash di perangkat Android 12+ dan < 12. (Android 12+ sudah terverifikasi di emulator, §6.5; API < 12 masih butuh perangkat nyata.)

### 8.7 Status akhir

**READY FOR STAGING** — kode terkompilasi bersih (analyze 0 issue), 53/53 test otomatis pass, APK release terbangun (bertanda tangan release key dari `android/key.properties`; tersedia varian per-ABI), uji asap emulator nyata (release APK: splash → login → jalur API produksi) lulus (§6.5), dan tidak ada fitur palsu/tombol mati (fitur tanpa dukungan API dikecualikan secara eksplisit di §5). **NOT READY untuk produksi** sampai: (a) checklist §8.6 dieksekusi dengan backend & perangkat nyata, dan (b) perbaikan backend disepakati (deposit/slug refund).
