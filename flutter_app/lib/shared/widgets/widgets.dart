import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fixmyroad/utils/repair_estimator.dart';
import 'package:shimmer/shimmer.dart';

import '../models/models.dart';
import '../../core/theme.dart';

// ── Severity Badge ─────────────────────────────────────────────────────────
class SeverityBadge extends StatelessWidget {
  final String severity;
  final bool large;
  const SeverityBadge({super.key, required this.severity, this.large = false});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.severityColor(severity);
    final label = severity[0].toUpperCase() + severity.substring(1);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 14 : 10,
        vertical: large ? 6 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: large ? 10 : 8,
          height: large ? 10 : 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: large ? 6 : 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: large ? 14 : 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ]),
    );
  }
}

// ── Status Chip ────────────────────────────────────────────────────────────
class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip({super.key, required this.status});

  String get _label {
    switch (status) {
      case 'submitted':    return 'Submitted';
      case 'under_review': return 'Under Review';
      case 'assigned':     return 'Assigned';
      case 'in_progress':  return 'In Progress';
      case 'fixed':        return 'Fixed';
      case 'rejected':     return 'Rejected';
      default:             return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Report Card ────────────────────────────────────────────────────────────
class ReportCard extends StatelessWidget {
  final Report report;
  final VoidCallback onTap;
  const ReportCard({super.key, required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final ai     = report.aiResult;
    final hasAi  = ai?.hasAiSignals ?? false;

    // Build single-value cost label only after AI signals are available.
    String? costLabel;
    if (hasAi && ai?.severity != null) {
      final est = RepairEstimatorAhmedabad(
        severity:      ai!.severity!,
        areaPx:        ai.potholeAreaPx,
        relativeDepth: ai.relativeDepth,
      );
      costLabel = est.costLabel;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: report.imageUrl,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                errorWidget: (_, __, ___) => Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.image_not_supported_outlined),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Chips — use Wrap to avoid RenderFlex overflow
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (hasAi && ai?.severity != null)
                        SeverityBadge(severity: ai!.severity!),
                      StatusChip(status: report.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    report.address ?? 'Location recorded',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Bottom row — upvotes + time
                  Row(children: [
                    Icon(Icons.arrow_upward,
                        size: 14, color: theme.colorScheme.primary),
                    Text(' ${report.upvoteCount}',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(width: 10),
                    Icon(Icons.schedule,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        _timeAgo(report.submittedAt),
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  // Cost / Analyzing — on its own line
                  const SizedBox(height: 4),
                  if (costLabel != null)
                    Text(
                      costLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    Text(
                      'Analyzing…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0)    return '${diff.inDays}d ago';
    if (diff.inHours > 0)   return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}

// ── Shimmer Loading List ───────────────────────────────────────────────────
class ShimmerList extends StatelessWidget {
  final int count;
  const ShimmerList({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      highlightColor: Theme.of(context).colorScheme.surface,
      child: ListView.builder(
        itemCount: count,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          height: 96,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

// ── Empty State ────────────────────────────────────────────────────────────
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: theme.colorScheme.primary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

// ── Section Header ─────────────────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const Spacer(),
        if (trailing != null) trailing!,
      ]),
    );
  }
}
