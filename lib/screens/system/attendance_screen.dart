import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/s.dart';
import '../../models/system_ops.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';

BadgeTone _toneForAttendance(String status) {
  switch (status.toLowerCase()) {
    case 'present':
    case 'hadir':
      return BadgeTone.success;
    case 'late':
    case 'terlambat':
      return BadgeTone.warning;
    case 'izin':
      return BadgeTone.info;
    case 'sakit':
      return BadgeTone.error;
    default:
      return BadgeTone.neutral;
  }
}

/// Absensi pegawai — backend nyata (produksi):
/// - GET /attendances/today → {data: {id, user_id, outlet_id, date,
///   clock_in ("HH:mm:ss"), clock_out, status: present|late, notes} | null}
/// - POST /attendances/clock-in {outlet_id, notes?}
///   (status otomatis server: late bila lewat 08:00)
/// - POST /attendances/clock-out (tanpa body)
/// - GET /attendances/history?outlet_id=&from=&to=(&per_page=) → envelope
///   {data: [...], meta} milik outlet yang bisa diakses user.
///   Bila 404 (endpoint belum deploy) → today-only + pesan jujur.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final ApiService _api = ApiService();
  Attendance? _today;
  List<Attendance> _history = [];
  bool _historyAvailable = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  static Attendance? parseToday(dynamic response) {
    final raw = response is Map ? response['data'] : response;
    if (raw is Map<String, dynamic>) return Attendance.fromJson(raw);
    return null;
  }

  static List<Attendance> parseHistory(dynamic response) {
    final raw = response is Map ? response['data'] : response;
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Attendance.fromJson)
        .toList();
  }

  Future<void> _refresh() async {
    final outletId = context.read<AuthProvider>().currentOutletId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.get('/attendances/today');
      if (!mounted) return;
      setState(() {
        _today = parseToday(response);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = S.tn(context, 'Gagal memuat data absensi.');
      });
      return;
    }
    // Riwayat best-effort: gagal memuatnya tidak menutupi kartu today.
    try {
      final history = await _api.get(
        '/attendances/history',
        query: {
          'per_page': '20',
          if (outletId != null) 'outlet_id': '$outletId',
        },
      );
      if (!mounted) return;
      setState(() {
        _history = parseHistory(history);
        _historyAvailable = true;
        _loading = false;
      });
    } on ApiException catch (_) {
      if (!mounted) return;
      setState(() {
        _history = [];
        _historyAvailable = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _history = [];
        _historyAvailable = false;
        _loading = false;
      });
    }
  }

  Future<void> _clock(String action) async {
    final outletId = context.read<AuthProvider>().currentOutletId;
    if (action == 'clock-in' && outletId == null) {
      showAppSnackbar(
        context,
        S.tn(context, 'Pilih outlet dulu.'),
        type: SnackType.warning,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _api.post(
        '/attendances/$action',
        body: action == 'clock-in' ? {'outlet_id': outletId} : null,
      );
      if (!mounted) return;
      showAppSnackbar(
        context,
        action == 'clock-in'
            ? S.tn(context, 'Clock-in berhasil dicatat.')
            : S.tn(context, 'Clock-out berhasil dicatat.'),
        type: SnackType.success,
      );
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackbar(context, e.message, type: SnackType.error);
    } catch (_) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Gagal mencatat absensi.'),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = _today;
    final clockedIn =
        today != null && (today.clockIn?.isNotEmpty ?? false);
    final clockedOut =
        today != null && (today.clockOut?.isNotEmpty ?? false);
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Absensi')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Muat ulang'),
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('clock_in_button'),
                    onPressed: (_busy || clockedIn) ? null : () => _clock('clock-in'),
                    icon: const Icon(Icons.login, size: 18),
                    label: Text(S.t(context, 'Clock In')),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('clock_out_button'),
                    onPressed: (_busy || !clockedIn || clockedOut)
                        ? null
                        : () => _clock('clock-out'),
                    icon: const Icon(Icons.logout, size: 18),
                    label: Text(S.t(context, 'Clock Out')),
                  ),
                ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingSkeleton(items: 3, itemHeight: 88);
    if (_error != null) return ErrorState(message: _error!, onRetry: _refresh);
    final today = _today;
    if (today == null) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            EmptyState(
              icon: Icons.fact_check_outlined,
              title: S.t(context, 'Belum ada absensi'),
              message: S.t(context, 'Belum clock-in hari ini.'),
            ),
            _historySection(),
            if (!_historyAvailable) _webAdminNote(),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          _todayCard(today),
          _historySection(),
          if (!_historyAvailable) _webAdminNote(),
        ],
      ),
    );
  }

  Widget _webAdminNote() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Text(
        S.t(
          context,
          'Riwayat absensi lengkap tersedia di web admin.',
        ),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  /// Riwayat dari GET /attendances/history. Bila endpoint belum tersedia
  /// di server (404) → pesan jujur, layar tetap today-only.
  Widget _historySection() {
    final theme = Theme.of(context);
    if (!_historyAvailable) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Text(
          S.t(
            context,
            'Riwayat server belum tersedia, menampilkan hari ini saja.',
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.md,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            S.t(context, 'Riwayat Absensi'),
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
          ),
        ),
        if (_history.isEmpty)
          Text(
            S.t(context, 'Belum ada riwayat absensi.'),
            style: theme.textTheme.bodySmall,
          )
        else
          for (final h in _history) _historyTile(h),
      ],
    );
  }

  Widget _historyTile(Attendance h) {
    final name = (h.userName ?? '').trim();
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        dense: true,
        title: Text(
          h.date ?? '-',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${S.t(context, 'Masuk')} ${_shortTime(h.clockIn)}'
          ' • ${S.t(context, 'Keluar')} ${_shortTime(h.clockOut)}'
          '${name.isEmpty ? '' : '\n$name'}',
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: name.isNotEmpty,
        trailing: StatusBadge(
          Attendance.statusLabel(h.status),
          tone: _toneForAttendance(h.status),
        ),
      ),
    );
  }

  String _shortTime(String? v) {
    if (v == null || v.isEmpty) return '-';
    // Backend mengirim "HH:mm:ss" — tampilkan "HH:mm".
    if (v.length >= 5 && !v.contains('T')) return v.substring(0, 5);
    if (v.length >= 16 && v.contains('T')) return v.substring(11, 16);
    return v;
  }

  Widget _todayCard(Attendance a) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    S.t(context, 'Absensi Hari Ini'),
                    style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
                  ),
                ),
                StatusBadge(
                  Attendance.statusLabel(a.status),
                  tone: _toneForAttendance(a.status),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              a.date ?? Fmt.dateForApi(DateTime.now()),
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: _timeTile(
                    context,
                    Icons.login,
                    S.t(context, 'Masuk'),
                    _shortTime(a.clockIn),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _timeTile(
                    context,
                    Icons.logout,
                    S.t(context, 'Keluar'),
                    _shortTime(a.clockOut),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeTile(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
