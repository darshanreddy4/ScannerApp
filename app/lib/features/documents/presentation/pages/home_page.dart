import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../monetization/presentation/ad_banner_slot.dart';
import '../../../scanner/presentation/bloc/scan_session_cubit.dart';
import '../../../settings/presentation/settings_view.dart';
import '../../domain/entities/scanned_document.dart';
import '../bloc/documents_cubit.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_tab == 0 ? 'My Documents' : 'Settings')),
      body: IndexedStack(index: _tab, children: const [_DocumentsView(), SettingsView()]),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => _showAddSheet(context),
              icon: const Icon(AppIcons.scan),
              label: const Text('Scan'),
            )
          : null,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AdBannerSlot(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(AppIcons.home), selectedIcon: Icon(AppIcons.homeActive), label: 'Documents'),
              NavigationDestination(icon: Icon(AppIcons.settings), selectedIcon: Icon(AppIcons.settingsActive), label: 'Settings'),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showAddSheet(BuildContext context) async {
    final session = context.read<ScanSessionCubit>();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            _SheetTile(icon: AppIcons.camera, title: 'Scan with camera', subtitle: 'Automatic edge detection', value: 'camera'),
            _SheetTile(icon: AppIcons.gallery, title: 'Import image', subtitle: 'JPEG or PNG from your device', value: 'import'),
            SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;

    session.reset();
    if (choice == 'camera') {
      context.push('/scan');
      return;
    }

    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null || !context.mounted) return;
      final ok = await session.beginDraft(file.path);
      if (!context.mounted) return;
      if (ok) {
        context.push('/scan/crop');
      } else if (session.state.error != null) {
        showFailure(context, session.state.error!);
      }
    } catch (_) {
      if (context.mounted) {
        showFailure(context, const PermissionFailure('Photo library access is unavailable.'));
      }
    }
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({required this.icon, required this.title, required this.subtitle, required this.value});
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppColors.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        onTap: () => Navigator.of(context).pop(value),
      );
}

class _DocumentsView extends StatelessWidget {
  const _DocumentsView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DocumentsCubit, DocumentsState>(
      listenWhen: (a, b) => b.status == LoadStatus.failed && a.failure != b.failure,
      listener: (context, s) => showFailure(context, s.failure!),
      builder: (context, state) {
        if (state.status == LoadStatus.loading) return const Center(child: CircularProgressIndicator());
        if (state.documents.isEmpty) return const _EmptyState();

        return RefreshIndicator(
          onRefresh: context.read<DocumentsCubit>().load,
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 96),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
              childAspectRatio: 0.72,
            ),
            itemCount: state.documents.length,
            itemBuilder: (context, i) => _DocumentCard(document: state.documents[i]),
          ),
        );
      },
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.document});
  final ScannedDocument document;

  @override
  Widget build(BuildContext context) {
    final cover = document.cover;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await context.push('/document/${document.id}');
          if (context.mounted) context.read<DocumentsCubit>().load();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: AppColors.background,
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: cover == null
                    ? const Icon(AppIcons.document, color: AppColors.inkMuted)
                    : Image.file(File(cover.imagePath), fit: BoxFit.contain, cacheWidth: 420,
                        errorBuilder: (_, _, _) => const Icon(AppIcons.document, color: AppColors.inkMuted)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm + 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(document.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${pagesLabel(document.pageCount)}  ·  ${formatDate(document.updatedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.emptyDocs, size: 72, color: AppColors.inkMuted),
            const SizedBox(height: AppSpacing.md),
            const Text('No documents yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Scan a document or import an image. Everything stays on this device.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}
