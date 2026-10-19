# RELEASE READINESS

## Keputusan: CONDITIONAL GO (staging) — NOT READY produksi

Syarat staging: backend `pos_retail_e2e`-paritas + printer fisik teruji +
fix D18 dari backend.

## Pintu kritis

| Pintu | Status |
|-------|--------|
| Analyzer + format + 54 test hijau | ✅ |
| Checkout online + refund + shift + sync idempoten (E2E) | ✅ |
| Tanpa tombol mati / data palsu (audit statis + E2E) | ✅ |
| Deposit `use` (D18 backend 500) | ❌ BLOCKED |
| Cetak fisik (tanpa perangkat) | ❌ NOT VERIFIED |
| Scan kamera fisik | ❌ NOT VERIFIED |
| Release build + smoke prod-URL (tanpa transaksi nyata) | ⏳ rebuild final sesi ini |

## Risiko rilis

- B1–B15 backend (khusus B1/B3/B4/B7 berdampak transaksi).
- `orders/today` tanpa limit (B6) di outlet ramai.
- Cold start debug ±1 mnt di emulator lemah (bukan crash).
