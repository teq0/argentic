# Argentic

Argentic is a fractal image generator inspired by the Windows program Sterling2, by Tad Boniecki, which itself was an update to the original Sterling program by Stephen C. Ferguson. It currently targets OSX and iOS.

The app works with one image at a time. Its macOS image window does not use tabs; opening another picture, parameter file or example replaces the current image. Help has its own separate window.

It has the advantage that on systems with a supported GPU it uses Metal Shading Language (MSL) to utilise the GPU for greatly improved performance, plus there are more configuration settings, and you can choose which preferences to save when the app exits.

## Help and features

For a full guide to the controls and functionality, see [FEATURES.md](FEATURES.md), or open **Help → Argentic Help** in the macOS app (**Menu → Argentic Help** on iOS). In-app Help is bundled for offline use and supports searching topics and their contents.

## Saving and reopening fractals

PNG and JPEG exports embed Argentic's fractal settings in XMP metadata. Open the exported image to restore its settings and continue zooming, or press Draw to render it again. PNG is recommended for lossless images. Image editors and sharing services may strip metadata, so retain the original export.

**Edit → Copy Image** (**⌘C**, or **Menu → Edit** on iOS) copies the full-resolution current picture, not a screenshot of the scaled or scrolled view. Copy Image is the only Edit-menu action; the unused standard text-editing entries are removed.

BMP exports contain pixels only. For Sterling2 compatibility, use **Save Sterling Parameters (.loo)…** separately. Existing image/`.loo` pairs can be opened together; automatically finding a neighbouring `.loo` is best effort because of app sandbox permissions. An explicitly opened parameter file overrides embedded settings.

## Examples and first-run image

The **Examples** menu (**Menu → Examples** on iOS) renders the presets bundled from [`examples/`](examples/). A fresh configuration starts from `examples/example1.loo`. Loading an example preserves the current image width, height and anti-aliasing factor instead of resetting them. Saved-setting groups override the corresponding startup values when present.

Add more `.loo` files to `examples/` and rebuild to include them automatically. Optional same-name `.png` files are reference images only and do not determine output dimensions. Menu names come from filenames and are naturally sorted. Loading an example resets the fractal parameters and zoom history while keeping output-quality settings and app preferences such as CPU/GPU rendering.

Without saved image-size settings, the first render is sized for the actual canvas and display backing scale, preserving the preset's aspect ratio, with anti-aliasing Off and a conservative 4-megapixel/4096-per-axis startup limit. A fresh macOS window uses approximately 90% of the usable screen area; iOS leaves window sizing to the system and accounts for the actual available canvas, including multitasking. Resizing later does not automatically re-render. Saved **Image Size and Anti-Aliasing** settings always take precedence; disable that save group and relaunch to try adaptive sizing.

To clear all saved defaults for the macOS developer build, **quit all Argentic instances first**, then run:

```sh
defaults delete "$HOME/Library/Preferences/com.teq0.argentic.plist"
```

Relaunch to use the new startup preset without saved overrides. This deletes Argentic's preferences, not exported images or parameter files. For sandboxed-build storage and a non-destructive alternative, see **Clearing saved defaults** in [FEATURES.md](FEATURES.md) or in-app Help.

## Classic Mandelbrot

Choose **Examples → Classic Mandelbrot** (**Menu → Examples** on iOS) for the standard z = z² + c set, with 256 iterations, escape-time colour bands and a black non-escaping interior. It preserves your chosen resolution and anti-aliasing, and enables aspect fitting to avoid distorting the set.

The new formula is **56**, under **Formula → Classic**, and works on CPU and Metal. Formula **0** is now labelled **Nova/Newton variation (sin/log/tan)**; its computation and ID are unchanged. Formula 56 is Argentic-specific rather than a legacy Sterling2 formula.

## Image display and scrolling

Use **View → Image Display** (**Menu → View** on iOS), or the toolbar's **Fit Image to Window** toggle, to choose **Fit to Window** or **Actual Pixels (100%)**. macOS defaults to Actual Pixels so a low-resolution render is not automatically enlarged; iOS defaults to Fit to keep the whole picture visible.

Actual Pixels maps one image pixel to one physical screen pixel, including on Retina displays, and provides native two-axis scrolling for oversized images. On iOS, swipe to pan in click/tap zoom mode; Rectangle mode reserves drags for selection. The status bar shows display magnification alongside rendered dimensions. Scaling and scrolling do not change the rendered resolution or fractal coordinates. Enable **Image Display** in Saved Settings to remember the mode.

## Click zooming

Choose **Zoom In** or **Zoom Out** in the toolbar zoom-mode menu's **Zoom In/Out** section. The same menu offers Rectangle selection; there is no separate direction toggle beside it.

The **Image → Click Zoom Behaviour** setting chooses whether click zooming centres the clicked point in the next image (the default) or keeps it in place. It applies to both zooming in and out. Previously saved choices are respected.

For finer adjustments, use the toolbar's small zoom-out/in buttons and percentage picker, or **Image → Small Zoom In/Out**. Steps of **1%, 5% (default), 10%, and 25%** adjust magnification around the current centre. Zooming out uses the reciprocal of the zoom-in factor, so opposite steps undo one another's scale change. Each step is also recorded in Back history. The step size is remembered with **Zoom Controls** in Saved Settings.

## Remembering app settings

Open **Dialogs → Saved Settings…** (or **Argentic → Settings…**, ⌘, on macOS) to choose which groups to restore on the next launch: zoom controls, rendering backend, fractal/render, colours, image size/anti-aliasing, view coordinates, inspector, image display, and export format. Only zoom controls are remembered by default. Unchecked groups use built-in defaults next time; unchecking a group does not change the current session.

Selected settings are saved as they change and when the app closes or enters the background. Images and Back history are not restored; the app renders the restored parameters on launch. Save a PNG/JPEG with embedded settings or a parameter file to keep a particular fractal independently of app defaults.

On macOS, use the default **View → Enter/Exit Full Screen** command and the shortcut shown in that menu, or the green window button. Argentic does not add a duplicate command or override the system shortcut.

To remember full screen, enable **Full-Screen State** in **Dialogs → Saved Settings…** (or **Argentic → Settings…**) and choose **Save**. This option is off by default. The main fractal window's native state is captured before quit teardown and restored once the next launch's window is visible and ready. When unchecked, the next launch starts windowed without changing the current window. See [FEATURES.md](FEATURES.md) or in-app Help for details.

## CPU and GPU rendering

**Image → Use Metal GPU Rendering** switches between Metal (on, the default) and CPU software rendering (off). Switching re-renders the current fractal without changing its parameters or zoom history. CPU rendering uses multiple CPU workers and double precision for all computation and colouring; it does not require a Metal device. It is slower, but supports deeper zooms before losing precision. The status bar identifies the selected backend. To remember the choice, enable **Rendering Backend** in Saved Settings.

## Development

### Requirements

- macOS with the full **Xcode** installation and its command-line tools selected. `xcode-select -p` should point to your Xcode installation's `Contents/Developer` directory, not the standalone Command Line Tools directory.
- **Mise** and **XcodeGen**, both available on your terminal's `PATH`. With Homebrew, install them using `brew install mise xcodegen`.
- **Python 3** for regenerating icons and renderer sources. The generated assets and source files are included, so regeneration is not needed for an ordinary build.

The Xcode project and build outputs are intentionally ignored by Git. A fresh clone does not contain `app/Argentic.xcodeproj`; the Mise tasks generate it from `app/project.yml` before building or running app tests.

### Regenerating the icon

The application icon is generated from `icons/argentic.icon.png`, an opaque 1024 × 1024 PNG. After replacing it, run `python3 app/Tools/generate_app_icon.py` on macOS to regenerate the assets in `app/Argentic/Assets.xcassets/AppIcon.appiconset`, then rebuild. The original source image is left unchanged.

The generator uses the Xcode Swift toolchain and `sips`, with no third-party image libraries. For macOS it makes a continuous rounded-square tile (824 × 824 on a transparent 1024 × 1024 canvas) with a subtle shadow, then generates the smaller sizes. The separate iOS asset remains a byte-for-byte copy of the opaque square master, allowing iOS to apply its own mask. Layered icons are not implemented yet.

### Build and run on macOS

From the repository root, use Mise as the canonical build/run workflow. If Mise asks you to trust the repository's configuration, run `mise trust` after reviewing `mise.toml`.

```sh
mise run run
```

This runs **generate → build → launch**, including on a fresh clone. It builds the Debug configuration and opens `app/.build/DerivedData/Build/Products/Debug/Argentic.app`. For a build without launching, use `mise run build`; to generate only the Xcode project, use `mise run generate`.

Quit all running Argentic instances with **Command–Q** before launching a rebuilt app. `open` can otherwise activate an existing process instead of starting the updated executable. Avoid mixing this workflow with other DerivedData locations or using `open -n` to create another instance. The old `app/DerivedData` location is not used by the Mise or VS Code workflows.

### VS Code

Open the repository root in VS Code. Its generate, build and core-test tasks call the corresponding Mise tasks from that directory. **Debug Argentic (macOS)** builds through Mise before launching the executable under `app/.build/DerivedData`; **Debug Argentic (macOS, no rebuild)** uses that same executable without building first. These launch configurations require a debugger extension supporting the `lldb-dap` launch type, alongside Swift language support.

If VS Code cannot find `mise` or `xcodegen`, restart it from a terminal where those commands work, using `code .`.

### Tests and generated renderer sources

Run `mise run test` for the core package tests and `mise run test-app` for the macOS app tests. App tests use the same project-generation step, Debug configuration and DerivedData directory as the build/run workflow. `mise run clean` cleans the package and Xcode build outputs; it is not normally needed between builds.

Both backends use the same formula, orbit reduction, Lyapunov and colour algorithms. `app/Tools/generate_cpu_renderer.py` generates the portable C++ version from the Metal source, generated formulas and shared render header; rerun it after changing those inputs. The original independent C++ oracle and Swift colour reference remain in the tests to check both implementations.

Shared formula IDs are declared in `app/Sources/ArgenticCore/FormulaConstants.swift`. Metal embeds those constants and the CPU generator reads the same declarations; rerun the CPU generator after editing that file as well. IDs are stored in parameter files, so existing values must remain stable.

App tests isolate the main app model from your saved preferences. The native full-screen regression test is opt-in because it opens test windows and changes macOS Spaces. On an interactive Mac, run from the repository root:

```sh
TEST_RUNNER_ARGENTIC_NATIVE_FULLSCREEN_TEST=1 mise run test-app -- \
  -only-testing:ArgenticAppTests/FullScreenWindowTests/testNativeFullScreenPersistsAndRestores
```

Leave the test windows open until the test completes. If macOS does not activate the test app automatically, bring its regression-test window to the foreground; the check requires access to an interactive desktop. It checks native entry, saved-state read-back, quit teardown, and restoration in a fresh window, without changing your saved app preferences.

Since the original source wasn't available this was developed using [ghidra](https://github.com/nationalsecurityagency/ghidra) to firstly reverse engineer the original code.

The C++ source for many of the algorithms is from [Tad Boniecki's website](https://soler7.com/Fractals/Sterling2Formulae.html). It's not clear on the website that this is licensed under GPLv3 however the [Wikipedia entry](https://en.wikipedia.org/wiki/Sterling_(program)) says that it is.
