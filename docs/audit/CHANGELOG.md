# CHANGELOG (sesi refresh E2E)

## Unreleased (di atas `59cc79c`, siap commit)

- `offline_sync_service`: tabel `payment_methods` (sqlite v5) +
  `cachePaymentMethods`/`getCachedPaymentMethods` (D16).
- `payment_dialog`: fallback cache metode saat `ApiNetworkException` +
  caption mode-offline; refactor raw/list (tanpa ubah perilaku online).
- `offline_sync_test`: regression test round-trip + replace cache.
- Investigasi revert: hardening `await token` di get/post DIBATALKAN
  (menggantung widget test; invariant restore/login sudah menjamin).
- Dokumen: `docs/audit/` (12 file) + pembaruan audit utama.

## `59cc79c` — fix temuan E2E: navigasi outlet dobel + guard context.mounted
## `b512e28` — feat config: `--dart-define=API_BASE_URL` + cleartext debug-only
## `5df8aba` — docs: hasil uji asap emulator + screenshot
(ringkasan; riwayat penuh: `git log`)
