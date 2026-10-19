# SECURITY REVIEW — Flutter (statis + perilaku E2E)

## Hasil pemeriksaan

| Area | Status | Catatan |
|------|--------|---------|
| Secret hardcoded | ✅ bersih | audit statis: tanpa API key/password/private key; base URL produksi default bukan rahasia; token hanya di secure storage |
| Token lifecycle | ✅ | Keystore/Keychain; 401 → wipe + logout + login; expiry teruji E2E |
| Input validation | ✅ | login, pelanggan (nama wajib), deposit amount, shift cash, checkout (server validasi ulang; harga dari server) |
| SQL injection | ✅ | tanpa SQL mentah ke server; sqlite lokal parameter binding (batch insert map) |
| XSS/HTML | N/A | tidak ada WebView/HTML render |
| IDOR/lintas outlet | ⚠️ klien benar, server sebagian | klien selalu kirim outlet_id + cache per outlet; server: customer-create & policy-delete tanpa cek outlet (B11/B15) → diserahkan backend |
| Permission | ✅ klien / ⚠️ server | refund hanya tampilkan aksi; izin ditegakkan server (`hapus-transaksi`); ability `pos-access` tak konsisten di semua endpoint (B5) |
| Rate limiting | ✅ dipatuhi | login throttle 10/mnt diuji sekali (gagal) lalu hindari; API 120/mnt tak tersentuh |
| Logging sensitif | ✅ | proxy log hanya ekor token 8 char; tanpa password di log/commit/screenshot |
| Transport | ✅ | HTTPS produksi; HTTP polos HANYA build debug → 10.0.2.2 (manifest debug) |
| Logout | ✅ | clear token + prefs user/outlet; cart dikosongkan |
| Webhook/marketplace | N/A mobile | risiko B14 dicatat untuk backend |

## Rekomendasi ke backend (bukan tugas repo ini)

B1–B5, B11, B14, B15 (lihat DEFECTS.md §C).
