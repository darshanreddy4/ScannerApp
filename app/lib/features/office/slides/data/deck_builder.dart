import '../domain/slide_presets.dart';
import '../domain/slide_themes.dart';
import 'deck_editor.dart';
import 'pptx_package.dart';
import 'pptx_template.dart';

/// A new presentation made from a starter: its theme and one slide for each entry, filled with the suggested text.
PptxDeck buildPresetDeck(DeckPreset preset) {
  final deck = PptxDeck.fromFiles(newPresentationFiles(theme: deckThemeById(preset.themeId)));
  final editor = DeckEditor(deck);
  for (final spec in preset.slides) {
    final slide = editor.addSlide(layout: spec.layout);
    editor.fillPlaceholders(slide, spec.texts);
  }
  // The empty slide a new file starts with.
  editor.deleteSlide(0);
  return deck;
}
