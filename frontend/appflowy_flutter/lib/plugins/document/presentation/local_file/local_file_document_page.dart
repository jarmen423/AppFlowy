import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_page.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/plugins/document/presentation/local_file/local_file_info.dart';
import 'package:appflowy/plugins/document/presentation/local_file/local_file_persistence.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:universal_platform/universal_platform.dart';
import 'package:watcher/watcher.dart';

/// A document page that treats a local Markdown / text file as the source of truth.
/// Edits are round-tripped via the existing markdown <-> document converters and
/// written back to disk (debounced). External changes are detected via file watcher.
class LocalFileDocumentPage extends StatefulWidget {
  const LocalFileDocumentPage({
    super.key,
    required this.view,
    this.initialSelection,
  });

  final ViewPB view;
  final Selection? initialSelection;

  @override
  State<LocalFileDocumentPage> createState() => _LocalFileDocumentPageState();
}

class _LocalFileDocumentPageState extends State<LocalFileDocumentPage> {
  late final LinkedFileInfo? _linkedInfo = widget.view.linkedLocalFile;

  EditorState? _editorState;
  final LocalFilePersistence _persistence = LocalFilePersistence();
  StreamSubscription<WatchEvent>? _watcherSub;
  DirectoryWatcher? _watcher;

  bool _isLoading = true;
  bool _hasExternalChange = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initFromLinkedFile();
  }

  Future<void> _initFromLinkedFile() async {
    if (_linkedInfo == null || !UniversalPlatform.isDesktop) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'This page is not a valid linked local file.';
      });
      return;
    }

    final state = await _persistence.loadFromFile(_linkedInfo!);
    if (state == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not read the linked file. It may have been moved or deleted.';
      });
      return;
    }

    setState(() {
      _editorState = state;
      _isLoading = false;
    });

    _startWatcher();
    _attachSaveListener();
  }

  void _attachSaveListener() {
    final state = _editorState;
    if (state == null || _linkedInfo == null) return;

    // Listen to *before* transactions so we can persist the latest document.
    state.transactionStream.listen((tuple) {
      final time = tuple.$1;
      if (time != TransactionTime.before) return;

      // Debounced save back to the original file on disk.
      _persistence.saveToFileDebounced(
        info: _linkedInfo!,
        editorState: state,
        onSaved: () {
          if (mounted) {
            setState(() => _hasExternalChange = false);
          }
        },
      );
    });
  }

  void _startWatcher() {
    final info = _linkedInfo;
    if (info == null || !UniversalPlatform.isDesktop) return;

    try {
      final dir = Directory(p.dirname(info.path));
      _watcher = DirectoryWatcher(dir.path);

      _watcherSub = _watcher!.events.listen((event) async {
        if (event.path != info.path) return;
        if (event.type == ChangeType.MODIFY ||
            event.type == ChangeType.ADD ||
            event.type == ChangeType.REMOVE) {
          await _handleExternalFileChange();
        }
      });
    } catch (e) {
      Log.error('[LocalFilePage] Failed to start watcher for ${info.path}: $e');
    }
  }

  Future<void> _handleExternalFileChange() async {
    final info = _linkedInfo;
    if (info == null || _editorState == null) return;

    final changed = await _persistence.hasExternalChange(info);
    if (!changed || !mounted) return;

    setState(() => _hasExternalChange = true);

    // For now we show a non-blocking banner. User explicitly chooses to reload.
    // In a future iteration we could offer a 3-way diff.
  }

  Future<void> _reloadFromDisk() async {
    final info = _linkedInfo;
    if (info == null) return;

    final newState = await _persistence.reloadFromDisk(info);
    if (newState != null && mounted) {
      setState(() {
        _editorState?.dispose();
        _editorState = newState;
        _hasExternalChange = false;
      });
      _attachSaveListener(); // re-attach to the new instance
      showSnackBarMessage(context, 'Reloaded from disk');
    }
  }

  Future<void> _revealInFileManager() async {
    final info = _linkedInfo;
    if (info == null) return;

    try {
      // Use url_launcher helper (opens the directory containing the file)
      final uri = Uri.file(p.dirname(info.path));
      await afLaunchUrlString(uri.toString());
    } catch (e) {
      showSnackBarMessage(context, 'Could not open file location');
    }
  }

  @override
  void dispose() {
    _watcherSub?.cancel();
    _persistence.dispose();
    _editorState?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (_errorMessage != null || _editorState == null || _linkedInfo == null) {
      return _buildErrorState();
    }

    final editorState = _editorState!;
    final info = _linkedInfo!;

    return Column(
      children: [
        if (_hasExternalChange) _buildExternalChangeBanner(info),
        Expanded(
          child: AppFlowyEditorPage(
            editorState: editorState,
            styleCustomizer: EditorStyleCustomizer(
              context: context,
              padding: EditorStyleCustomizer.documentPadding,
              width: context.read<DocumentAppearanceCubit>().state.width,
            ),
            header: _buildLinkedHeader(info),
          ),
        ),
      ],
    );
  }

  Widget _buildLinkedHeader(LinkedFileInfo info) {
    final shortPath = p.basename(info.path);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.6),
      child: Row(
        children: [
          const FlowySvg(FlowySvgs.text_s, size: Size.square(16)),
          const HSpace(8),
          Flexible(
            child: FlowyText(
              'Linked to $shortPath',
              overflow: TextOverflow.ellipsis,
              fontSize: 12,
            ),
          ),
          const HSpace(8),
          FlowyIconButton(
            icon: const Icon(Icons.refresh, size: 16),
            onPressed: _reloadFromDisk,
            tooltipText: 'Reload from disk',
          ),
          FlowyIconButton(
            icon: const Icon(Icons.folder_open, size: 16),
            onPressed: _revealInFileManager,
            tooltipText: 'Reveal in file manager',
          ),
        ],
      ),
    );
  }

  Widget _buildExternalChangeBanner(LinkedFileInfo info) {
    return Container(
      color: Theme.of(context).colorScheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18),
          const HSpace(8),
          const Expanded(
            child: FlowyText(
              'This file was modified outside AppFlowy.',
              fontSize: 13,
            ),
          ),
          OutlinedButton(
            onPressed: _reloadFromDisk,
            child: const Text('Reload'),
          ),
          const HSpace(8),
          TextButton(
            onPressed: () => setState(() => _hasExternalChange = false),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const VSpace(16),
          FlowyText(
            _errorMessage ?? 'Unable to open linked file',
            fontSize: 16,
          ),
          const VSpace(12),
          if (_linkedInfo != null)
            OutlinedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose different file'),
              onPressed: () async {
                // Simple re-link flow: let the user pick a new path and update the view extra.
                final result = await getIt<FilePickerService>().pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['md', 'txt', 'markdown'],
                );
                if (result != null && result.files.isNotEmpty) {
                  final newPath = result.files.first.path;
                  if (newPath != null && mounted) {
                    final newInfo = LinkedFileInfo(path: newPath, linkedAt: DateTime.now().millisecondsSinceEpoch);
                    await ViewBackendService.updateView(
                      viewId: widget.view.id,
                      extra: jsonEncode({ViewExtKeys.linkedFileKey: newInfo.toJsonString()}),
                    );
                    // Re-init the page (simple approach: pop + reopen or just setState + re-init)
                    if (mounted) Navigator.of(context).pop(); // crude but effective for v1
                  }
                }
              },
            ),
        ],
      ),
    );
  }
}
