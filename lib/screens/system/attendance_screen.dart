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
    case 'hadir':
      return BadgeTone.success;
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

/// Absensi pegawai (kontrak grup 13):
/// GET /attendances?outlet_id=&date=, POST clock-in/out.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final ApiService _api = ApiService();
  DateTime _date = DateTime.now();
  List<Attendance> _rows = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final outletId = context.read<AuthProvider>().currentOutletId;
      final response = await _api.get(
        '/attendances',
        query: {
          if (outletId != null) 'outlet_id': '$outletId',
          'date': Fmt.dateForApi(_date),
        },
      );
      final raw = response is Map ? response['data'] : response;
      final rows = raw is List
          ? raw.whereType<Map<String, dynamic>>().map(Attendance.fromJson).toList()
          : <Attendance>[];
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = S.tn(context, 'Gagal memuat data absensi.');
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 1)),
      helpText: S.tn(context, 'Pilih tanggal'),
    );
    if (picked == null) return;
    setState(() => _date = picked);
    await _refresh();
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
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month_outlined, size: 18),
                    label: Text(Fmt.dateForApi(_date)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  key: const ValueKey('clock_in_button'),
                  onPressed: _busy ? null : () => _clock('clock-in'),
                  icon: const Icon(Icons.login, size: 18),
                  label: Text(S.t(context, 'Clock In')),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton.icon(
                  key: const ValueKey('clock_out_button'),
                  onPressed: _busy ? null : () => _clock('clock-out'),
                  icon: const Icon(Icons.logout, size: 18),
                  label: Text(S.t(context, 'Clock Out')),
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
    if (_loading) return const LoadingSkeleton(items: 6, itemHeight: 64);
    if (_error != null) return ErrorState(message: _error!, onRetry: _refresh);
    if (_rows.isEmpty) {
      return EmptyState(
        icon: Icons.fact_check_outlined,
        title: S.t(context, 'Belum ada absensi'),
        message: S.t(
          context,
          'Catat kehadiran dengan tombol Clock In di atas.',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: _rows.length,
        itemBuilder: (_, i) => _rowCard(_rows[i]),
      ),
    );
  }

  Widget _rowCard(Attendance a) {
    final theme = Theme.of(context);
    final name = (a.userName == null || a.userName!.isEmpty)
        ? S.t(context, 'Tanpa nama')
        : a.userName!;
    final time = [
      if (a.clockIn != null && a.clockIn!.isNotEmpty)
        '${S.t(context, 'Masuk')} ${a.clockIn!.length >= 16 ? a.clockIn!.substring(11, 16) : a.clockIn!}',
      if (a.clockOut != null && a.clockOut!.isNotEmpty)
        '${S.t(context, 'Keluar')} ${a.clockOut!.length >= 16 ? a.clockOut!.substring(11, 16) : a.clockOut!}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            name.substring(0, 1).toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          time.isEmpty ? (a.date ?? '-') : time,
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: StatusBadge(
          Attendance.statusLabel(a.status),
          tone: _toneForAttendance(a.status),
        ),
      ),
    );
  }
}
