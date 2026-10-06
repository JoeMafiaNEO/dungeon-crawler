# Translation Workflow (Issue #33)

## Adding a new language

1. Open `translations/strings.csv` in a spreadsheet editor or text editor.
2. Add a new column header with the language code (e.g., `es` for Spanish,
   `fr` for French, `de` for German). The first row must stay:
   `keys,en,es,fr,de` (add your code to the end).
3. For each key row, fill in the translated string in your new column.
   - Leave a cell empty to fall back to English for that key.
   - Use `%s`, `%d` placeholders where the English has them — translators
     can reorder placeholders (e.g., `%2$s %1$s`).
   - For plurals, Phase 2 will use `tr_n()`; Phase 1 keys are singular.
4. Save the CSV (UTF-8, comma-separated).
5. In the Godot editor: the CSV auto-reimports on `--import` or editor focus.
   This generates `translations/strings.<lang>.translation`.
6. Add the new `.translation` file to `project.godot` under `[localization]`:
   ```
   translations/translations=PackedStringArray(
       "res://translations/strings.en.translation",
       "res://translations/strings.es.translation"
   )
   ```
7. Add the language to the Settings picker in
   `scripts/ui/main_menu.gd` (`_build_settings_panel`, the `locales` array).

## String keys

- Keys are UPPER_SNAKE_CASE (e.g., `SETTINGS`, `SELECT_DESTINATION`).
- New UI strings should use `tr("KEY")` — see the Phase 2 externalization.
- The `tr()` audit test (`_test_locale_infrastructure` in `tests/playtest.gd`)
  verifies the pipeline; run the full suite after adding strings.

## Font note

The SNES pixel font is Latin-only. Phase 1–2 ship Latin-script languages.
CJK/Cyrillic need a fallback font (scoped as a follow-up).
