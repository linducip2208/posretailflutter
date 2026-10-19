# FEATURE SCORECARD — POS Retail Flutter

Skema per fitur (total 100): perilaku & aturan bisnis 25 · integrasi API/DB 20 ·
error/loading/empty/offline 15 · security & permission 15 · automated tests 15 ·
UI/UX & aksesibilitas 10.

Aturan: tanpa bukti = tanpa poin penuh. NOT VERIFIED/BLOCKED tidak bisa 100.
E2E lokal melawan backend `pos_retail_e2e` via proxy (lihat BASELINE.md).

## Skor per fitur

| ID | Fitur | F(25) | I(20) | E(15) | S(15) | T(15) | U(10) | Total | Status | Bukti kunci |
|----|-------|-------|-------|-------|-------|-------|-------|-------|--------|-------------|
| F01 | Login/logout + lifecycle 401 | 25 | 20 | 15 | 15 | 12 | 9 | **96** | PASS | E2E: login 200→dashboard; hapus token DB→401→login rapi; unit+widget login |
| F02 | Pilih outlet + isolasi | 25 | 20 | 13 | 13 | 10 | 9 | **90** | PASS | E2E outlet Toko Pusat; `?outlet_id=1` di semua query; cache produk per outlet. −S: create-customer tanpa cek outlet (server); −T: tanpa widget test seleksi |
| F03 | Beranda/dashboard | 23 | 20 | 15 | 15 | 10 | 8 | **91** | PASS | E2E: omzet/transaksi sinkron dgn DB; quick action; sync card. −T: agregasi tanpa unit test khusus |
| F04 | POS + checkout online | 25 | 20 | 15 | 15 | 13 | 9 | **97** | PASS | E2E order 501 (order+item+payment+stok+mutasi cocok DB); idempoten `client_uuid`; anti double-tap |
| F05 | Antrean offline + sync | 25 | 20 | 15 | 15 | 15 | 9 | **99** | PASS | E2E: offline→pending badge 1→auto sync→order 502; 2×sync-batch→1 order (idempoten); unit: batch/retry/duplicate/backoff |
| F06 | Metode bayar + dialog (split/kasbon/kembalian) | 25 | 20 | 15 | 12 | 15 | 9 | **96** | PASS | E2E tunai pas; split UI; kasbon DP; cache metode offline (D16). −S: non-tunai offline ikut antrean tanpa verifikasi dana |
| F07 | Riwayat + detail + refund | 25 | 20 | 15 | 13 | 10 | 9 | **92** | PASS | E2E: order tampil + badge antrean; refund 201→RT-20261019-0001 + stok 119→120 + mutasi `in via return`. −S: policy outlet di server; −T: tanpa widget test refund |
| F08 | Katalog produk + search/filter | 23 | 20 | 15 | 15 | 12 | 9 | **94** | PASS | E2E: 50 item + kategori + search 1 hasil; barcode endpoint ada (belum E2E scan kamera). −F: scan kamera NOT VERIFIED |
| F09 | Laporan + produk terlaris | 23 | 20 | 15 | 15 | 13 | 9 | **95** | PASS | E2E: omzet 1.726.681 termasuk order sync; metode ter-mapping; batas 93hr/500 ditandai. −F: periode non-hari-ini belum E2E |
| F10 | Pelanggan + deposit | 20 | 15 | 15 | 12 | 10 | 9 | **81** | PARTIAL | E2E: create 201 + topup 50rb ✓. −F/−I: `use` = 500 backend (D18, BLOCKED); `refund` ambigu (B2) |
| F11 | Shift buka/tutup + selisih | 25 | 20 | 13 | 13 | 8 | 9 | **88** | PASS | E2E: open 201 + close 200 + difference 12000 cocok DB. −E: tanpa state shift-ganda khusus; −T: tanpa widget test |
| F12 | Struk: PDF/share + printer BLE | 15 | 12 | 12 | 12 | 8 | 8 | **67** | PARTIAL | PDF/share Hanya UI teruji; cetak fisik NOT VERIFIED (tanpa perangkat). Jangan klaim cetak berhasil |
| F13 | Stok menipis + forecast | 23 | 20 | 15 | 15 | 8 | 9 | **90** | PASS | E2E: empty state "Stok aman" benar; endpoint weeks/outlet. −T: agregasi tanpa unit test |
| F14 | Layar Sinkronisasi (retry/hapus) | 23 | 20 | 15 | 15 | 12 | 9 | **94** | PASS | summary pending/failed, retry force, hapus item; unit backoff/attempts. −F: partial-batch-failure UI belum E2E |
| F15 | Pengaturan/bahasa/profil/tentang | 25 | 18 | 13 | 15 | 8 | 9 | **88** | PASS | id/en persist; baseUrl tampil; logout bersih. −I: tanpa API profil khusus; −T: tanpa widget test |

## Rekap

- Rata-rata 15 fitur: **≈90/100**. Tertinggi F05 (99), terendah F12 (67).
- Tidak ada 100: sesuai aturan (perangkat printer tak tersedia; periode
  laporan non-default & scan kamera belum E2E; deposit `use` blocked server).
- Yang harus naik sebelum rilis: F12 butuh printer fisik; F10 butuh fix
  backend D18; F11/F07/F02 butuh widget test tambahan (akumulasi +9 poin).

## Peta bukti → file

- E2E DB: `pos_retail_e2e` (orders 501/502, returns RT-20261019-0001,
  shifts 13, customers 201, stock_movements out/in).
- Proxy log: `e2e-proxy.log` (temp) — method/path/query/status/bytes/auth-tail.
- Screenshot: `e2e-*.png` (temp; pilihan dipindah ke `docs/screenshots/`).
- Unit/widget: `test/` 11 file, 54 test hijau (lihat TEST_RESULTS.md).
