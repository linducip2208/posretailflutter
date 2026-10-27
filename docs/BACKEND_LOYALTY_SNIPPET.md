# Snippet Backend Laravel — Loyalitas & Promo (siap tempel)

Ikuti kontrak `docs/API_CONTRACT_MOBILE_PARITY.md` grup 8 (Diskon) dan
grup 9 (Loyalitas). Semua route di bawah prefix `api/v1` dengan
middleware `auth:sanctum` (+ scope outlet bila relevan).

## 1. Migrations

```php
// database/migrations/2026_10_27_000001_create_discounts_table.php
Schema::create('discounts', function (Blueprint $table) {
    $table->id();
    $table->string('name');
    $table->enum('type', ['percent', 'fixed', 'buy_x_get_y'])->default('percent');
    $table->decimal('value', 15, 2)->default(0);
    $table->decimal('min_purchase', 15, 2)->default(0);
    $table->unsignedInteger('buy_qty')->default(0);
    $table->unsignedInteger('get_qty')->default(0);
    $table->timestamp('start_at')->nullable();
    $table->timestamp('end_at')->nullable();
    $table->boolean('active')->default(true);
    $table->timestamps();
});

// database/migrations/2026_10_27_000002_create_loyalty_tables.php
Schema::create('loyalty_rewards', function (Blueprint $table) {
    $table->id();
    $table->string('name');
    $table->unsignedInteger('points_cost')->default(0);
    $table->unsignedInteger('stock')->default(0);
    $table->boolean('active')->default(true);
    $table->timestamps();
});

// Ledger poin: satu baris per earn/redeem (audit trail, jangan update-in-place).
Schema::create('loyalty_points', function (Blueprint $table) {
    $table->id();
    $table->foreignId('customer_id')->constrained()->cascadeOnDelete();
    $table->foreignId('outlet_id')->nullable()->constrained()->nullOnDelete();
    $table->enum('type', ['earn', 'redeem']);
    $table->integer('points'); // positif untuk earn, negatif untuk redeem
    $table->foreignId('order_id')->nullable()->constrained()->nullOnDelete();
    $table->foreignId('reward_id')->nullable()->constrained('loyalty_rewards')->nullOnDelete();
    $table->timestamps();
});

// database/migrations/2026_10_27_000003_create_customer_groups_table.php
Schema::create('customer_groups', function (Blueprint $table) {
    $table->id();
    $table->string('name'); // Regular | Member | Reseller
    $table->string('code')->unique()->nullable();
    $table->decimal('discount_percent', 5, 2)->default(0);
    $table->decimal('min_spent', 15, 2)->default(0); // syarat auto-upgrade
    $table->timestamps();
});
// + tambahkan customers.group_id nullable -> constrained('customer_groups')->nullOnDelete()
//   dan customers.total_spent decimal(15,2) default 0 untuk auto-upgrade.
```

## 2. Routes (`routes/api.php`)

```php
Route::prefix('v1')->middleware('auth:sanctum')->group(function () {
    Route::get('discounts', [DiscountController::class, 'index']);
    Route::post('discounts', [DiscountController::class, 'store']);
    Route::put('discounts/{discount}', [DiscountController::class, 'update']);

    Route::get('loyalty-rewards', [LoyaltyRewardController::class, 'index']);
    Route::post('loyalty-rewards', [LoyaltyRewardController::class, 'store']);
    Route::put('loyalty-rewards/{reward}', [LoyaltyRewardController::class, 'update']);

    Route::get('loyalty-points', [LoyaltyPointController::class, 'show']); // ?customer_id=
    Route::post('loyalty-points/redeem', [LoyaltyPointController::class, 'redeem']);

    Route::get('customer-groups', [CustomerGroupController::class, 'index']);
});
```

## 3. Controllers (ringkas)

```php
class DiscountController extends Controller
{
    public function index(Request $r) {
        $q = Discount::query()
            ->when($r->type, fn ($q) => $q->where('type', $r->type))
            ->when($r->has('active'), fn ($q) => $q->where('active', (bool) $r->active));
        return response()->json(['data' => $q->get()]);
    }
    public function store(Request $r) {
        $v = $r->validate([
            'name' => 'required|string|max:255',
            'type' => 'required|in:percent,fixed,buy_x_get_y',
            'value' => 'nullable|numeric|min:0',
            'min_purchase' => 'nullable|numeric|min:0',
            'buy_qty' => 'nullable|integer|min:0',
            'get_qty' => 'nullable|integer|min:0',
            'start_at' => 'nullable|date', 'end_at' => 'nullable|date',
            'active' => 'nullable|boolean',
        ]);
        if (($v['type'] ?? '') === 'percent' && ($v['value'] ?? 0) > 100) {
            return response()->json(['message' => 'Diskon persen maksimal 100.'], 422);
        }
        return response()->json(['data' => Discount::create($v)], 201);
    }
    public function update(Request $r, Discount $discount) {
        $discount->update($r->validate([
            'name' => 'sometimes|string|max:255',
            'type' => 'sometimes|in:percent,fixed,buy_x_get_y',
            'value' => 'nullable|numeric|min:0',
            'min_purchase' => 'nullable|numeric|min:0',
            'buy_qty' => 'nullable|integer|min:0',
            'get_qty' => 'nullable|integer|min:0',
            'start_at' => 'nullable|date', 'end_at' => 'nullable|date',
            'active' => 'nullable|boolean',
        ]));
        return response()->json(['data' => $discount]);
    }
}

class LoyaltyPointController extends Controller
{
    public function show(Request $r) {
        $r->validate(['customer_id' => 'required|exists:customers,id']);
        $earned = LoyaltyPoint::where('customer_id', $r->customer_id)->where('type', 'earn')->sum('points');
        $redeemed = -LoyaltyPoint::where('customer_id', $r->customer_id)->where('type', 'redeem')->sum('points');
        $customer = Customer::find($r->customer_id);
        return response()->json(['data' => [
            'customer_id' => (int) $r->customer_id,
            'customer_name' => $customer?->name,
            'earned' => (int) $earned,
            'redeemed' => (int) $redeemed,
            'balance' => max(0, (int) $earned - (int) $redeemed),
        ]]);
    }

    public function redeem(Request $r) {
        $v = $r->validate([
            'customer_id' => 'required|exists:customers,id',
            'reward_id' => 'required|exists:loyalty_rewards,id',
        ]);
        return DB::transaction(function () use ($v) {
            $reward = LoyaltyReward::lockForUpdate()->findOrFail($v['reward_id']);
            if (! $reward->active) {
                return response()->json(['message' => 'Reward tidak aktif.'], 422);
            }
            if ($reward->stock <= 0) {
                return response()->json(['message' => 'Stok reward habis.'], 422);
            }
            $earned = LoyaltyPoint::where('customer_id', $v['customer_id'])->where('type', 'earn')->sum('points');
            $redeemed = -LoyaltyPoint::where('customer_id', $v['customer_id'])->where('type', 'redeem')->sum('points');
            if ($earned - $redeemed < $reward->points_cost) {
                return response()->json(['message' => 'Saldo poin tidak cukup.'], 422);
            }
            LoyaltyPoint::create([
                'customer_id' => $v['customer_id'],
                'type' => 'redeem',
                'points' => -$reward->points_cost,
                'reward_id' => $reward->id,
            ]);
            $reward->decrement('stock');
            return response()->json(['message' => 'Reward berhasil diredeem.']);
        });
    }
}

class CustomerGroupController extends Controller
{
    // Read-only sesuai kontrak: urut min_spent agar alur upgrade terbaca.
    public function index() {
        return response()->json(['data' => CustomerGroup::withCount('customers')->orderBy('min_spent')->get()]);
    }
}
```

## 4. Poin auto-earned saat POST /orders lunas (hook)

Jangan hitung poin di client. Tambahkan di `OrderController@store`
(atau observer `Order::created` / service `CheckoutService`) setelah
order berstatus `paid`/lunas, dalam transaksi yang sama:

```php
// Setelah order lunas:
if ($order->customer_id && $order->payment_status === 'paid') {
    // Contoh aturan: 1 poin per Rp10.000 (sesuaikan dengan web /admin/loyalty-rewards).
    $points = (int) floor($order->grand_total / 10000);
    if ($points > 0) {
        LoyaltyPoint::create([
            'customer_id' => $order->customer_id,
            'outlet_id' => $order->outlet_id,
            'type' => 'earn',
            'points' => $points,
            'order_id' => $order->id,
        ]);
        // Auto-upgrade grup berdasar total belanja:
        $total = Order::where('customer_id', $order->customer_id)
            ->where('payment_status', 'paid')->sum('grand_total');
        $group = CustomerGroup::where('min_spent', '<=', $total)->orderByDesc('min_spent')->first();
        if ($group) {
            Customer::whereKey($order->customer_id)->update([
                'group_id' => $group->id, 'total_spent' => $total,
            ]);
        }
    }
}
```

Catatan: redeem memvalidasi saldo + stok di dalam `DB::transaction`
dengan `lockForUpdate` agar dua redeem bersamaan tidak double-spend.
Envelope sukses `{data, meta?, message?}`; error `422 {message, errors}`,
`404` tidak ketemu — sama seperti endpoint lama.
