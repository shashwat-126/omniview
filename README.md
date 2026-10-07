<p align="center">
  <img src="assets/icon/icon.png" width="120" alt="OmniView icon"/>
</p>

<h1 align="center">OmniView</h1>
<p align="center"><b>One private, offline viewer for almost any file.</b><br/>
PDF · Word · Excel · PowerPoint · OpenDocument · images · Markdown · notebooks · code · ZIP</p>

<p align="center">
  <a href="https://github.com/shashwat-126/omniview">github.com/shashwat-126/omniview</a>
</p>

---

## Why OmniView

Opening a `.docx`, a `.xlsx`, a `.pptx` and a `.ipynb` normally means four different apps, and many viewers
upload your documents or track you. OmniView is a single **read-only** viewer where **everything is processed
on your device**: no account, no analytics, no ads, no uploads.

## Features

- **Real rendering, not just text extraction**
  - Word / PowerPoint / OpenDocument documents are rendered page by page (LibreOffice engine → PDF).
  - Spreadsheets open as an Excel-style grid: sheet tabs, column letters, row numbers, fonts, fills, alignment,
    merged cells, frozen panes, real column widths and row heights, number and date formats, zoom.
    A **Print layout** mode shows charts and page breaks.
  - PDFs via PDFium with smooth zoom and a password prompt for protected PDFs.
  - Jupyter notebooks as notebooks: rendered Markdown, code cells with run numbers, outputs and inline images.
- **Fast on big files** – parsing runs off the UI thread; long lists and grids only build what is on screen.
- **Private by design** – see [Privacy](#privacy).
- **Safe by default** – every file is treated as untrusted (size, entry-count and zip-bomb limits; remote images
  in Markdown are blocked; SVG is drawn without running scripts).
- **Pleasant to use** – Material 3 design, light / dark / system themes, recent files, file details sheet.
- **Cross-platform Flutter code** – developed and tested on Android; also runs on the web and Linux desktop
  (see [Platform notes](#platform-notes)).

## Supported formats

| Category | Formats | How it opens |
|---|---|---|
| PDF | `.pdf`  | PDFium viewer |
| Word processing | `.docx` `.doc` `.odt` `.rtf` (+ templates) | Rendered pages |
| Spreadsheets | `.xlsx` `.xls` `.ods` | Styled grid + Print layout |
| Tables | `.csv` `.tsv` | Scrollable grid |
| Presentations | `.pptx` `.ppt` `.odp` | One page per slide |
| Images | `.jpg` `.png` `.webp` `.gif` `.bmp` `.tif/.tiff` `.ico` `.svg` | Zoomable viewer |
| Images (Android only) | `.heic` `.heif` `.avif` | Android decoder (HEIC: 9+, AVIF: 12+) |
| Markdown | `.md` | Rendered |
| Notebooks | `.ipynb` | Rendered notebook |
| Text / code / config | `.txt` `.json` `.xml` `.yaml` `.py` `.java` `.c` `.cpp` `.js` `.ts` `.dart` `.go` `.rs` `.sql` `.log` … | Line-numbered, virtualised |
| Archives | `.zip` | File listing (nothing is extracted) |

> **Fidelity note:** Office/ODF files are rendered by LibreOffice, which is close to Microsoft Office but not
> identical. Fonts the device lacks are substituted, and SmartArt, some charts and animations can differ.

## Privacy

- No account, analytics, advertising, telemetry or crash-report upload.
- OmniView itself makes **no network requests**. All parsing and rendering happens locally.
- "Recent files" stores only file **paths** on the device, and can be cleared in *About & settings*.
- Converted previews are cached in an app-private folder (max 20) and can be cleared. The app deletes its temporary
  copy of your source file as soon as a conversion finishes.
- The release Android manifest should **not** request the `INTERNET` permission (Flutter only adds it to debug and
  profile builds for hot reload). Verify this for your own builds, and audit third-party dependencies.

## Screenshots

_Add screenshots here (home, PDF, Word, spreadsheet grid, notebook, dark mode)._ Use sample files that contain no
personal data.

## Getting started

Requirements: [Flutter](https://docs.flutter.dev/get-started/install) (stable), Android SDK + JDK 17 or newer for
Android builds. For desktop previews of Office files on Linux you also need LibreOffice
(`sudo apt install libreoffice-writer libreoffice-calc libreoffice-impress`).

```bash
git clone https://github.com/shashwat-126/omniview.git
cd omniview
flutter pub get
flutter test
flutter run            # pick a connected Android device, Chrome, or Linux
```

If the repository does not contain the platform folders yet, generate them first:

```bash
flutter create --platforms=android,web --org com.example --project-name omniview .
cp android_native/MainActivity.kt android/app/src/main/kotlin/com/example/omniview/MainActivity.kt  # HEIC/AVIF decoder
```

Build, signing, size-reduction and release instructions are in [docs/BUILD.md](docs/BUILD.md).

**Two Android variants:** *Full* (includes the LibreOffice engine, about 240 MB per ABI) and *Lite* (no engine, far smaller;
Office files show text only or a notice). Build them with `tool/build_full.sh` and `tool/build_lite.sh`.

## Architecture

```
lib/
├── main.dart, app_state.dart       app entry, theme, recent-files state (Riverpod)
├── core/
│   ├── file_detection.dart         magic-byte + extension detection -> FileKind
│   ├── office_converter.dart       LibreOffice engine (Android plugin / desktop CLI), cache, queue
│   └── limits.dart                 size, entry-count and zip-bomb limits
├── renderers/
│   ├── api.dart                    FileRenderer interface + OpenedFile
│   ├── renderers.dart              registry + PDF, image, SVG, Markdown, CSV, text, notebook, ZIP, Office
│   ├── xlsx_parser.dart            XLSX -> sheets, styles, merges, panes (runs in an isolate)
│   └── spreadsheet_view.dart       Excel-style grid (TableView) + Print layout toggle
├── features/                       home, viewer page, about & settings
stubs/                              empty stand-in for the LibreOffice plugin (Lite build)
tool/                               build_full.sh, build_lite.sh
└── shared/file_style.dart          icons, colours, labels, size formatting
android_native/MainActivity.kt      HEIC/HEIF/AVIF decoding via Android ImageDecoder
```

Adding a format = implement `FileRenderer` and add it to the registry in `renderers.dart`.

## Platform notes

- **Android** – primary target. Office/ODF rendering uses the
  [`libre_office_kit_converter_plugin`](https://pub.dev/packages/libre_office_kit_converter_plugin) package, which bundles
  LibreOffice and makes the app large; build per-ABI APKs (see docs/BUILD.md).
- **Linux desktop** – development convenience: Office rendering shells out to a locally installed LibreOffice.
- **Web** – works for formats that need no LibreOffice (PDF, images, CSV, XLSX grid, text, notebooks, ZIP).

## Known limitations

- Password-protected **Office** files (`.docx`/`.xlsx`/`.pptx`, and legacy `.doc`/`.xls`/`.ppt`) cannot be opened yet;
  
- Spreadsheet grid: no cell borders, conditional formatting, data bars or in-cell charts (use Print layout for charts).
- No in-document search, syntax highlighting or bookmarks yet.
- Files are read fully into memory (limit 200 MB); streaming for very large files is not implemented.
- The LibreOffice plugin is young (v0.0.x); review its manifest, native code and licence before shipping.



## Contributing

Issues and pull requests are welcome. Please run `flutter test` before submitting, and do not commit sample documents that contain personal data.

## Third-party software

OmniView builds on Flutter, pdfrx / PDFium, LibreOffice (via `libre_office_kit_converter_plugin`, MPL 2.0), and the
packages listed in `pubspec.yaml`. In the app, *About & settings → Open-source licenses* lists all bundled licenses.
Review their terms before redistributing binaries.

## License

[MIT](LICENSE) © 2026 Shashwat Kumar. Bundled third-party components keep their own licenses.
