import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fixmyroad/utils/repair_estimator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/widgets/widgets.dart';
import 'admin_report_detail_screen.dart';

class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() =>
      _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  List<Report>  _reports    = [];
  List<Profile> _engineers  = [];
  bool          _loading    = true;
  String        _filterStatus = 'all';

  final _statuses = ['all', 'submitted', 'under_review', 'assigned',
                     'in_progress', 'fixed', 'rejected'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;

      // Load all reports with AI results
      final reportsData = await client
          .from('reports')
          .select('''
            *,
            ai_results (*),
            citizen:profiles!citizen_id (id, full_name),
            engineer:profiles!assigned_to (id, full_name),
            upvotes(count)
          ''')
          .order('submitted_at', ascending: false);

      // Load all engineers
      final engData = await client
          .from('profiles')
          .select()
          .eq('role', 'engineer');

      final reports = (reportsData as List).map((e) {
        e['upvote_count'] = e['upvotes'];
        return Report.fromJson(e);
      }).toList();

      final engineers = (engData as List)
          .map((e) => Profile.fromJson(e))
          .toList();

      if (mounted) {
        setState(() {
          _reports   = reports;
          _engineers = engineers;
          _loading   = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  List<Report> get _filtered {
    if (_filterStatus == 'all') return _reports;
    return _reports.where((r) => r.status == _filterStatus).toList();
  }

  Future<void> _assignEngineer(Report report) async {
    if (_engineers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No engineers available.')));
      return;
    }

    final selected = await showDialog<Profile>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Assign engineer'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _engineers.length,
            itemBuilder: (_, i) {
              final eng = _engineers[i];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(eng.initials),
                ),
                title: Text(eng.displayName),
                subtitle: Text(eng.role),
                onTap: () => Navigator.pop(context, eng),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected == null) return;

    try {
      await Supabase.instance.client.from('reports').update({
        'assigned_to': selected.id,
        'status':      'assigned',
        'updated_at':  DateTime.now().toIso8601String(),
      }).eq('id', report.id);

      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Assigned to ${selected.displayName}')));
      _load();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _updateStatus(Report report, String status) async {
    try {
      await Supabase.instance.client.from('reports').update({
        'status':     status,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', report.id);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _signOut() async {
    await ref.read(supabaseServiceProvider).signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Reports'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(icon: const Icon(Icons.logout), onPressed: _signOut),
        ],
      ),
      body: Column(children: [

        // ── Stats bar ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(12),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(children: [
            _StatChip(label: 'Total',
                value: _reports.length.toString(),
                color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            _StatChip(
                label: 'Open',
                value: _reports
                    .where((r) =>
                        !['fixed', 'rejected'].contains(r.status))
                    .length
                    .toString(),
                color: Colors.orange),
            const SizedBox(width: 8),
            _StatChip(
                label: 'Fixed',
                value: _reports
                    .where((r) => r.status == 'fixed')
                    .length
                    .toString(),
                color: Colors.green),
            const Spacer(),
            Text(
              '₹${_totalCost().toStringAsFixed(0)}',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 4),
            Text('est.', style: theme.textTheme.bodySmall),
          ]),
        ),

        // ── Status filter ──────────────────────────────────────────
        SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: _statuses.length,
            itemBuilder: (_, i) {
              final s = _statuses[i];
              final selected = _filterStatus == s;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(
                    s == 'all' ? 'All' : s.replaceAll('_', ' '),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400),
                  ),
                  selected: selected,
                  onSelected: (_) =>
                      setState(() => _filterStatus = s),
                ),
              );
            },
          ),
        ),

        // ── Reports list ───────────────────────────────────────────
        Expanded(
          child: _loading
              ? const ShimmerList()
              : _filtered.isEmpty
                  ? EmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'No reports',
                      subtitle: _filterStatus == 'all'
                          ? 'No pothole reports yet.'
                          : 'No reports with status "$_filterStatus".',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) => _AdminReportCard(
                          report: _filtered[i],
                          onAssign: () => _assignEngineer(_filtered[i]),
                          onStatusChange: (s) =>
                              _updateStatus(_filtered[i], s),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdminReportDetailScreen(
                                  reportId: _filtered[i].id),
                            ),
                          ).then((_) => _load()),
                        ),
                      ),
                    ),
        ),
      ]),
    );
  }

  double _totalCost() => _reports.fold(0.0, (sum, r) {
        final ai = r.aiResult;
        if (ai?.severity == null) return sum;
        return sum + RepairEstimatorAhmedabad(
          severity:      ai!.severity!,
          areaPx:        ai.potholeAreaPx,
          relativeDepth: ai.relativeDepth,
        ).costInr;
      });
}

// ── Admin Report Card ──────────────────────────────────────────────────────
class _AdminReportCard extends StatelessWidget {
  final Report       report;
  final VoidCallback onAssign;
  final VoidCallback onTap;
  final void Function(String) onStatusChange;

  const _AdminReportCard({
    required this.report,
    required this.onAssign,
    required this.onTap,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ai    = report.aiResult;

    // Build single-value cost + depth/area labels from AI data
    RepairEstimatorAhmedabad? est;
    if (ai?.severity != null) {
      est = RepairEstimatorAhmedabad(
        severity:      ai!.severity!,
        areaPx:        ai.potholeAreaPx,
        relativeDepth: ai.relativeDepth,
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // Row 1 — image + info
            Row(children: [
              if (report.imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: report.imageUrl,
                    width: 64, height: 64,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 64, height: 64,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.image_not_supported),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Chips — Wrap to avoid overflow
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (ai?.severity != null)
                        SeverityBadge(severity: ai!.severity!),
                      StatusChip(status: report.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    report.address ?? 'Location recorded',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'By: ${report.citizen?.displayName ?? "Unknown"}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 8),

            // Row 2 — metrics (Wrap to avoid overflow)
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                // Cost estimate
                if (est != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.currency_rupee,
                        size: 14, color: theme.colorScheme.primary),
                    Text(est.costLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600)),
                  ])
                else
                  Text('Analyzing…',
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurfaceVariant)),

                // Priority score
                if (ai?.priorityScore != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.priority_high, size: 14,
                        color: theme.colorScheme.error),
                    Text(' ${ai!.priorityScore!.toStringAsFixed(1)}',
                        style: theme.textTheme.bodySmall),
                  ]),

                // Upvotes
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.thumb_up_outlined,
                      size: 14, color: theme.colorScheme.onSurfaceVariant),
                  Text(' ${report.upvoteCount}',
                      style: theme.textTheme.bodySmall),
                ]),

                // Depth in mm
                if (est?.depthMm != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.straighten, size: 14,
                        color: theme.colorScheme.onSurfaceVariant),
                    Text(' ${est!.depthMm!.toStringAsFixed(0)} mm',
                        style: theme.textTheme.bodySmall),
                  ]),

                // Area in m²
                if (est?.areaM2 != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.crop_square, size: 14,
                        color: theme.colorScheme.onSurfaceVariant),
                    Text(' ${est!.areaM2!.toStringAsFixed(2)} m²',
                        style: theme.textTheme.bodySmall),
                  ]),

                // Assigned engineer
                if (report.engineer != null)
                  Text(
                    '👷 ${report.engineer!.displayName}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Row 3 — action buttons
            Row(children: [
              // Assign button
              if (!['fixed', 'rejected'].contains(report.status))
                OutlinedButton.icon(
                  onPressed: onAssign,
                  icon: const Icon(Icons.person_add, size: 14),
                  label: Text(
                    report.assignedTo == null ? 'Assign' : 'Reassign',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                ),
              const SizedBox(width: 8),
              // Quick status buttons
              if (report.status == 'submitted')
                _QuickBtn('Review', Colors.orange,
                    () => onStatusChange('under_review')),
              if (report.status == 'in_progress')
                _QuickBtn('Mark Fixed', Colors.green,
                    () => onStatusChange('fixed')),
              if (!['fixed', 'rejected'].contains(report.status))
                _QuickBtn('Reject', Colors.red,
                    () => onStatusChange('rejected')),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _QuickBtn extends StatelessWidget {
  final String     label;
  final Color      color;
  final VoidCallback onTap;
  const _QuickBtn(this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      );
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color)),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: Colors.grey)),
        ],
      );
}