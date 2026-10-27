# Snippet Backend — Retur, Hold, Cicilan/DP (Laravel, siap tempel)

> Scope: grup 6 (Retur), 7 (Hold), 11 (Cicilan/DP) dari
> `docs/API_CONTRACT_MOBILE_PARITY.md`. Prefix `api/v1`, middleware
> `auth:sanctum`. Status string persis `pending|approved|rejected`.

## 1. Migration

```php
// database/migrations/2026_10_27_000001_create_sales_ops_tables.php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('returns', function (Blueprint $t) {
            $t->id();
            $t->foreignId('order_id')->constrained()->cascadeOnDelete();
            $t->foreignId('outlet_id')->constrained()->cascadeOnDelete();
            $t->string('status')->default('pending'); // pending|approved|rejected
            $t->text('reason')->nullable();
            $t->string('reject_reason')->nullable();
            $t->timestamps();
            $t->index(['outlet_id', 'status']);
        });

        Schema::create('return_items', function (Blueprint $t) {
            $t->id();
            $t->foreignId('return_id')->constrained('returns')->cascadeOnDelete();
            $t->foreignId('product_id')->constrained()->restrictOnDelete();
            $t->integer('qty');
            $t->timestamps();
        });

        Schema::create('held_orders', function (Blueprint $t) {
            $t->id();
            $t->foreignId('outlet_id')->constrained()->cascadeOnDelete();
            $t->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $t->string('label');
            $t->json('cart')->nullable(); // {items:[{product_id,qty,price}], customer_id?, note?}
            $t->timestamp('expires_at');
            $t->timestamps();
            $t->index(['outlet_id', 'expires_at']);
        });

        Schema::create('installments', function (Blueprint $t) {
            $t->id();
            $t->foreignId('order_id')->constrained()->cascadeOnDelete();
            $t->string('plan'); // weekly|biweekly|monthly
            $t->integer('count');
            $t->decimal('down_payment', 15, 2)->default(0);
            $t->decimal('due_amount', 15, 2)->default(0);
            $t->string('payment_status')->default('pending'); // paid|partial|pending
            $t->timestamps();
            $t->index('order_id');
        });
        // Pembayaran cicilan/DP memakai tabel payments yang sudah ada
        // (order_id, payment_method_id, amount). Bila belum ada:
        // Schema::create('payments', fn (Blueprint $t) => ...);
    }

    public function down(): void
    {
        Schema::dropIfExists('installments');
        Schema::dropIfExists('held_orders');
        Schema::dropIfExists('return_items');
        Schema::dropIfExists('returns');
    }
};
```

## 2. Model ringkas

```php
// app/Models/ReturnOrder.php  (table: returns)
class ReturnOrder extends Model
{
    protected $table = 'returns';
    protected $fillable = ['order_id', 'outlet_id', 'status', 'reason', 'reject_reason'];
    public function items() { return $this->hasMany(ReturnItem::class, 'return_id'); }
    public function order() { return $this->belongsTo(Order::class); }
}

// app/Models/ReturnItem.php  (table: return_items)
class ReturnItem extends Model
{
    protected $fillable = ['return_id', 'product_id', 'qty'];
    public function product() { return $this->belongsTo(Product::class); }
}

// app/Models/HeldOrder.php
class HeldOrder extends Model
{
    protected $fillable = ['outlet_id', 'user_id', 'label', 'cart', 'expires_at'];
    protected $casts = ['cart' => 'array', 'expires_at' => 'datetime'];
}

// app/Models/Installment.php
class Installment extends Model
{
    protected $fillable = ['order_id', 'plan', 'count', 'down_payment', 'due_amount', 'payment_status'];
}
```

## 3. Controllers

```php
// app/Http/Controllers/Api/V1/ReturnController.php
namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\ReturnOrder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ReturnController extends Controller
{
    public function index(Request $r)
    {
        $q = ReturnOrder::with(['items.product', 'order'])
            ->when($r->outlet_id, fn ($q) => $q->where('outlet_id', $r->outlet_id))
            ->when($r->status, fn ($q) => $q->where('status', $r->status))
            ->latest();
        return response()->json([
            'data' => $q->paginate($r->integer('per_page', 50))->through(fn ($x) => $this->shape($x)),
            'meta' => ['total' => $q->count(), 'last_page' => 1],
        ]);
        // Catatan: pakai $page->toArray() untuk meta {total,last_page} yang akurat.
    }

    public function store(Request $r)
    {
        $v = $r->validate([
            'order_id' => 'required|exists:orders,id',
            'items' => 'required|array|min:1',
            'items.*.product_id' => 'required|exists:products,id',
            'items.*.qty' => 'required|integer|min:1',
            'reason' => 'required|string|max:1000',
        ]);
        $order = \App\Models\Order::findOrFail($v['order_id']);
        $ret = ReturnOrder::create([
            'order_id' => $order->id,
            'outlet_id' => $order->outlet_id, // scope server, jangan percaya client
            'status' => 'pending',
            'reason' => $v['reason'],
        ]);
        foreach ($v['items'] as $it) {
            $ret->items()->create(['product_id' => $it['product_id'], 'qty' => $it['qty']]);
        }
        return response()->json(['data' => $this->shape($ret->load('items.product'))], 201);
    }

    public function show(ReturnOrder $return)
    {
        return response()->json(['data' => $this->shape($return->load(['items.product', 'order']))]);
    }

    public function approve(ReturnOrder $return)
    {
        abort_if($return->status !== 'pending', 409, 'Retur sudah diproses.');
        DB::transaction(function () use ($return) {
            $return->update(['status' => 'approved']);
            foreach ($return->items as $it) {
                $stock = \App\Models\Stock::where('outlet_id', $return->outlet_id)
                    ->where('product_id', $it->product_id)->lockForUpdate()->first();
                $before = $stock?->qty ?? 0;
                $after = $before + $it->qty;
                if ($stock) { $stock->update(['qty' => $after]); }
                else { \App\Models\Stock::create(['outlet_id' => $return->outlet_id, 'product_id' => $it->product_id, 'qty' => $after]); }
                \App\Models\StockMovement::create([ // audit trail wajib
                    'outlet_id' => $return->outlet_id,
                    'product_id' => $it->product_id,
                    'type' => 'return_in',
                    'qty_before' => $before,
                    'qty_after' => $after,
                    'qty_change' => $it->qty,
                    'reference_type' => 'return',
                    'reference_id' => $return->id,
                ]);
            }
        });
        return response()->json(['data' => $this->shape($return->fresh()->load('items.product'))]);
    }

    public function reject(Request $r, ReturnOrder $return)
    {
        abort_if($return->status !== 'pending', 409, 'Retur sudah diproses.');
        $v = $r->validate(['reason' => 'nullable|string|max:1000']);
        $return->update(['status' => 'rejected', 'reject_reason' => $v['reason'] ?? null]);
        return response()->json(['data' => $this->shape($return->fresh()->load('items.product'))]);
    }

    private function shape(ReturnOrder $x): array
    {
        return [
            'id' => $x->id, 'order_id' => $x->order_id,
            'order_number' => $x->order?->number, 'outlet_id' => $x->outlet_id,
            'status' => $x->status, 'reason' => $x->reason,
            'created_at' => $x->created_at?->toIso8601String(),
            'items' => $x->items->map(fn ($i) => [
                'product_id' => $i->product_id,
                'product_name' => $i->product?->name,
                'qty' => $i->qty,
            ])->values(),
        ];
    }
}
```

```php
// app/Http/Controllers/Api/V1/HeldOrderController.php
class HeldOrderController extends Controller
{
    public function index(Request $r)
    {
        $rows = HeldOrder::where('outlet_id', $r->outlet_id)
            ->where('expires_at', '>', now()) // auto-expire 24 jam: kadaluwarsa tak tampil
            ->latest()->get();
        return response()->json(['data' => $rows]);
    }

    public function store(Request $r)
    {
        $v = $r->validate([
            'outlet_id' => 'required|exists:outlets,id',
            'label' => 'required|string|max:120',
            'cart' => 'nullable|array',
        ]);
        $hold = HeldOrder::create([
            'outlet_id' => $v['outlet_id'], 'user_id' => $r->user()->id,
            'label' => $v['label'], 'cart' => $v['cart'] ?? ['items' => []],
            'expires_at' => now()->addHours(24),
        ]);
        return response()->json(['data' => $hold], 201);
    }

    public function resume(HeldOrder $heldOrder)
    {
        abort_if($heldOrder->expires_at->isPast(), 410, 'Transaksi hold sudah kedaluwarsa.');
        return response()->json(['data' => $heldOrder]); // client buka cart di kasir
    }

    public function destroy(HeldOrder $heldOrder)
    {
        $heldOrder->delete();
        return response()->json(['message' => 'Dihapus.']);
    }
}
```

```php
// app/Http/Controllers/Api/V1/InstallmentController.php
class InstallmentController extends Controller
{
    public function index(Request $r)
    {
        $rows = \App\Models\Installment::where('order_id', $r->order_id)->latest()->get();
        return response()->json(['data' => $rows]);
    }

    public function storePlan(Request $r, \App\Models\Order $order)
    {
        $v = $r->validate([
            'plan' => 'required|in:weekly,biweekly,monthly',
            'count' => 'required|integer|min:1|max:60',
            'down_payment' => 'nullable|numeric|min:0',
        ]);
        $dp = (float) ($v['down_payment'] ?? 0);
        $due = max(0, (float) $order->total - $dp - (float) $order->paid_amount);
        $ins = \App\Models\Installment::create([
            'order_id' => $order->id, 'plan' => $v['plan'], 'count' => $v['count'],
            'down_payment' => $dp, 'due_amount' => $due,
            'payment_status' => $due <= 0 ? 'paid' : 'partial',
        ]);
        if ($dp > 0) {
            $order->payments()->create(['payment_method_id' => $r->payment_method_id, 'amount' => $dp]);
            $order->update(['paid_amount' => (float) $order->paid_amount + $dp]);
        }
        return response()->json(['data' => $ins], 201);
    }

    public function pay(Request $r, \App\Models\Order $order)
    {
        $v = $r->validate([
            'amount' => 'required|numeric|min:1',
            'payment_method_id' => 'nullable|exists:payment_methods,id',
        ]);
        $order->payments()->create([
            'payment_method_id' => $v['payment_method_id'] ?? null,
            'amount' => $v['amount'],
        ]);
        $paid = (float) $order->paid_amount + (float) $v['amount'];
        $order->update([
            'paid_amount' => $paid,
            'payment_status' => $paid >= (float) $order->total ? 'paid' : 'partial',
        ]);
        // Sinkronkan due_amount jadwal terakhir:
        $order->installments()->latest()->first()
            ?->update(['due_amount' => max(0, (float) $order->total - $paid)]);
        return response()->json(['data' => ['paid_amount' => $paid]], 201);
    }
}
```

## 4. Routes

```php
// routes/api.php
Route::prefix('v1')->middleware('auth:sanctum')->group(function () {
    Route::get('/returns', [ReturnController::class, 'index']);
    Route::post('/returns', [ReturnController::class, 'store']);
    Route::get('/returns/{return}', [ReturnController::class, 'show']);
    Route::post('/returns/{return}/approve', [ReturnController::class, 'approve']);
    Route::post('/returns/{return}/reject', [ReturnController::class, 'reject']);

    Route::get('/held-orders', [HeldOrderController::class, 'index']);
    Route::post('/held-orders', [HeldOrderController::class, 'store']);
    Route::post('/held-orders/{heldOrder}/resume', [HeldOrderController::class, 'resume']);
    Route::delete('/held-orders/{heldOrder}', [HeldOrderController::class, 'destroy']);

    Route::get('/installments', [InstallmentController::class, 'index']);
    Route::post('/orders/{order}/installments', [InstallmentController::class, 'storePlan']);
    Route::post('/orders/{order}/payments', [InstallmentController::class, 'pay']);
});
```

## 5. Scheduler — purge hold kedaluwarsa (opsional, index sudah memfilter)

```php
// app/Console/Kernel.php
$schedule->call(fn () => HeldOrder::where('expires_at', '<', now())->delete())->daily();
```

## 6. Checklist verifikasi

- [ ] Tanpa token → 401; salah outlet → 403/422 jujur.
- [ ] `outlet_id` retur diambil dari order di server (bukan input client).
- [ ] `approve` menulis `stock_movements` type `return_in` per item.
- [ ] Hold tak tampil setelah `expires_at`; purge harian jalan.
- [ ] `due_amount` + `payment_status: paid|partial|pending` konsisten setelah tiap `pay`.
