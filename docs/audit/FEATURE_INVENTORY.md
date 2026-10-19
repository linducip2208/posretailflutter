# FEATURE INVENTORY — menu & modul final (Flutter)

Bahasa UI default Indonesia (`lib/l10n/`, + Inggris). Zona operasional:
waktu server; format tanggal `id_ID`.

## Navigasi

Splash → (auto-login) → OutletGate → [pilih outlet] → Dashboard 5 tab:
Beranda · Transaksi · Produk · Laporan · Lainnya (+Lainnya: Operasional,
Perangkat & Akun, Informasi).

## Matriks menu

| Menu | Route/screen | Peran | API / operasi lokal | States | Aksi nyata |
|------|--------------|-------|---------------------|--------|------------|
| Beranda | HomeScreen | semua role login | today, forecast | skeleton/error+retry/empty | ringkasan, quick action, sinkron card, stok, transaksi terakhir |
| Transaksi (POS) | PosScreen | kasir+ (pos-access) | categories, products, barcode, orders, customers | loading/error+retry/offline-banner/antrean | search debounce, varian, qty stepper, pelanggan, kasbon DP, checkout idempoten, struk |
| Produk | ProductListScreen | semua | products, categories | loading/offline-banner/error+retry/empty | search, filter kategori, infinite scroll, detail read-only |
| Laporan | ReportScreen | semua (data outlet aktif) | history, payment-methods | loading/error+retry wajib, catatan 500/93hr | periode, 4 metrik, rekap metode, terlaris, daftar |
| Riwayat | OrdersScreen | semua | history | loading/error+retry/empty | search, filter periode, deep-link detail |
| Detail order | OrderDetailScreen | semua; refund butuh `hapus-transaksi`/`*` | show, refund, print/share PDF | loading/error+retry | pembayaran, cetak/share ulang, refund parsial + alasan |
| Pelanggan | CustomerListScreen | semua | customers CRUD-terbatas, deposits | loading/error+retry/empty, validasi | search, tambah, detail, topup/pakai/refund deposit |
| Shift Kasir | ShiftScreen | kasir+ | shifts open/close | loading/error+retry | kas awal/akhir, selisih, cegah shift ganda (server) |
| Sinkronisasi | SyncScreen | semua | sync-batch via service | summary pending/failed, error per item | retry force, hapus item, badge count |
| Peringatan Stok | StockAlertScreen | semua | forecast | loading/error+retry/empty | daftar low-stock + saran order |
| Printer | PrinterScreen | semua | BLE lokal; PDF/share fallback | scanning/error/empty | scan, connect, cetak 80mm, bagikan PDF |
| Ganti Outlet | OutletSelectionScreen | multi-outlet | outlets | empty | pilih + persist; reset data relevan |
| Profil | ProfileScreen | semua | lokal (AuthProvider) | — | info user/outlet |
| Pengaturan | SettingsScreen | semua | lokal + baseUrl tampil | — | bahasa, info server/versi |
| Bantuan & Tentang | AboutScreen | semua | — | — | info app, antrean offline |
| Keluar | — | semua | logout (server best-effort + clear lokal) | konfirmasi | hapus kredensial + state |

## Sengaja TIDAK ada (backend tak mendukung / web-only)

CRUD produk, opname/transfer/adjustment stok, hold/recall order,
split bill UI, voucher preview, gateway QRIS, purchasing/supplier,
notifikasi. Semua tercatat di API_CONTRACT; tidak ada tombol palsu
(audit statis: tidak ada `onPressed` kosong).
