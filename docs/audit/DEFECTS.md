# DEFECTS — Registri Temuan (bukti, status, pemilik)

Legenda status: FIXED (terbukti hijau) · OPEN-FLUTTER (tugas repo ini) ·
BACKEND (milik repo Laravel — Flutter TIDAK boleh mengubah; butuh keputusan
pengguna) · INFRA (artefak lingkungan uji) · WONTFIX/TERCATAT.

## A. Defect lama D1–D15 — semua FIXED & terhijau

(ringkasan; detail di `docs/FLUTTER_UI_UX_AUDIT.md §2.2`)

| ID | Defect | Bukti fix |
|----|--------|-----------|
| D1 | Pajak default klien 11% ≠ server 0 | CartProvider default 0; payload tanpa pajak |
| D2 | Diskon total tak didukung API | Dihapus; hanya `discount_percent` per item |
| D3 | Laporan/Beranda tanpa outlet_id | outlet-aware; E2E `?outlet_id=1` di proxy log |
| D4 | POS tidak responsif | layout adaptif ≥900dp / bottom-sheet |
| D5 | Tanpa debounce | POS/Produk/Pelanggan; E2E search 1 hasil |
| D6 | Gambar relatif tak tampil | `Fmt.productImageUrl` + test |
| D7 | Query tak di-encode | `ApiService.query` map + test karakter khusus |
| D8 | Cast `as List` | parsing defensif (sisa `as List` terjaga `is`-check — audit statis) |
| D9 | Laporan error → angka 0 diam-diam | error+retry; angka reset eksplisit |
| D10 | Beranda tanpa error/retry/quick action | beranda baru; E2E tampil data nyata |
| D11 | Pelanggan orphan + error ditelan | menu aktif; E2E create 201 + deposit |
| D12 | Dialog bayar tanpa preset/kembalian | preset + realtime; E2E tunai pas Rp12.000 |
| D13 | Cicilan semantik salah | DP `allowPartial`; struk SISA TAGIHAN |
| D14 | Tanpa adaptive icon/splash | adaptive icon + splash brand (terverifikasi visual) |
| D15 | Detail tanpa pembayaran/cetak/refund | ringkasan + refund; E2E refund 201 + stok pulih |

## B. Temuan sesi E2E lokal (baru)

### D16 — Checkout offline mustahil: metode pembayaran hanya dari server
- Gejala: dialog bayar offline terkunci (tidak ada metode → tombol mati),
  padahal catatan UI menjanjikan "transaksi masuk antrean kirim".
- Status: **FIXED (Flutter)** — `payment_methods` v5 di sqlite +
  `cachePaymentMethods/getCachedPaymentMethods` + fallback di
  `PaymentDialog._loadMethods` (hanya saat `ApiNetworkException`) +
  caption "Mode offline — memakai daftar metode tersimpan."
  + test round-trip `offline_sync_test.dart`.
- Verifikasi: `flutter analyze` 0 issue, `flutter test` 54/54.
  E2E penuh (cache→offline→antrean→sync) MENUNGGU emulator pulih (reboot).

### D17 — Respons dev-server terpotong → layar kosong tanpa error
- Gejala: POS & Produk kosong tanpa error padahal server menjawab 200/50 item.
- Akar (terbukti via probe + proxy + curl sejajar): `php artisan serve`
  menjawab `Connection: close` tanpa `Content-Length`; body besar (±56 KB)
  terpotong lewat NAT emulator → `jsonDecode` gagal → `_handleResponse`
  mengembalikan `{}` diam-diam.
- Status: **INFRA teratasi** (proxy normalisasi + sekuens) — BUKAN bug app.
- Rekomendasi permanen (OPEN-FLUTTER, P2): body 2xx yang tak-terparse
  harus melempar `ApiNetworkException` (bukan `{}`), agar korupsi jaringan
  tampil sebagai error+retry, bukan "kosong".

### D18 — Deposit `use` → 500 + saldo terpotong tanpa jejak (BACKEND)
- Bukti: `POST /customers/201/deposits {type:use}` → `500`;
  `deposit_balance` 50000→38000; tabel `customer_deposits` TANPA baris `use`;
  `laravel.log`: `SQLSTATE 1265 Data truncated for column 'type'`.
- Akar: validasi `in:topup,use,refund` (PosExtraController:171) vs kolom
  `enum('topup','deduct','refund')` + tanpa DB transaction (decrement dulu,
  insert gagal belakangan).
- Status: **BACKEND** — butuh migrasi enum (`use`) + bungkus transaksi.
  Flutter BENAR (mengikuti kontrak validasi). Uji `use` dihentikan agar
  tidak menggerogoti saldo (sisa 38.000, tercatat).
- Lihat juga: audit backend #1–#2 (definisi `refund` = increment?).

### D19 — Anomali token sesaat (TERJAWAB — bukan bug app)
- Gejala awal: 2× `POST payment-methods → 401 auth=KOSONG` di proxy.
- Investigasi: token id=13 valid (`last_used_at` update, `/user` 200);
  server+proxy 200 untuk token fresh di semua jalur.
- Kesimpulan: request KOSONG itu **curl diagnosis milik sendiri**
  (tanpa header), bukan dari app. Tidak ada token-wipe liar.
- Tindak lanjut: percobaan hardening `await token` di get/post
  **di-revert** — menggantung widget test (fake async + MethodChannel)
  dan tidak diperlukan (invariant: `tryAutoLogin`/`login` selalu mengisi
  `_token` sebelum request apapun — terverifikasi di kode).

### D20 — Emulator kehabisan RAM (INFRA)
- `lowmemorykiller`: "min watermark breached" → proses app dibunuh sistem
  saat cold start. Bukan crash aplikasi (tanpa FATAL/Dart exception).
- Mitigasi: reboot emulator; cold start debug ±1 menit adalah normal.

## C. Mismatch backend untuk pengguna (dari audit read-only)

| # | Masalah | Dampak mobile | Rekomendasi |
|---|---------|---------------|-------------|
| B1 | Enum deposit (D18) | use = 500 | samakan enum + transaksi DB |
| B2 | `deposit refund` = increment | definisi bisnis ambigu | konfirmasi: refund = arus keluar? |
| B3 | `shifts.status` `active` vs `open` | shift lama tak terbaca; risiko shift ganda | migrasi data `active→open` |
| B4 | `cash_drawer_transactions.shift_id` | refund tanpa shift = 500 bila migrasi nullable belum jalan | pastikan migrasi jalan |
| B5 | `ensurePosAbility` hanya di store/syncBatch | token tanpa ability bisa baca/tutup shift | satukan guard |
| B6 | `orders/today` tanpa limit | outlet ramai bisa timeout | samakan limit/pagination |
| B7 | syncBatch menghilangkan deposit/cicilan/voucher/notes | total online ≠ hitungan kasir offline | samakan payload |
| B8 | Pajak mobile selalu 0 | laporan campur bila web kena pajak | dokumentasikan/flag eksplisit |
| B9 | `byBarcode` tanpa filter active + OR tak dikelompokkan | produk nonaktif bisa muncul | perbaiki query |
| B10 | Envelope `categories` vs `data` | klien handle dua kunci (sudah) | samakan bila sempat |
| B11 | Customer create tanpa cek outlet + show filter order | user bisa buat tapi tak bisa lihat | pakai respons 201 langsung (klien sudah) |
| B12 | `order_type` dinamis dari SystemSetting | hardcode enum berisiko | klien fallback `walk_in` (sudah) |
| B13 | `client_uuid` lookup beda scope store vs syncBatch | duplikat lewat exception (hasil akhir sama) | satukan `withoutGlobalScope` |
| B14 | Webhook marketplace tanpa auth default | spam INSERT | set token prod + required |
| B15 | `OrderPolicy@delete` tanpa cek outlet | refund lintas outlet | perketat bila sensitif |

## D. Observasi minor (bukan defect)

- O1: badge stok kartu POS tidak refresh otomatis pasca-checkout (perlu
  kembali/buka ulang untuk angka terbaru). P2 kosmetik.
- O2: kartu Aksi Cepat Beranda besar (boros ruang, mudah disentuh). Selera.
- O3: splash hanya logo (tanpa tagline/spinner terlihat) — cek `main.dart`
  dua fase splash sebelum klaim.
- O4: shift expected_cash hanya menghitung transaksi dalam rentang shift
  (order sebelum shift dibuka tidak masuk harapan) — benar secara sistem,
  UI menjelaskan rumus dengan tepat. Bukan bug.
