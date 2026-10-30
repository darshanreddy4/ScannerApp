import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../bloc/documents_cubit.dart';
import '../widgets/document_widgets.dart';
import '../widgets/refresh_on_return.dart';
import 'home_page.dart';
import '../../../../core/widgets/text.dart';

class FolderPage extends StatelessWidget {
  const FolderPage({super.key, required this.folderId});
  final String folderId;

  @override
  Widget build(BuildContext context) {
    return RefreshOnReturn(
      child: BlocBuilder<DocumentsCubit, DocumentsState>(
        builder: (context, state) {
          final matches = state.folders.where((f) => f.id == folderId);
          final folder = matches.isEmpty ? null : matches.first;
          final docs = state.inFolder(folderId);

          return PopScope(
            canPop: !state.selecting,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) context.read<DocumentsCubit>().clearSelection();
            },
            child: Scaffold(
              appBar: DocumentsAppBar(title: folder?.name ?? 'Folder'),
              floatingActionButton: state.selecting ? null : ScanFab(folderId: folderId),
              body: docs.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(AppIcons.emptyDocs, size: 56, color: AppColors.inkMuted),
                            SizedBox(height: AppSpacing.md),
                            Text('This folder is empty', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                            SizedBox(height: AppSpacing.sm),
                            Text(
                              'Scan a new document here, or use "Move to folder" on any document.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.inkMuted),
                            ),
                          ],
                        ),
                      ),
                    )
                  : CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 96),
                          sliver: DocumentsCollection(documents: docs, gridView: state.gridView),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}
