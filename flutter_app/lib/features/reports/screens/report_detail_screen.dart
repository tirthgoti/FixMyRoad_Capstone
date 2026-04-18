import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fixmyroad/utils/repair_estimator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/models.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../core/theme.dart';
import '../../../core/constants.dart';

class ReportDetailScreen extends ConsumerStatefulWidget {
  final String reportId;
  const ReportDetailScreen({super.key, required this.reportId});

  @override
  ConsumerState<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends ConsumerState<ReportDetailScreen> {
  Report? _report;
  List<StatusHistory> _history = [];
  bool _loading     = true;
  bool _hasUpvoted  = false;
  bool _upvoting    = false;

  /// True when the AI has returned at least one meaningful signal.
  bool _hasAiSignals(AiResult? ai) => ai?.hasAiSignals ?? false;

  String _severityDescription(String severity) {
  switch (severity) {
    case 'critical':
      return 'Severe damage requiring immediate repair to ensure safety.';
    case 'deep':
      return 'Significant pothole that poses a risk to vehicles and cyclists.';
    case 'moderate':
      return 'Moderate damage that should be scheduled for repair soon.';
    case 'shallow':
    default:
      return 'Minor surface damage. Monitor and repair when convenient.';
  }
}

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final service = ref.read(supabaseServiceProvider);
      final report  = await service.getReport(widget.reportId);
      final history = await service.getStatusHistory(widget.reportId);
      final upvoted = await service.hasUpvoted(widget.reportId);
      if (mounted) {
        setState(() {
          _report     = report;
          _history    = history;
          _hasUpvoted = upvoted;
          _loading    = false;
        });
      }
      service.subscribeToReport(widget.reportId, (updated) {
        if (mounted) _load();
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading report: $e')));
    }
  }

  Future<void> _upvote() async {
    if (_hasUpvoted || _upvoting) return;
    setState(() => _upvoting = true);
    await ref.read(supabaseServiceProvider).upvoteReport(widget.reportId);
    await _load();
    setState(() => _upvoting = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_report == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Report')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Could not load report'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                setState(() => _loading = true);
                _load();
              },
              child: const Text('Retry'),
            ),
          ]),
        ),
      );
    }

    final r = _report!;
    final ai = r.aiResult;
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(slivers: [
        // ── Hero image ─────────────────────────────────────────────────
        SliverAppBar(
          expandedHeight: 280,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: r.imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: r.imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.image_not_supported, size: 48),
                    ),
                  )
                : Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.image_not_supported, size: 48),
                  ),
          ),
          actions: [
            // Upvote button
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _hasUpvoted ? null : _upvote,
                icon: _upvoting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_hasUpvoted
                        ? Icons.thumb_up
                        : Icons.thumb_up_outlined,
                        size: 18),
                label: Text('${r.upvoteCount}'),
                style: FilledButton.styleFrom(
                  backgroundColor: _hasUpvoted
                      ? theme.colorScheme.primary
                      : Colors.white.withOpacity(0.9),
                  foregroundColor: _hasUpvoted
                      ? Colors.white
                      : theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Status + severity
              Row(children: [
                StatusChip(status: r.status),
                const SizedBox(width: 8),
                if (ai?.severity != null)
                  SeverityBadge(severity: ai!.severity!, large: true),
              ]),
              const SizedBox(height: 16),

              // Address
              Row(children: [
                Icon(Icons.location_on,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(r.address ?? 'Location recorded',
                        style: theme.textTheme.bodyMedium)),
              ]),
              const SizedBox(height: 8),

              // Description
              if (r.description != null) ...[
                Text(r.description!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),
              ],

              // ── AI Results card — citizen sees severity only ───────
              if (ai != null && _hasAiSignals(ai)) ...[
                const SectionHeader(title: 'AI Analysis'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      // Severity badge — always visible
                      if (ai.severity != null)
                        Center(child: SeverityBadge(severity: ai.severity!, large: true)),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          _severityDescription(ai.severity ?? 'shallow'),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // Engineers and admins also see technical metrics
                      Builder(builder: (context) {
                        final uid = Supabase.instance.client.auth.currentUser?.id;
                        // Check if user is engineer or admin via profile role
                        final isPrivileged = r.engineer?.id == uid ||
                            r.assignedTo == uid;
                        if (!isPrivileged) return const SizedBox.shrink();
                        final est = ai.severity != null
                            ? RepairEstimatorAhmedabad(
                                severity:      ai.severity!,
                                areaPx:        ai.potholeAreaPx,
                                relativeDepth: ai.relativeDepth,
                              )
                            : null;
                        return Column(children: [
                          const Divider(height: 20),
                          _metricRow('Relative depth',
                              ai.relativeDepth?.toStringAsFixed(4) ?? '—'),
                          _metricRow('Confidence',
                              '${((ai.confidence ?? 0) * 100).toStringAsFixed(1)}%'),
                          if (est != null)
                            _metricRow('Repair cost estimate',
                                est.costLabel, highlight: true),
                          if (ai.asphaltKg != null)
                            _metricRow('Asphalt required',
                                '${ai.asphaltKg!.toStringAsFixed(1)} kg'),
                          if (ai.labourHours != null)
                            _metricRow('Labour',
                                '${ai.labourHours!.toStringAsFixed(1)} hrs'),
                        ]);
                      }),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
              ] else if (ai != null) ...[
                // AI record exists but no meaningful signals yet
                const SectionHeader(title: 'AI Analysis'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text('Analyzing…',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ── Output images ─────────────────────────────────────────
              if (ai?.heatmapUrl != null ||
                  ai?.depthMapUrl != null ||
                  ai?.beforeAfterUrl != null) ...[
                const SectionHeader(title: 'Analysis images'),
                _imageGrid(ai!),
                const SizedBox(height: 16),
              ],

              // ── Status timeline ───────────────────────────────────────
              if (_history.isNotEmpty) ...[
                const SectionHeader(title: 'Status history'),
                ..._history.map((h) => _timelineItem(h, theme)),
              ],

              const SizedBox(height: 32),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _metricRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, color: Color(0xFF757575))),
        const Spacer(),
        Text(value,
            style: TextStyle(
              fontSize: 13,
              fontWeight:
                  highlight ? FontWeight.w700 : FontWeight.w500,
              color: highlight
                  ? AppTheme.primary
                  : null,
            )),
      ]),
    );
  }

  Widget _imageGrid(AiResult ai) {
    final urls = <String, String>{
      if (ai.heatmapUrl != null)    'Heatmap': ai.heatmapUrl!,
      if (ai.depthMapUrl != null)   'Depth map': ai.depthMapUrl!,
      if (ai.beforeAfterUrl != null)'Before/After': ai.beforeAfterUrl!,
    };
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final entry = urls.entries.elementAt(i);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: entry.value,
                    width: 180,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(entry.key,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF757575))),
            ],
          );
        },
      ),
    );
  }

  Widget _timelineItem(StatusHistory h, ThemeData theme) {
    final color = AppTheme.statusColor(h.newStatus);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Container(width: 2, height: 40, color: color.withOpacity(0.2)),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h.newStatus.replaceAll('_', ' ').toUpperCase(),
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            if (h.changer != null)
              Text('by ${h.changer!.displayName}',
                  style: theme.textTheme.bodySmall),
            if (h.note != null)
              Text(h.note!, style: theme.textTheme.bodySmall),
            Text(
              _formatDate(h.changedAt),
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ]),
        ),
      ]),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}