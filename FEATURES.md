# Argentic Features and Help

Argentic is a macOS and iOS fractal explorer inspired by Sterling2. Explore formulas, change how their orbits are rendered and coloured, zoom into details, and save images with the settings needed to continue exploring later.

This guide is also bundled with the app as offline Help. On macOS choose **Help → Argentic Help** or press **Command–?**. On iOS choose **Menu → Argentic Help**. Search Help by topic name or words in its contents.

Argentic works with one image at a time. On macOS there is one main image window, without window tabs or tab-management commands. Opening a picture, parameter file or example replaces the current image. Help opens in a separate window, not another image tab.

## Getting started

- The app draws a fractal automatically when its main view opens. On a fresh configuration, its starting parameters come from **Example 1** (`examples/example1.loo`). Selected saved-setting groups override that starting preset on later launches.
- Click or tap the picture to zoom in. To zoom out instead, choose **Zoom Out** in the toolbar zoom-mode menu's **Zoom In/Out** section.
- Open **Controls** (the sliders icon) to show the Colour, Fractal and Size panels.
- Choose a **Formula**, a **Render** method, and a **Colour** blend from the menus. Menu choices usually update the image immediately.
- For text-field edits in the Fractal or Size panel, use that panel's **Apply** button. **Draw** also renders the current parameters again.
- Save as PNG to keep a lossless picture with embedded fractal settings, then open that picture to continue exploring.

On macOS use the menu bar. On iOS the toolbar's **Menu** contains File, Edit, View, Examples, Image, Formula, Render, Colour, Dialogs and Help actions. Some toolbar controls may move into the system's overflow menu when space is limited.

## Image display, actual pixels and scrolling

Choose **View → Image Display** on macOS, or **Menu → View → Image Display** on iOS. The toolbar's **Fit Image to Window** toggle (diagonal arrows) switches between the same two options:

- **Actual Pixels (100%)** is the macOS default. Each image pixel occupies one physical display pixel, including on Retina screens. Small images are not enlarged to fill the window; oversized images can be scrolled horizontally and vertically.
- **Fit to Window** is the iOS default. The whole image is scaled to the available area while preserving its aspect ratio. This can enlarge a low-resolution image and make it look soft; it does not create additional image detail.

The status bar shows output dimensions and display magnification. **Fit · 200%**, for example, means the existing pixels are being enlarged twofold for viewing, not that the image has been rendered at twice its resolution. For more actual detail, increase Width/Height in the Size panel and Apply.

Actual Pixels accounts for the screen's backing scale: on a 2× Retina screen, a 1600 × 1200 image occupies 800 × 600 interface points at 100%. Images smaller than the canvas are centred. Scroll bars/indicators appear as appropriate for the platform and its system settings when the image exceeds the visible area.

On macOS, use the scroll bars, mouse wheel or trackpad to explore an oversized image. On iOS, swipe to pan in normal click/tap zoom mode; a tap still performs a fractal zoom. In Rectangle mode, one-finger drags select a region instead of scrolling, so switch back to **Zoom In/Out** mode to swipe-pan. iOS uses native touch scrolling and transient scroll indicators rather than permanent desktop-style scroll bars.

Switching display mode does not render again, change output resolution or complex-plane bounds, or clear Back history. Scrolling moves only the displayed picture, not the fractal coordinates. Existing click and rectangle zoom tools continue to use image-pixel coordinates in either display mode. This setting is separate from the renderer's complex-plane aspect fitting.

**Image Display** in Saved Settings remembers the mode between launches and is enabled by default on first run. When unchecked, the platform default is used. Display mode and scroll position are not stored in exported fractal settings; scroll position is not restored on launch.

## Bundled examples and the starting image

Choose a preset from the **Examples** menu on macOS, or **Menu → Examples** on iOS. **Example 1** is the initial preset when there are no saved parameter overrides. The app renders each example from its .loo settings; it does not simply display the companion PNG.

Loading an example replaces the fractal settings and view, clears rectangle selection and Back history, and renders again. It **preserves the current Width, Height and anti-aliasing factor**, along with app preferences such as the CPU/Metal backend, display mode, click-zoom behaviour, small zoom step and inspector visibility. If parameter groups are selected in Saved Settings, the newly chosen example's values become the current values saved for those groups.

The .loo file is authoritative for the fractal settings, but does not store image size. Bundled companion PNGs, when present, are reference images and do not override your chosen output settings. Examples no longer reset the image to 640 × 480. As with other renders, CPU/GPU precision and sampling can affect the exact pixels.

To add more bundled examples during development, put additional `.loo` files in the repository's `examples/` directory and rebuild the app. Optional same-name `.png` images may be kept as references. The menu discovers .loo files automatically, sorts their names naturally, and turns filenames such as `spiral_study.loo` into **Spiral Study**. No menu-code changes are needed. New files appear after rebuilding and relaunching; the app does not monitor the source directory at runtime. Keep `example1.loo` as the built-in startup preset.

## Startup sizing and screen space

On a fresh configuration, the app waits briefly for canvas layout to settle before choosing output dimensions, using its available area and the display's Retina backing scale. Temporary startup layouts are ignored. It preserves the starting preset's complex-plane aspect ratio instead of stretching the fractal to match a differently shaped screen.

- The first render targets the pixels available to the picture, rather than a fixed 640 × 480 image.
- Automatic startup sizing is capped at **4 megapixels** and **4096 pixels per axis** to keep first rendering reasonably responsive on large or high-density displays.
- Automatic sizing uses a minimum **640-pixel long edge**, avoiding thumbnail-sized output from a compact or temporary viewport. Explicit and restored sizes are not raised to this minimum.
- **Anti-aliasing starts Off (1:1)**. Use the Size panel to increase it if desired.
- Saved **Image Size and Anti-Aliasing** settings take precedence over these automatic defaults. Explicit dimensions already chosen before the first picture also take precedence.
- Automatic sizing runs once for the initial picture, not whenever the window is resized or the device rotates. Further changes are display scaling/scrolling only unless you Apply a new output size.

On macOS, a new window defaults to approximately **90% of the usable screen area**, excluding the menu bar and Dock, and is centred. Normal system restoration of an existing window's size and position can take precedence. On iOS, window sizing is left to the system; the first render uses the actual canvas area, including iPad split-screen or other multitasking layouts, not the full device screen.

These are startup defaults, not manual output limits. The Size panel still supports dimensions up to 8192 per axis. To try automatic startup sizing after previously saving a fixed resolution, uncheck **Image Size and Anti-Aliasing** in Saved Settings, Save, then quit and relaunch.

## Classic Mandelbrot

Choose **Examples → Classic Mandelbrot** (**Menu → Examples** on iOS) for the familiar black Mandelbrot set with coloured escape-time bands. The preset keeps your current image dimensions and anti-aliasing, just like the other examples, and sets:

- **Formula 56: Classic Mandelbrot — z=z*z+c**, starting from z = 0 and iterating z = z² + c, where c is the pixel's complex coordinate.
- **Render 1: log(Iterations escape value)**, with points that do not escape within the iteration limit coloured black. Escape is detected when |z| exceeds 2.
- **256 iterations**, **Blend 1**, RGB order 1, and default channel mixing controls.
- **Julia Off**, **Inside Out Off**, **Coordinates Normal**, **Transform None**.
- Requested view **X −2.5 to 1.5, Y −1.5 to 1.5**, with aspect fitting enabled so the set is not stretched at different output aspect ratios.

Increase Max iterations and Apply for finer boundaries when zooming. Both Metal and CPU rendering support the classic formula. Enabling Julia mode with this formula produces the corresponding quadratic Julia family using Julia X/Y.

The formula is also under **Formula → Classic**, but choosing just a formula retains other current render/colour/Julia settings. Use the bundled example when you want the complete classic setup.

Formula **0** is **Nova/Newton variation (sin/log/tan)**, not the classic Mandelbrot recurrence. Its misleading original “M-set” caption has been corrected without changing its ID or calculation, preserving existing Sterling presets. Formula 56 is an Argentic extension; .loo files using it are not intended for the original Sterling2 application. JSON or PNG/JPEG embedded settings retain all Argentic parameters, including aspect fitting.

## Toolbar and status bar

### Draw, Abort, Back and Reset

- **Draw** (play icon) renders the current parameters. It is disabled while rendering.
- **Abort** (stop icon) cancels the current render. It is enabled only while rendering; any bands already displayed remain visible.
- **Back** (left chevron) restores the previous zoom coordinates exactly and renders them again. It steps through zoom history, rather than estimating an inverse zoom.
- **Reset Coordinates** (home icon) returns to the standard full complex-plane view for the current Julia/non-Julia mode and enables aspect fitting. It clears zoom history; it does not reset the formula, colours or image size. To reload the exact starting example and its view, choose **Examples → Example 1** instead.

Back is disabled while rendering or when there is no previous zoom. Click zooms, rectangle zooms and small zoom steps all enter the same Back history.

### Other toolbar controls

- The small magnifying-glass minus/plus buttons zoom around the current centre. The percentage picker sets their step size.
- **Fit Image to Window** switches between a scaled-to-fit picture and Actual Pixels with scrolling; this does not change render resolution.
- The **Zoom mode** menu groups **Zoom In** and **Zoom Out** under **Zoom In/Out**, with **Select Rectangle** in a separate section. Checkmarks show the active tool; the toolbar icon reflects the selected click direction or Rectangle mode.
- Choosing **Zoom In** or **Zoom Out** switches to click/tap mode and sets the direction for picture clicks. It is a persistent tool choice, not a one-step zoom action. There is no separate zoom-out toolbar toggle.
- **Zoom to Selection** appears in Rectangle mode.
- **Julia Sets** (J icon) toggles Julia mode and renders again. Its tooltip explains the action; the Julia constant is edited in **Controls → Fractal**.
- **Controls** shows or hides the inspector.

The status bar shows rendering progress or a warning. Otherwise it shows the selected CPU/Metal backend, image dimensions and the complex-plane bounds of the rendered view. An image may appear progressively in bands during rendering.

## Click zooming

In the toolbar zoom-mode menu's **Zoom In/Out** section, choose **Zoom In** for picture clicks to zoom by a factor of two, or **Zoom Out** for a factor of one-half instead. Selecting either direction also activates click/tap mode.

Choose **Image → Click Zoom Behaviour** to control the clicked point:

- **Centre Clicked Point** (default) puts it at the centre of the next image.
- **Keep Clicked Point in Place** keeps it at the same relative position in the next image. It does not move the point to the centre.

This preference applies to both click zoom-in and click zoom-out. Zoom requests are ignored while rendering; wait for completion or use Abort first.

## Small zoom steps

Use the toolbar's small zoom-out/in buttons, or **Image → Small Zoom In/Out**, for fine adjustments around the current centre. These actions work independently of the click-zoom behaviour and Rectangle mode.

Choose **1%, 5% (default), 10%, or 25%** with the toolbar percentage picker or **Image → Small Zoom Step**.

The percentage changes magnification: a 5% zoom-in multiplies magnification by 1.05 and divides the visible width and height by 1.05. Zoom-out uses the reciprocal factor, so opposite steps reverse one another's scale change. For an exact restoration of saved coordinates, use Back.

Small zooms require a rendered image or a picture with known parameters. They are disabled while rendering. The chosen step can be remembered with **Zoom Controls** in Saved Settings.

## Rectangle zooming and Back history

Choose **Rectangle** in the zoom-mode picker, then drag over the picture to select an area. Choose **Zoom to Selection**, or double-click/double-tap inside the selection, to render that region. Aspect fitting can expand one axis to keep pixels square.

Choose **Image → Clear Rectangle** to discard the selection without zooming. Drawing also clears the selection.

Back restores saved zoom coordinates and aspect-fitting state without undoing current colour changes or other fractal settings. Switching between CPU and GPU rendering does not clear history.

History is cleared when you reset coordinates, change Julia mode through the menu/toolbar, or successfully open a picture or parameter file. History and rectangle selections are not restored after quitting the app.

## Formulas, render methods and transforms

### Formula

The Formula menu contains 50 implemented Sterling2 formulas in the original numbered groups, plus Argentic's **Classic Mandelbrot** formula 56 in the Classic group. Choosing one renders immediately. Formula numbers are not contiguous: gaps in the original catalog are intentional. Most legacy captions are retained and are not always mathematically precise descriptions. Formula 0's misleading caption is corrected to **Nova/Newton variation (sin/log/tan)**, and Formula 18's group-heading placeholder is replaced with **Newton M-set variation (sin/exp/log)**. These naming corrections do not change the formulas or their IDs.

### Render

The Render menu selects one of 32 methods that reduce a formula's orbit to the values used for colouring. These include iteration counts, orbit traps, statistical reductions, fractal-dimension variants, sine/gaussian variants and Lyapunov renders.

The Render method is different from the **Render** scale slider in the Colour panel: the method changes the computed field; the slider only scales the values passed to colouring.

### Lyapunov

**Render → Lyapunov** provides 20 maps, 21 derivative variants and 9 coordinate mappings. Maps use formulas 101–120. Selecting a map chooses render 30 if the current render is not already 30–32. The Fractal panel also exposes map, derivative and mapping controls.

Choose **Render → Lyapunov → Clear**, or **Clear Lyapunov Settings** in the Fractal panel, to return to ordinary rendering and reset the Lyapunov choices. Clear is a command, not a checked mode, and is enabled only while a Lyapunov map or render is active. It restores the last non-Lyapunov formula and render used in this session (built-in defaults if none have been used), resets derivative and mapping to their defaults and forgets the previous map. Coordinates, colours, image size and anti-aliasing do not change. Any ordinary formula or render chosen while Lyapunov was active is kept. Inactive Lyapunov menu options have no checkmarks or selected numbers.

The Fractal panel's **Enable Lyapunov** switch can temporarily disable Lyapunov without resetting its choices; enabling it again recalls the last map, retaining derivative and mapping settings. The panel's map, derivative and mapping controls are inactive while disabled. Selecting a map in the menu also enables Lyapunov. The resulting formula/render choices are remembered when **Fractal and Render** is enabled in Saved Settings; no new parameter-file fields are required.

### Transform and coordinate flags

**Colour → Transform** applies one of the orbit-point transforms: None, sin/cos variants, arctangent, or a sine/cosine product. Changing it requires a new render, despite its location in the Colour menu.

**Image → Rotate90, Rotate90Mirror, Mirror**, and the Fractal panel's Coordinates picker change the coordinates fed into the formula. They are not rotations or flips of the finished bitmap. Selecting an active Image-menu coordinate flag clears it.

Menu checkmarks identify the current choices. Grouped submenu titles show the active setting number so you can find its group without opening every submenu.

## Colour controls

Open **Controls → Colour** or **Dialogs → Colour**. Most colour changes recolour the stored field without recomputing the fractal's orbit.

- **Blend** selects one of 26 colour-mixing methods, also available in the Colour menu.
- **RGB order** selects one of six channel permutations.
- **Render** scales the field values before colour mixing.
- **Steps** controls per-channel variation through the colour function.
- **Start** changes the per-channel starting levels.
- **Saturation** scales each channel's colour contribution.
- **Offset** shifts each channel's colour control value. Its visual effect depends on the blend.
- **Reset Colours** restores the channel controls and Render scale to defaults; it does not reset the selected Blend or RGB order.

Each channel group has separate Red, Green and Blue sliders. Changes made during rendering are applied when the render finishes. A picture opened from disk must be rendered with Draw before its field can be recoloured; loading settings alone does not reconstruct the field.

## Fractal parameters and Julia mode

Open **Controls → Fractal** or **Dialogs → Fractal** to edit:

- **Max iterations**: the iteration limit. Higher values can reveal more structure but require more work.
- **Stalks & bubbles radius**: the orbit-trap radius used by applicable render methods.
- **Scale factor**: a parameter used by several render methods and Lyapunov maps.
- **Lyapunov Map, Derivative and Mapping**.
- **Julia mode**, **Julia X** and **Julia Y**: Julia mode uses the chosen complex constant rather than deriving it from each pixel.
- **Inside out**: changes the starting coordinates through the formula's inversion behaviour.
- **Coordinates**: Normal, Rotate90, Rotate90Mirror or Mirror.
- **X min, X max, Y min, Y max**: the requested complex-plane bounds, not screen/window coordinates.

Use **Apply** after editing text fields and other controls that do not render immediately. The menu and toolbar Julia toggle renders immediately and, when enabling Julia mode, resets the view to the Julia starting region. Editing Julia mode directly in the panel is applied with the other panel parameters.

## Image size and anti-aliasing

Open **Controls → Size** or **Dialogs → Size**. Choose a size preset or enter Width and Height, select an anti-aliasing factor, then choose **Apply**.

Applied dimensions are limited to **16–8192 pixels per axis**. These are output-image dimensions; resizing the app window only changes how the picture is displayed.

Anti-aliasing options are **Off, 2:1, 3:1 and 4:1**. The renderer computes multiple sub-samples per pixel and averages their colours. Higher factors cost more memory and computation. The renderer may reduce the requested sampling factor to fit its field-memory budget; large images or iteration counts can still exceed available memory.

With complex-plane aspect fitting enabled, the renderer expands the shorter view axis as needed to keep pixels square. Reset Coordinates enables aspect fitting. Sterling .loo imports disable it to preserve their original bounds, which may appear stretched at a different image aspect ratio. This changes rendered coordinates and is separate from **View → Image Display → Fit to Window**, which only scales the existing picture for viewing.

## CPU and Metal GPU rendering

**Image → Use Metal GPU Rendering** selects the rendering backend and renders the current fractal again:

- **On** (default): Metal compute kernels run iteration, orbit reduction and colouring on the GPU using single precision.
- **Off**: multiple CPU workers perform software rendering and colouring using double precision. No Metal device is required for this backend.

Both backends support the formula/render catalog, recolouring, anti-aliasing, progressive display and Abort. Switching preserves parameters and zoom history. Remember the choice by enabling **Rendering Backend** in Saved Settings.

CPU rendering is generally slower, but double precision allows deeper zooms before adjacent pixels become numerically indistinguishable. The backends can produce different results in chaotic or numerically sensitive regions; they are not guaranteed to produce identical pixels.

The status bar warns when the selected backend's precision is inadequate. Rendering still proceeds after the warning. If a GPU image becomes blocky at a deep zoom, try CPU rendering. CPU double precision also has a finite limit. If memory allocation fails, reduce image size, anti-aliasing or iterations.

## Opening pictures and parameter files

Choose **File → Open Picture or Parameters…**. You can select an image, a Sterling **.loo** file, an Argentic **JSON** parameter file, or an image together with its parameter file. Files are identified by their contents, not only their extensions.

- A picture is displayed as saved; opening it does not immediately recompute the fractal.
- A PNG/JPEG exported by Argentic can restore parameters from its embedded metadata. You can zoom it immediately, or use Draw to reconstruct its field for recolouring.
- A parameter file opened on its own is rendered immediately.
- An image without settings can be viewed and exported, but cannot be zoomed as a fractal. Draw replaces it with a render of the current parameters.

When opening an image, settings take priority in this order:

- A parameter file explicitly selected with the picture.
- Settings embedded in the image.
- A same-name .loo or .LOO beside the image, if the app is permitted to read it.

Sandbox permissions can prevent automatic access to neighbouring files. Select the image and .loo together if the companion file is not found. Sterling .loo files do not store image size; when opened with a picture, its pixel dimensions supply the size. Sterling compatibility is best effort and some legacy files may not reproduce their original appearance exactly.

## Saving pictures and fractal settings

### Copy Image

**Edit → Copy Image** (**Command–C**) copies the current full-resolution picture to the clipboard, independent of display scaling or scroll position. On iOS use **Menu → Edit → Copy Image**. You can paste it into another application. The command is disabled until an image is available; while rendering, it copies the current partial picture. PNG is supplied, plus TIFF on macOS for compatibility. Receiving applications may discard embedded metadata.

Copy Image is the app's only Edit-menu command. The default text-editing and Undo/Redo menu entries are not provided; use Back for zoom history.

### Pictures

Choose **File → Save Image As**:

- **PNG** is lossless and embeds Argentic's fractal settings in XMP metadata. It is recommended for keeping a picture and its settings together.
- **JPEG** also embeds settings but uses lossy image compression.
- **BMP (Image Only)** saves pixels without embedded fractal settings.

Embedded settings describe the displayed picture, rather than unapplied edits in the inspector. An imported plain picture with no known parameters is not given invented fractal settings when re-exported. Saving during an incomplete render can save the partial picture currently displayed; wait for completion for a finished image.

Image editors, conversion tools and sharing services may strip metadata. Keep the original exported file, or save a separate parameter file as a backup. Embedded Argentic settings are not a Sterling2 parameter-file format.

### Parameter files

- **Save Sterling Parameters (.loo)…** exports the current parameters in Sterling's text format for legacy interchange. This format does not preserve every Argentic-specific setting.
- **Save Parameters As JSON…** exports the current fractal parameters, including image dimensions, sampling and aspect fitting.

Parameter-file exports describe the current controls, including any changes not yet rendered. They do not contain pixels, app preferences or Back history. Opening them later renders a new image. The app does not automatically write a .loo sidecar alongside an image; export it separately when needed.

## Saved Settings and startup defaults

Choose **Dialogs → Saved Settings…**, or **Argentic → Settings…** on macOS. Select which groups should be restored on the next launch, then choose **Save**. Cancel leaves the selection unchanged. **Select All** and **Select None** are available.

- **Zoom Controls**: click behaviour, zoom mode, click-zoom direction and small zoom step.
- **Rendering Backend**: CPU or Metal GPU.
- **Fractal and Render**: formula, render method, iterations, Julia settings, transforms, coordinate flags, scale factor, trap radius and Lyapunov options.
- **Colours**: Blend, RGB order, Render scale and channel controls.
- **Image Size and Anti-Aliasing**: width, height and sampling factor.
- **View Coordinates**: complex-plane bounds and aspect fitting.
- **Inspector**: visibility and selected panel.
- **Image Display**: Fit to Window or Actual Pixels (100%).
- **Export Format**: the last chosen image export format.
- **Full-Screen State** (macOS only): the main fractal window's native full-screen/windowed state. Enable this to restore it on the next launch; it is not selected by default.

On first run, Zoom Controls, Inspector, Image Display and Export Format are remembered by default. Existing saved group selections are preserved. Unchecked groups use built-in defaults at the next launch; unchecking a group does not change the current image or controls. Selected settings are checkpointed as they change and when the app closes or enters the background, including on iOS where an exit notification is not guaranteed.

Images, Back history, rectangle selections and open export/import dialogs are not restored. The main view draws a new picture from the restored parameters. Save a picture or parameter file to keep a particular fractal independently of startup defaults.

### Clearing saved defaults

To stop restoring selected settings without deleting preferences, choose **Select None** in Saved Settings and **Save**, then quit and relaunch. The app will use the Example 1 startup parameters and default app controls. This retains the choice not to save any groups; it is not a complete first-run reset.

For a complete reset of the macOS developer build, quit **all** Argentic instances before running `defaults delete "$HOME/Library/Preferences/com.teq0.argentic.plist"` in Terminal, then relaunch. Using the explicit file path avoids named-domain lookup failures. This removes all preferences in that file, including the save-group selection and window preferences. It does not delete exported pictures, parameter files or the bundled examples. Do not run the command while an instance is still running, as it can write its preferences back.

Sandboxed builds may instead store preferences in `~/Library/Containers/com.teq0.argentic/Data/Library/Preferences/com.teq0.argentic.plist`; while the app is quit, the corresponding command is `defaults delete "$HOME/Library/Containers/com.teq0.argentic/Data/Library/Preferences/com.teq0.argentic.plist"`.

## Full screen and keyboard shortcuts

### Native full-screen controls

On macOS, use the default **View → Enter/Exit Full Screen** command or the green window button. There is only the system-provided menu command: Argentic does not add a duplicate command or a custom keyboard handler. Use the shortcut displayed by macOS in the View menu; its exact keys can depend on the keyboard, macOS version and your system shortcut settings.

### Remembering full-screen state

- Open **Dialogs → Saved Settings…** or **Argentic → Settings…**.
- Enable **Full-Screen State**, then choose **Save**. This option is off by default.
- Enter or exit full screen using either native control. When you quit, Argentic captures the main fractal window's state before macOS tears down its full-screen presentation.
- On the next launch, the app restores that state after the main window is visible, key and has had a short settling period. Full screen may therefore appear after the window first opens, rather than immediately. If macOS ignores the initial request, the app retries up to three times. The saved preference is retained while restoration is pending or unsuccessful; the initial windowed frame does not count as choosing windowed mode.

If Full-Screen State is unchecked, the next launch starts windowed, even if you quit from full screen. Unchecking it does not take the current window out of full screen. This preference concerns the main fractal window, not the separate Help window, and does not restore the previous image or Back history.

### Keyboard shortcuts

The app's keyboard shortcuts include:

- **Command–O**: Open Picture or Parameters.
- **Command–C**: Copy Image.
- **Command–D**: Draw.
- **Command–[**: Back.
- **Command–0**: Reset Coordinates.
- **Command–Return**: Apply Fractal panel edits when that panel is available.
- **Command–Comma**: Saved Settings on macOS.
- **The shortcut shown beside View → Enter/Exit Full Screen**: toggle full screen on macOS (provided by the system, not overridden by Argentic).
- **Command–?**: Argentic Help on macOS.

Buttons and menus remain available without a keyboard. Toolbar tooltips on macOS explain icon-only controls.
