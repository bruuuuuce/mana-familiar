import 'dart:io';

import 'package:flutter/material.dart';

import '../native_project_window.dart';

/// First-run destination. It deliberately does not attempt an inspect command
/// until a project was explicitly selected by the user.
class ProjectWelcomePage extends StatelessWidget {
  const ProjectWelcomePage({
    super.key,
    required this.recentProjectRoots,
    required this.onOpenProject,
    required this.onClearRecentProjects,
  });

  final List<String> recentProjectRoots;
  final Future<void> Function(String projectRoot) onOpenProject;
  final Future<void> Function() onClearRecentProjects;

  Future<void> _chooseProject() async {
    final projectRoot = await NativeProjectWindow.chooseProject();
    if (projectRoot != null) await onOpenProject(projectRoot);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final recent = recentProjectRoots
        .where(
          (projectRoot) =>
              Directory(projectRoot).existsSync() && !_isRoot(projectRoot),
        )
        .take(10)
        .toList(growable: false);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 20, 32, 24),
              child: Column(
                children: [
                  Image.asset(
                    'assets/branding/mana-familiar-welcome.png',
                    height: 230,
                    fit: BoxFit.contain,
                    semanticLabel: 'Mana Familiar',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Mana Familiar',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Choose a project to explore its Mana journeys and evidence.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _chooseProject,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Open another project…'),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: recent.isEmpty
                          ? Center(
                              child: Text(
                                'No recent projects yet.',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: recent.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final projectRoot = recent[index];
                                return ListTile(
                                  leading: const Icon(Icons.folder_outlined),
                                  title: Text(_projectName(projectRoot)),
                                  subtitle: Text(
                                    projectRoot,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => onOpenProject(projectRoot),
                                );
                              },
                            ),
                    ),
                  ),
                  if (recent.isNotEmpty)
                    TextButton(
                      onPressed: onClearRecentProjects,
                      child: const Text('Clear recent projects'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _projectName(String projectRoot) =>
      Directory(
        projectRoot,
      ).uri.pathSegments.where((part) => part.isNotEmpty).lastOrNull ??
      projectRoot;

  static bool _isRoot(String projectRoot) {
    final directory = Directory(projectRoot).absolute;
    return directory.parent.path == directory.path;
  }
}
