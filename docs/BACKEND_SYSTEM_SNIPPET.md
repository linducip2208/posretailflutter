# Snippet Backend Laravel — Users & Roles, Absensi, Laporan (grup 12–14)

Tempel ke backend Laravel (`routes/api/v1`, controller, migration).
Kontrak persis `docs/API_CONTRACT_MOBILE_PARITY.md` grup 12–14.
Envelope: `{ "data": ..., "meta": ...? }`, auth `auth:sanctum`,
scope `outlet_id` di-server, tanggal `YYYY-MM-DD`.

> Status mobile saat ini: semua endpoint di bawah ini 404
> (terverifikasi via probe). Layar Flutter menampilkan pesan
> 404 jujur + tombol Coba Lagi sampai backend live.

## 1. Migrations

```php
// database/migrations/xxxx_add_role_outlets_to_users.php
Schema::table('users', function (Blueprint $table) {
    $table->string('role')->default('kasir'); // owner|admin|manager|kasir|gudang
    $table->boolean('active')->default(true);
});

// Pivot bila belum ada (user bisa akses beberapa outlet).
Schema::create('outlet_user', function (Blueprint $table) {
    $table->id();
    $table->foreignId('user_id')->constrained()->cascadeOnDelete();
    $table->foreignId('outlet_id')->constrained()->cascadeOnDelete();
    $table->unique(['user_id', 'outlet_id']);
});

// database/migrations/xxxx_create_attendances_table.php
Schema::create('attendances', function (Blueprint $table) {
    $table->id();
    $table->foreignId('user_id')->constrained()->cascadeOnDelete();
    $table->foreignId('outlet_id')->constrained()->cascadeOnDelete();
    $table->date('date');
    $table->timestamp('clock_in')->nullable();
    $table->timestamp('clock_out')->nullable();
    $table->string('status')->default('hadir'); // hadir|terlambat|izin|sakit
    $table->timestamps();
    $table->unique(['user_id', 'date']);
});
```

## 2. Controllers (sketsa)

```php
// app/Http/Controllers/Api/V1/UserController.php
class UserController extends Controller
{
    public function index(Request $r) {
        $q = User::query()->with('outlets:id');
        if ($r->outlet_id) {
            $q->whereHas('outlets', fn ($w) => $w->where('outlets.id', $r->outlet_id));
        }
        if ($r->role) $q->where('role', $r->role);
        return response()->json(['data' => $q->paginate(50)->through(fn ($u) => [
            'id' => $u->id, 'name' => $u->name, 'email' => $u->email,
            'role' => $u->role, 'active' => (bool) $u->active,
            'outlet_ids' => $u->outlets->pluck('id'),
        ])]);
    }

    public function store(Request $r) {
        $v = $r->validate([
            'name' => 'required|string|max:100',
            'email' => 'nullable|email|unique:users,email',
            'password' => 'required|string|min:6',
            'role' => 'required|in:owner,admin,manager,kasir,gudang',
            'outlet_ids' => 'nullable|array',
            'outlet_ids.*' => 'exists:outlets,id',
        ]);
        $u = User::create([...$v, 'password' => Hash::make($v['password'])]);
        $u->outlets()->sync($v['outlet_ids'] ?? []);
        return response()->json(['data' => $u], 201);
    }

    public function update(Request $r, User $user) {
        $v = $r->validate([
            'name' => 'sometimes|string|max:100',
            'role' => 'sometimes|in:owner,admin,manager,kasir,gudang',
            'active' => 'sometimes|boolean',
            'outlet_ids' => 'sometimes|array',
        ]);
        $user->update($v);
        if (isset($v['outlet_ids'])) $user->outlets()->sync($v['outlet_ids']);
        return response()->json(['data' => $user->fresh()]);
    }

    public function roles() {
        return response()->json(['data' => [
            ['name' => 'owner'], ['name' => 'admin'], ['name' => 'manager'],
            ['name' => 'kasir'], ['name' => 'gudang'],
        ]]);
    }
}

// app/Http/Controllers/Api/V1/AttendanceController.php
class AttendanceController extends Controller
{
    public function index(Request $r) {
        $q = Attendance::query()->with('user:id,name')
            ->when($r->outlet_id, fn ($w) => $w->where('outlet_id', $r->outlet_id))
            ->when($r->date, fn ($w) => $w->whereDate('date', $r->date))
            ->latest('date');
        return response()->json(['data' => $q->paginate(50)->through(fn ($a) => [
            'id' => $a->id, 'user_id' => $a->user_id,
            'user_name' => $a->user->name ?? null,
            'outlet_id' => $a->outlet_id, 'date' => $a->date->toDateString(),
            'clock_in' => $a->clock_in?->toIso8601String(),
            'clock_out' => $a->clock_out?->toIso8601String(),
            'status' => $a->status,
        ])]);
    }

    public function clockIn(Request $r) {
        $r->validate(['outlet_id' => 'required|exists:outlets,id']);
        $today = now()->toDateString();
        $att = Attendance::firstOrCreate(
            ['user_id' => $r->user()->id, 'date' => $today],
            ['outlet_id' => $r->outlet_id, 'clock_in' => now(),
             // Status otomatis: terlambat bila lewat 09:00 lokal.
             'status' => now()->format('H:i') > '09:00' ? 'terlambat' : 'hadir'],
        );
        if ($att->wasRecentlyCreated === false && $att->clock_in) {
            return response()->json(['message' => 'Sudah clock-in hari ini.'], 409);
        }
        $att->update(['clock_in' => now(), 'outlet_id' => $r->outlet_id]);
        return response()->json(['data' => $att, 'message' => 'Clock-in tercatat']);
    }

    public function clockOut(Request $r) {
        $att = Attendance::where('user_id', $r->user()->id)
            ->whereDate('date', now()->toDateString())->first();
        if (!$att || !$att->clock_in) {
            return response()->json(['message' => 'Belum clock-in hari ini.'], 422);
        }
        $att->update(['clock_out' => now()]);
        return response()->json(['data' => $att, 'message' => 'Clock-out tercatat']);
    }
}

// Laporan: agregasi server-side (bukan hitung di client).
// GET /reports/purchases → total_cost, po_count, outstanding_po,
//   top_suppliers[] (name, total), trend[] (date, total).
//   Query purchase_orders where outlet_id + date range (max 93 hari,
//   limit 500 terbaru + flag truncated bila kepotong).
// GET /reports/inventory → total_value (sum stock*qty*hpp),
//   opname_accuracy (% item selisih 0 pada opname terakhir),
//   low_stock[] (name, qty, unit), overstock[],
//   movements[] (product_name, type, qty_change, created_at, max 15).
```

## 3. Routes

```php
// routes/api.php  (prefix v1 + auth:sanctum)
Route::get('/users', [UserController::class, 'index']);
Route::post('/users', [UserController::class, 'store']);
Route::put('/users/{user}', [UserController::class, 'update']);
Route::get('/roles', [UserController::class, 'roles']);

Route::get('/attendances', [AttendanceController::class, 'index']);
Route::post('/attendances/clock-in', [AttendanceController::class, 'clockIn']);
Route::post('/attendances/clock-out', [AttendanceController::class, 'clockOut']);

Route::get('/reports/purchases', [ReportController::class, 'purchases']);
Route::get('/reports/inventory', [ReportController::class, 'inventory']);
```

## 4. Checklist verifikasi

- Tanpa token → 401; salah outlet → 403/422 jujur.
- `outlet_id` selalu di-scope server.
- Status workflow persis string kontrak (`hadir`, `terlambat`, dst.).
- `POST /orders` lunas tidak berubah (laporan hanya baca agregat).
- Export PDF/Excel tetap via web (mobile ringkasan saja).
