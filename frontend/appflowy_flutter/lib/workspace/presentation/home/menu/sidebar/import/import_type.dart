import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum ImportType {
  historyDocument,
  historyDatabase,
  markdownOrText,
  csv,
  afDatabase,

  /// Link (not import/copy) a local Markdown or plain text file as a live-editable
  /// document page. The file on disk is the source of truth.
  linkMarkdownOrText;

  @override
  String toString() {
    switch (this) {
      case ImportType.historyDocument:
        return LocaleKeys.importPanel_documentFromV010.tr();
      case ImportType.historyDatabase:
        return LocaleKeys.importPanel_databaseFromV010.tr();
      case ImportType.markdownOrText:
        return LocaleKeys.importPanel_textAndMarkdown.tr();
      case ImportType.csv:
        return LocaleKeys.importPanel_csv.tr();
      case ImportType.afDatabase:
        return LocaleKeys.importPanel_database.tr();
      case ImportType.linkMarkdownOrText:
        return 'Link local Markdown or text file'; // TODO: add to translations
    }
  }

  WidgetBuilder get icon => (context) {
        final FlowySvgData svg;
        switch (this) {
          case ImportType.historyDatabase:
            svg = FlowySvgs.document_s;
          case ImportType.historyDocument:
          case ImportType.csv:
          case ImportType.afDatabase:
            svg = FlowySvgs.board_s;
          case ImportType.markdownOrText:
          case ImportType.linkMarkdownOrText:
            svg = FlowySvgs.text_s;
        }

        return FlowySvg(
          svg,
          color: Theme.of(context).colorScheme.tertiary,
        );
      };

  bool get enableOnRelease {
    switch (this) {
      case ImportType.historyDatabase:
      case ImportType.historyDocument:
      case ImportType.afDatabase:
        return kDebugMode;
      case ImportType.linkMarkdownOrText:
        // gated by FeatureFlag.linkedLocalFiles in the actual handler + desktop check
        return true;
      default:
        return true;
    }
  }

  List<String> get allowedExtensions {
    switch (this) {
      case ImportType.historyDocument:
        return ['afdoc'];
      case ImportType.historyDatabase:
      case ImportType.afDatabase:
        return ['afdb'];
      case ImportType.markdownOrText:
      case ImportType.linkMarkdownOrText:
        return ['md', 'txt', 'markdown'];
      case ImportType.csv:
        return ['csv'];
    }
  }

  bool get allowMultiSelect {
    switch (this) {
      case ImportType.historyDocument:
      case ImportType.historyDatabase:
      case ImportType.csv:
      case ImportType.afDatabase:
      case ImportType.markdownOrText:
        return true;
      case ImportType.linkMarkdownOrText:
        return false; // link one file at a time for clarity
    }
  }
}
