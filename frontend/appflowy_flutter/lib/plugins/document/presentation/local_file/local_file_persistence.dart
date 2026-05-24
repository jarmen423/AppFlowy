import 'dart:async';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/local_file/local_file_info.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy/util/debounce.dart' as af;
import 'package:appflowy/util/throttle.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Handles read / write / roundtrip for a local Markdown or text file
/// that is linked as a live-editable AppFlowy document page.
///
/// This class deliberately does **not** touch the Collab / DocumentService
/// layer — it works purely with in-memory EditorState + dart:io.
class LocalFilePersistence {
  LocalFilePersistence({
    this.debounceDuration = const Duration(milliseconds: 400),
    this.throttleDuration = const Duration(milliseconds: 250),
  });

  final Duration debounceDuration;
  final Duration throttleDuration;

  af.Debounce? _saveDebouncer;
  Throttler? _readThrottler;

  /// Last successfully read/written content (used for cheap external change detection).
  String? _lastKnownContent;

  /// Last modified time we observed from the file (for watcher-driven reload decisions).
  DateTime? _lastObservedMTime;

  /// Load the file from disk and convert it into an EditorState using the
  /// existing Markdown -> Document pipeline.
  Future<EditorState?> loadFromFile(LinkedFileInfo info) async {
    try {
      final file = File(info.path);
      if (!await file.exists()) {
        Log.warn('[LocalFile] Linked file does not exist: ${info.path}');
        return null;
      }

      final content = await file.readAsString();
      _lastKnownContent = content;
      _lastObservedMTime = await file.lastModified();

      final document = customMarkdownToDocument(content);
      final state = EditorState(document: document);

      // Mark the whole document as "from local file" so downstream code
      // (if any) can make decisions. Extra info is cheap and harmless.
      // (The EditorState itself doesn't need special treatment beyond this.)
      return state;
    } catch (e, st) {
      Log.error('[LocalFile] Failed to load ${info.path}: $e\n$st');
      return null;
    }
  }

  /// Serialize the current EditorState back to Markdown and write it to disk.
  /// The write is debounced.
  Future<void> saveToFileDebounced({
    required LinkedFileInfo info,
    required EditorState editorState,
    VoidCallback? onSaved,
  }) async {
    _saveDebouncer ??= af.Debounce(duration: debounceDuration);

    _saveDebouncer!.call(() async {
      await _doSave(info, editorState, onSaved);
    });
  }

  Future<void> _doSave(
    LinkedFileInfo info,
    EditorState editorState,
    VoidCallback? onSaved,
  ) async {
    try {
      final markdown = await customDocumentToMarkdown(
        editorState.document,
        path: info.path,
      );

      // Only write if content actually changed (cheap guard)
      if (markdown == _lastKnownContent) {
        return;
      }

      final file = File(info.path);
      // Ensure parent dir exists (defensive)
      await file.parent.create(recursive: true);
      await file.writeAsString(markdown, flush: true);

      _lastKnownContent = markdown;
      _lastObservedMTime = await file.lastModified();

      onSaved?.call();
      Log.info('[LocalFile] Saved changes to ${p.basename(info.path)}');
    } catch (e, st) {
      Log.error('[LocalFile] Save failed for ${info.path}: $e\n$st');
    }
  }

  /// Force an immediate (non-debounced) save. Useful on close or explicit action.
  Future<void> saveImmediately({
    required LinkedFileInfo info,
    required EditorState editorState,
    VoidCallback? onSaved,
  }) async {
    _saveDebouncer?.dispose();
    _saveDebouncer = null;
    await _doSave(info, editorState, onSaved);
  }

  /// Re-read the file from disk (throttled). Returns the new EditorState or null.
  /// Callers (the page + watcher) decide whether to replace the EditorState.
  Future<EditorState?> reloadFromDisk(LinkedFileInfo info) async {
    _readThrottler ??= Throttler(duration: throttleDuration);

    EditorState? result;
    _readThrottler!.call(() async {
      result = await loadFromFile(info);
    });

    // Give the throttler a moment (not perfect but pragmatic for sync call sites)
    await Future.delayed(const Duration(milliseconds: 50));
    return result;
  }

  /// Cheap check: has the file on disk changed since we last read/wrote it?
  Future<bool> hasExternalChange(LinkedFileInfo info) async {
    try {
      final file = File(info.path);
      if (!await file.exists()) return true; // treat as changed (deleted)

      final mtime = await file.lastModified();
      if (_lastObservedMTime != null && mtime.isAfter(_lastObservedMTime!)) {
        return true;
      }

      // Fallback content check (for filesystems with coarse mtime)
      final current = await file.readAsString();
      return current != _lastKnownContent;
    } catch (_) {
      return true;
    }
  }

  /// Call on dispose / when the linked page is closed.
  void dispose() {
    _saveDebouncer?.dispose();
    _saveDebouncer = null;
    _readThrottler = null;
  }
}
