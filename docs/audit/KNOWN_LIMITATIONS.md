# KNOWN LIMITATIONS (jujur, beralasan, berlangkah lanjut)

1. Deposit `use`/`refund`: 500 backend (D18/B1–B2). Langkah: migrasi enum
   + transaksi DB di repo Laravel (butuh pemilik backend).
2. Cetak fisik & scan kamera: NOT VERIFIED (tanpa perangkat).
3. Periode laporan non-hari-ini & roles non-owner: belum E2E (terbuka).
4. `orders/today` tanpa pagination server (B6) — tangani client-side.
5. `sync-batch` subset payload (B7) — kasbon/voucher offline bisa selisih.
6. Pajak mobile selalu 0 (B8) — campur dengan web bila web berpajak.
7. Respons dev-server terpotong (D17) — hanya artefak uji lokal + proxy.
8. Cold start debug lambat di emulator RAM kecil (bukan crash).
9. Gambar produk seed memakai foto acak (data demo backend, bukan app).
10. Splash hanya logo (tanpa tagline/spinner terlihat) — backlog kosmetik.
