import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/styles/atom-one-dark-reasonable.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import '../source_workspace.dart';

class ReadOnlySourceEditor extends StatefulWidget {
  const ReadOnlySourceEditor({
    super.key,
    required this.source,
    required this.fontSize,
    required this.tabSize,
    required this.wordWrap,
  });

  final ResolvedSource source;
  final double fontSize;
  final int tabSize;
  final bool wordWrap;

  @override
  State<ReadOnlySourceEditor> createState() => _ReadOnlySourceEditorState();
}

class _ReadOnlySourceEditorState extends State<ReadOnlySourceEditor> {
  late final CodeLineEditingController _controller;
  late final CodeScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText(
      widget.source.contents,
      CodeLineOptions(indentSize: widget.tabSize),
    );
    _scrollController = CodeScrollController();
    final lines = widget.source.contents!.split('\n');
    final start = (widget.source.location.startLine - 1).clamp(
      0,
      lines.length - 1,
    );
    final end = (widget.source.location.endLine - 1).clamp(
      start,
      lines.length - 1,
    );
    _controller.selection = CodeLineSelection(
      baseIndex: start,
      baseOffset: 0,
      extentIndex: end,
      extentOffset: lines[end].length,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.makeCenterIfInvisible(
        CodeLinePosition(index: start, offset: 0),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return CodeEditor(
      controller: _controller,
      scrollController: _scrollController,
      readOnly: true,
      showCursorWhenReadOnly: false,
      wordWrap: widget.wordWrap,
      maxLengthSingleLineRendering: 20000,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      indicatorBuilder: (context, controller, chunkController, notifier) =>
          DefaultCodeLineNumber(controller: controller, notifier: notifier),
      style: CodeEditorStyle(
        fontFamily: 'monospace',
        fontSize: widget.fontSize,
        backgroundColor: Theme.of(context).colorScheme.surface,
        selectionColor: Theme.of(context).colorScheme.secondaryContainer,
        codeTheme: CodeHighlightTheme(
          languages: _languageModesFor(
            sourceLanguage(widget.source.location.path),
          ),
          theme: brightness == Brightness.dark
              ? atomOneDarkReasonableTheme
              : atomOneLightTheme,
        ),
      ),
    );
  }
}

final Map<String, CodeHighlightThemeMode> _allLanguageModes = {
  'dart': langDart.themeMode,
  'java': langJava.themeMode,
  'kotlin': langKotlin.themeMode,
  'javascript': langJavascript.themeMode,
  'typescript': langTypescript.themeMode,
  'python': langPython.themeMode,
  'bash': langBash.themeMode,
  'json': langJson.themeMode,
  'yaml': langYaml.themeMode,
  'sql': langSql.themeMode,
  'swift': langSwift.themeMode,
};

Map<String, CodeHighlightThemeMode> _languageModesFor(String language) {
  final mode = _allLanguageModes[language];
  return mode == null ? const {} : {language: mode};
}
