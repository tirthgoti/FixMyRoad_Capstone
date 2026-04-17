import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/models/models.dart';

import '../../../shared/services/supabase_service.dart';
import '../../../core/theme.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Profile? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(supabaseServiceProvider);
    if (svc.currentUser == null) return;
    final p = await svc.getProfile(svc.currentUser!.id);
    if (mounted) setState(() => _profile = p);
  }

  Future<void> _signOut() async {
    await ref.read(supabaseServiceProvider).signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Avatar + name
          Center(
            child: Column(children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  _profile?.initials ?? '?',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(_profile?.displayName ?? '—',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(ref.read(supabaseServiceProvider).currentUser?.email ?? '',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _profile?.role.toUpperCase() ?? 'CITIZEN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 32),

          // Settings section
          Text('Settings',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              // Theme toggle — custom row so the SegmentedButton
              // gets a fixed width and the 'Theme' label never stacks
              // vertically on small screens.
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.dark_mode_outlined),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Theme',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: 162,
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode, size: 16)),
                          ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.brightness_auto, size: 16)),
                          ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode, size: 16)),
                        ],
                        selected: {themeMode},
                        onSelectionChanged: (s) => ref
                            .read(themeModeProvider.notifier)
                            .state = s.first,
                        style: const ButtonStyle(
                            visualDensity: VisualDensity.compact),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 16),
              ListTile(
                leading: const Icon(Icons.chat_outlined),
                title: const Text('AI Assistant'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/chatbot'),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          Text('About',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('App version'),
                trailing: Text('1.0.0',
                    style: theme.textTheme.bodySmall),
              ),
              const Divider(height: 1, indent: 16),
              ListTile(
                leading: const Icon(Icons.construction_outlined),
                title: const Text('FixMyRoad'),
                subtitle: const Text('Civic pothole reporting platform'),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          OutlinedButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
