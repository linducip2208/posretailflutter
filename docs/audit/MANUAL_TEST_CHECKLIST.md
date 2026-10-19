# MANUAL TEST CHECKLIST — perangkat fisik / staging

## Telah lolos (emulator + backend lokal)

- [x] Login gagal → pesan; login sukses → outlet → dashboard
- [x] POS: grid, kategori, search, tambah, stepper, hapus
- [x] Checkout tunai pas → struk sukses + DB cocok
- [x] Riwayat → detail → refund + konfirmasi → stok pulih
- [x] Shift open → close + selisih
- [x] Pelanggan cari/tambah + topup deposit
- [x] Offline: badge, cache produk/metode, antrean, auto-sync, idempoten
- [x] Laporan + terlaris + rekap metode
- [x] Token mati → login ulang

## Wajib sebelum produksi (butuh perangkat/akses)

- [ ] Cetak struk fisik 58mm + 80mm (BLE thermal): pairing, putus, retry,
      karakter Indonesia, cetak ulang ≠ order baru
- [ ] Scan barcode kamera + input manual (varian barcode)
- [ ] Splash/ikon di API 26–35 + tablet + text-scaling besar + landscape POS
- [ ] Printer permission flow (Android 12+ BLUETOOTH_SCAN/CONNECT)
- [ ] Interupsi: telepon masuk saat bayar; rotasi saat dialog; process death
      dengan antrean pending (restart → sync)
- [ ] Multi-outlet 2 kasir bersamaan (nomor antrean + stok race)
- [ ] Staging HTTPS + token expiry nyata + throttle 429
- [ ] Deposit `use`/`refund` setelah fix backend D18/B2
- [ ] Refund oleh role non-owner berizin `hapus-transaksi` (kasir ditolak?)
