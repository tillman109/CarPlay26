# CarPlay26 v0.2.83 — Find Queue and Jam in navigation bar

- Searches the native navigation bar first and styles the containing item, since Queue and Jam may live outside the template content view

# CarPlay26 v0.2.82 — Queue and Jam native glass fix

- Finds the visible Queue and Jam title across the Now Playing screen and styles its actual native control with a persistent glass capsule and white text

# CarPlay26 v0.2.80 — Static Home titles

- Keeps the duplicate marquee title and edge fade disabled when a song title fits the Home mini-player

# CarPlay26 v0.2.79 — Queue and Jam glass button

- Matches the Now Playing Queue and Jam button to the Back button’s glass outline and keeps native taps working when Spotify exposes no custom action

# CarPlay26 v0.2.78 — Smooth continuous Home title scroll

- Scrolls long Home mini-player titles at a steady pace in a seamless loop, with a small gap before the title repeats

# CarPlay26 v0.2.77 — Scrolling Home song title

- Adds scrolling for long Now Playing song titles across the Home mini-player and keeps short titles stationary

# CarPlay26 v0.2.76 — Home title scroll attempt

- Added the Home mini-player title ticker

# CarPlay26 v0.2.75 — Home mini-player refresh

- Refreshes Spotify track and artwork on return to the browse screen

# CarPlay26 v0.2.74 — Now Playing Back transition

- Keeps the styled player with its outgoing screen until navigation finishes

# CarPlay26 v0.2.73 — Native dock positions

- Uses the native CarPlay positions for Home, time, battery and connectivity while keeping the larger glass dock and centred apps

# CarPlay26 v0.2.72 — Ranger dock and Spotify Home

- Ranger dock with Home and time on the right, larger glass and app icons, consistent translucent Spotify Home category rows, and caption updates while Home is visible

# CarPlay26 v0.2.71 — Ranger dock, Spotify Home and CarLy

- Places Home and the clock on the left of bottom docks in both drive configurations and measures live status items from the right edge
- Keeps the Spotify Home shelf appearance when the car supplies a limited list and uses the original visible controls for taps and focus
- Draws the Back chevron explicitly in light and dark appearances and restores Spotify’s player when CarLy leaves its lyrics layout

# CarPlay26 v0.2.70 — Spotify touch targets and shared dock

- Gives the shared bottom dock the compact glass appearance across the app grid, Dashboard and apps. Removes Settings from the dock and honours the existing pinned app choice
- Styles pushed Spotify lists, including Library → Playlists, with the same rows and background as the root tabs. Preserves section headings, selection, scroll controls and app-provided accessories
- Uses the round Back button on the left, the live Spotify mini-player on supported browse headers and the native queue action on the right of the full player
- Centres player artwork, metadata, transport and secondary controls over the current blurred cover. The original playback buttons handle touches at the displayed positions
- Adds centre and edge hit checks to the existing Spotify and dock reports

# CarPlay26 v0.2.69 — Spotify portrait layout

- Uses the four iOS 26 browse screenshots and the separate full-player screenshot on the 400 × 416 portrait display
- Places the native tabs at the left. The right-hand player uses Spotify artwork, title, play/pause, next and the host’s Now Playing action when a Spotify track is available
- Matches Home shortcut and shelf spacing, translucent surfaces and the charcoal wallpaper colour field. Recents, Search and Library render their live Spotify list items, with native scrolling and selections
- Arranges the full player’s artwork, song details, transport, progress and available Spotify actions over blurred current artwork
- With Glass Dock enabled, sizes the dock surface, live status icons and app slots. The fourth Settings shortcut uses the shell’s native action when CarPlay makes it available. An explicit third-slot pin takes priority
- The existing Spotify layout report includes browser, playback and geometry fields. Capture the screen being compared after installing the package through the normal build workflow

# CarPlay26 v0.2.68 — Spotify reference styling

- Centres the four native Spotify tabs in a compact teal pill, adjusts shelf captions and spacing, and tints the enabled dark glass dock blue while Spotify is foreground. Reads missing mix titles from legible cover text and shows available artist names beneath the artwork.

# CarPlay26 v0.2.67 — Liked Songs shortcut

- Supplies the Liked Songs shortcut title when its confirmed heart artwork is present and Spotify provides no readable caption.

# CarPlay26 v0.2.66 — Spotify Recents captions

- Reads the Recents template when available and remembers titles matched to Home artwork for the next launch.

# CarPlay26 v0.2.65 — Spotify Home title refresh

- Rechecks visible Spotify Home rows for late-arriving titles and refreshes the title catalogue when Home reloads.

# CarPlay26 v0.2.64 — Spotify Home labels and selections

- Filters identifier-like captions, reads available image titles and reuses Spotify metadata from visited lists. Compacts shelf headings and text-only Home selections.

# CarPlay26 v0.2.63 — Settings and icon

- Groups the iPhone settings into Display & Startup, Dock & Shortcuts, and Home Screen & Dashboard. Spotify and Diagnostics have their own pages
- Adds an information button beside each switch name. Tapping it opens the description over the current page
- Adds the CarPlay26 icon to the Settings list and to the main switch row

# CarPlay26 v0.2.62 — Spotify Home layout

- The Spotify Home Styling switch enables a two-column shortcut grid and six-column shelves. Tile spacing, typography and the continuous teal and blue background follow the supplied iOS 26 reference
- Home reads Spotify’s native image-row model, including artwork beyond the four buttons visible on the 400-point display. Titles and subtitles come from available Spotify lists and accessibility labels
- Tap a shelf heading, or press and hold a shortcut, to open the native full list. Returning to Home can supply up to six real items and their available captions for that section. Extra selections use the section and verify the chosen item against its live list
- Session data stays in memory. The layout report includes per-row counts to identify any content that the installed Spotify version omits
- The release requires on-device comparison in WinPlay

# CarPlay26 v0.2.61 — Spotify Home and dashboard glass finishing

## v0.2.61 — Bundled visual treatment of two already-supported surfaces

- **Spotify Home:** when the existing Spotify Home Styling switch is enabled and Spotify is foreground, soften the four-artwork CPSImageRowCell backing with a translucent three-stop glass-like glaze and very subtle edge highlight rather than the prior completely flat transparent surface. The native artwork, list headings, scroll handling, selection controls and navigation are unchanged
- Keep the known opaque CPSTableView and content canvas clear so the new row finish remains translucent; scope styling to the already-validated Spotify CarPlay four-artwork rows and remove our glaze when Home Styling is disabled
- **Dashboard:** add a restrained translucent directional sheen over the *existing native MTMaterialView* inside only the two verified lower DBWidgetView cards, using the current Glass Dashboard Cards preference. No extra card, offset, content overlay, map change or hit-test changes
- Keep the established dashboard gradient, dock, launcher, media controls, native widgets and app-grid geometry; do not attempt iOS 26 widgets or Live Activities on the iOS 16 host
- Keep the v0.2.60 animated Spotify selection capsule, native tab actions, Now Playing, rapid switching, Reduce Motion handling and independent Home Styling/Pill Navigation controls unchanged
- This is an **iOS 26-inspired cosmetic approximation**, not Apple's private iOS 26 Liquid Glass implementation. The existing switches allow reversing each family of changes; dashboard toggles may require a CarPlay restart as previously
- Retain public-build-safe wallpaper packaging and existing Sileo publication/retention workflows without modification
- **Validation required:** GitHub compile and WinPlay dark/light screenshots for Spotify Home with Home Styling on/off, Dashboard Glass Cards on/off, and checks of Maps, Now Playing and Spotify tab interactions

# CarPlay26 v0.2.60 — Animated Spotify pill tab selection

## v0.2.60 — Smooth, interruptible native-tab selection capsule

- Animate the existing rounded selected-tab indicator over 0.26 seconds with an ease-in/out transition whenever Spotify's four native tabs change selection
- Support rapid taps with `UIViewAnimationOptionBeginFromCurrentState`, allowing a new selection to redirect the ongoing movement instead of visibly snapping
- Do not animate when the pill first appears, when Now Playing initializes, when the tab bar changes geometry, or when the existing selection is redrawn during UIKit layout
- Respect the iOS Reduce Motion accessibility setting by moving immediately without animation
- Cancel indicator animations and reset per-bar selection history on disable/foreground loss, preserving reversible stock tab presentation
- Preserve the v0.2.59 balanced insets, pressed-tab feedback, active label styling, four original native button actions, independent Now Playing, Home Styling, dock, wallpaper build restrictions, and Sileo publishing configuration
- **Validation required**: build through the public repository and test Home → Library, Library → Search, rapid alternate taps, app reopen, switch off/on, and Reduce Motion enabled in WinPlay

# CarPlay26 v0.2.59 — Spotify pill feedback and symmetric spacing

## v0.2.59 — Bundled navigation improvements (single build)

- Public-build packaging update: the automatic GitHub Actions package includes 12 locally generated solid-colour PNGs and **does not download or bundle the 24 archived Apple-patterned wallpaper JPEGs**; those six wallpaper IDs gracefully fall back to native CarPlay wallpaper imagery because `CP26WallpaperImage` returns `nil` when assets are absent
- The original archived artwork download remains an **explicitly private, permission-dependent opt-in** (`CP26_INCLUDE_ARCHIVED_WALLPAPERS=1`), never set by the public build workflow; previous public Sileo builds may still contain the older assets and require separate review
- Real v0.2.58 screenshot confirmed that suppressing UIKit's native tab highlight also removed visible touch-down feedback; add a *separate, temporary rounded blue-tinted press capsule* behind the native buttons, while retaining the existing persistent selected-tab capsule
- Track the native `UIControl.highlighted` state from the already-hooked `UITabBarButton` state transitions; refresh pill visuals immediately on press and release without replacing touch handling, navigation targets or original tab button frames
- Fix an actual first/last-tab spacing error: the 0.2.58 selection indicator reached both outer pill edges; use mathematically symmetric 4-point interior horizontal padding plus 4-point top/bottom insets for all four tabs, including the edge tabs
- Reapply the selected/pressed tab's native text colour after UIKit selection and highlight changes, preventing a temporary dark/black label override during interaction
- Keep stock highlight suppression, verified early pill appearance before Now Playing, independent Now Playing control, native 44-point hit targets, live Spotify Home Styling, reversibility, diagnostics, wallpapers, dock, Airaw, and all other settings unchanged
- Conserves GitHub Actions usage by combining these related visual and interactive refinements into one staged package update; no workflow or Sileo retention-policy changes
- **Requires GitHub compilation and device/WinPlay testing**: press and hold Home/Recents/Search/Library in light and dark modes, verify press feedback and equal capsule padding, switch among tabs, and disable to verify full native restoration

# CarPlay26 v0.2.58 — Fix pressed tab highlights over Spotify pills

## v0.2.58 — Native tab press/selection highlight suppression

- The real v0.2.57 pressed-state screenshot exposed blue and grey iOS 16 UITabBarButton highlight surfaces bleeding through the custom iOS 26 pill, sometimes making two tabs look selected at once
- Target only each native button's observed non-interactive, childless, approximately 76x39 UIView with 8-point corners, using strict CarPlay scene, confirmed Spotify foreground, verified four-tab bar and associated pill guards
- Hide the stock visual highlight on initial style application and reapply after UITabBarButton layout, highlighted-state and selected-state transitions; leave the actual button frames, touch targets, tab routing and Now Playing control unchanged
- Snapshot/restore the stock highlight subview's visibility and alpha when Pill Navigation is disabled or Spotify loses foreground focus, alongside the existing icon/label restoration
- Slightly reduce the inner selection capsule to 28-point height with a 14-point corner radius, retaining the tested centred labels and outer pill geometry
- Keep v0.2.57's early-pill support (with or without Now Playing), v0.2.53 live Home Styling, all diagnostics, dock, wallpapers and Airaw behaviour unchanged
- **Requires GitHub compilation and WinPlay testing:** hold a finger on each tab, switch between all four, disable/re-enable navigation, and check Now Playing

# CarPlay26 v0.2.57 — Spotify pill navigation no longer waits for Now Playing

## v0.2.57 — Render Spotify's pill tabs before the Now Playing control appears

- Verified from v0.2.56's source that `CP26SpotifyNavButtons` explicitly required `CPUINowPlayingButtonWrapperView`, even though Spotify renders the Home/Recents/Search/Library tabs before the separate Now Playing control appears
- Remove the wrapper-presence requirement while keeping the four native `UITabBarButton` classes, four matching native tab items, observed CarPlay frame limits, button dimension checks, contiguous positions, and the already established Spotify-only foreground and CarPlay scene guards
- Accept the native four-tab row when it initially fills the bar (400 points) or reserves space for the later Now Playing control (about 362 points); once Now Playing exists, additionally verify it adjoins the native tabs with the expected width
- Leave tab hit areas and actions native, keep the now-working vertical label centering and selected capsule, and make no changes to Now Playing itself
- Preserve v0.2.53 live toggles, clear Home panels, diagnostics, dock, wallpapers, Airaw and all other UI
- **Requires GitHub compilation and on-device WinPlay testing**: first-open transition, normal tab switching, selected highlight and Now Playing when it becomes available

# CarPlay26 v0.2.56 — Faster Spotify navigation startup and centred labels

## v0.2.56 — Apply Spotify pill presentation earlier without weakening app isolation

- On CarPlayTemplateUIHost launch, request foreground-app state from the CarPlay shell on the next available main-queue turn instead of waiting one second for the first request; add a quarter-second retry, preserving the existing 1/4/7-second fallback for cold starts
- Do not infer Spotify foreground status or style unrelated applications before the shell confirms `com.spotify.client` is active; complete first-frame styling cannot be guaranteed until on-device testing
- Centre the existing UITabBarButton labels vertically within their native 44-point hit areas, instead of using a full-height label frame
- Guard a native UITabBarButton post-layout correction so late UIKit layout cannot return labels to the original bottom-aligned position; only touch four-tab navigation bars already verified as Spotify and already carrying the tweak's capsule
- Leave the pill and selection geometry, independent Now Playing control, four original tab actions and their hit targets unchanged
- Preserve the confirmed live Home Styling and Pill Navigation switches, native panel transparency, original-style restoration, diagnostic capture, wallpapers, dock, Airaw and other preferences
- **Requires GitHub compilation and WinPlay testing** to confirm the first-open delay and label alignment, the selected indicator, all four tabs and Now Playing

# CarPlay26 v0.2.55 — Native Spotify pill navigation (experimental)

## v0.2.55 — First visible iOS 26-style navigation experiment

- v0.2.54's real device report identified a native 400x44 `UITabBar` with four `UITabBarButton` items spanning x=0..362 and a separate `CPUINowPlayingButtonWrapperView` at x=362..400; controller selected index 0
- Adds an **independent, off-by-default** `iOS 26-Style Pill Navigation` switch on the Spotify settings page, preserving the already working Home Styling live switch
- Inside the native Spotify tab bar, hides each tab's icon visually, vertically centers its existing text label, and adds a rounded translucent navigation capsule and selected-tab highlight; all original buttons remain in place with their native hit targets/actions and the separate Now Playing control is untouched
- On selection changes, refresh the native selected item capsule without replacing navigation handlers; snapshot and restore label frames/fonts/colours and icon alpha when switching off or leaving Spotify
- Reuses the proven shell-to-template-host foreground signal, now relaying Home and Navigation mode states separately so each switch can be enabled or disabled independently without a full respring
- Restricted to the observed four-tab CarPlay template geometry and a verified Now Playing wrapper, never the phone UI or other CarPlay apps
- Preserves the v0.2.53 transparent panels, diagnostic report, wallpaper, dock, Airaw, playback, media buttons and other settings
- **Experimental until compiled and tested in WinPlay**: test Home → Recents → Search → Library with each navigation switch on and off, and confirm Now Playing remains clickable

# CarPlay26 v0.2.54 — Spotify navigation diagnostics

## v0.2.54 — Inspect native Spotify navigation controls (diagnostic only)

- Extends the existing **Capture Spotify Layout Report** button to include a bounded, read-only inventory of `CPSNavigationBar`, native tab-bar views where present, their child view classes, frames, screen positions, visual backings, control selected/highlighted/enabled states, and label geometry without reading any label text
- Records `CPSTabBarViewController` child-controller counts separately from `CPSNowPlayingViewController`, matching the verified four-main-controllers plus separate Now Playing presentation on iOS 16.4.1
- Examines only the CarPlay scene in `CarPlayTemplateUIHost`, with fixed traversal limits and no new hooks, preferences, actions, layout changes or polling
- Preserves the **confirmed v0.2.53 live Spotify Home Styling switch** and the existing clear-panel effect exactly, along with Spotify playback, navigation, Airaw, wallpapers and the CarPlay dock
- **Requires compilation and device testing:** capture on Spotify Home, then optionally while Now Playing is visible, and compare the navigation diagnostic sections before attempting iOS 26-style pills

# CarPlay26 v0.2.53 — Live Spotify Home Styling switch

## v0.2.53 — Apply Spotify Home Styling without respring

- The Spotify settings page now uses explicit read/write selectors for the existing `SpotifyHomeStyling` preference key, saving it and sending a Darwin notification immediately when the switch changes
- The two notification names carry the requested ON/OFF state, avoiding a race where the CarPlay process reads an outdated preferences cache
- While CarPlay26 is enabled, the CarPlay shell installs its existing `DBAppDockViewController` observer even if Spotify styling was OFF when the process started, so the native `activeBundleIdentifier` can be used when enabling styling live
- The shell relays the confirmed Spotify foreground/background state to `CarPlayTemplateUIHost`, which applies or restores the already verified v0.2.52 clear artwork rows and transparent table backing
- No changes to the Spotify content, playback, tab navigation, artwork sizes, wallpaper, dock, Airaw grid, diagnostic capture or other preference keys
- **Requires GitHub compilation and device verification**: toggle ON then OFF while Spotify Home remains visible in WinPlay, with no CarPlay Services restart or respring; also switch to another CarPlay app to confirm no spillover

# CarPlay26 v0.2.52 — Spotify Home clear-panel visual test

## v0.2.52 — Correct the colour-matching mistake

- Confirmed by v0.2.51 reports that the Spotify Home artwork-row background, its CALayer, CPSTableView and its enclosing UIView all become transparent when styling is enabled
- The original 12%-opacity charcoal colour was nearly indistinguishable from stock grey on the light host background: 0.88 × (240,239,245) + 0.12 × (56,56,56) ≈ (218,217,222), compared with stock panel (218,217,223)
- When **Spotify Home Styling (Experimental)** is enabled, use a *fully clear* fill for only the confirmed four-artwork `CPSImageRowCell` panels, allowing the underlying host background through rather than recreating opaque grey
- Also mark these clear cells as non-opaque; record and restore each original `opaque` flag and `backgroundColor` along with the existing reversible Spotify foreground logic
- Keep the existing table/canvas transparency, Spotify-only foreground verification, read-only reports, controls, four-column layout, Airaw, launcher, dock and wallpapers unchanged
- This is a visible-background experiment, **not** an iOS 26 wallpaper or blur recreation; compilation and iPhone/WinPlay verification required

# CarPlay26 v0.2.51 — Spotify Home backing diagnostics

## v0.2.51 — Identify the remaining native grey panel rendering

- Extend the existing **Capture Spotify Layout Report** action to inspect visible `CPSImageRowCell` backing structures in `CarPlayTemplateUIHost`
- Record `UITableViewCell.backgroundConfiguration` presence and colour, `backgroundView`, `selectedBackgroundView`, `contentView`, relevant CALayer backgrounds and a bounded number of sublayers
- Record only classes, geometry, colour, opacity and layer properties — never song names, artwork pixels, playlist contents or contacts
- Keep the Spotify Home Styling experiment unchanged and **off during testing**; no new visual hooks or changed colour values
- Preserve CarPlay26 dock, wallpapers, appearance preferences, Airaw support and existing Spotify diagnostic capture paths
- **Requires compilation and on-device report verification** — the root cause of the grey panel surface is not yet established

# CarPlay26 v0.2.50 — Spotify Home translucent backing correction

## v0.2.50 — Reveal Spotify Home artwork-row tint (experimental)

- Confirmed by the v0.2.49 on-device diagnostic report: `CPSImageRowCell` background was correctly changed to `rgba(0.22,0.22,0.22,0.12)`, but the screenshots still appeared identical because native `CPSTableView` and its immediately enclosing `UIView` were opaque
- Only after a Spotify foreground-app signal and the existing four-artwork-row geometry guard, make those **two** confirmed native backing views transparent and non-opaque so the row tint can show the underlying compositing surface
- Save and restore original native background colours and opaque flags when Spotify loses focus; leave the stock behaviour unchanged when **Spotify Home Styling** is off
- Preserve Spotify playlists, image count/size, text, hit targets, tab controls, Now Playing, the existing read-only report, dock, other apps, dashboard, Airaw, wallpapers and every existing preference key
- This remains an experiment: iOS 16 may expose a solid host backdrop rather than the iOS 26 wallpaper material. **GitHub compilation and device/WinPlay visual testing required**

# CarPlay26 v0.2.49 — Spotify Home appearance test

## v0.2.49 — Initial Spotify panel tint

- Added the opt-in Spotify Home Styling preference and foreground-app checks
- Confirmed by device diagnostics that the `CPSImageRowCell` background changed correctly, but the result was not visible behind opaque native surfaces

# CarPlay26 v0.2.49 — Spotify Home artwork-row experiment

## v0.2.49 — Reversible, foreground-gated Spotify Home styling

- Added **Spotify Home Styling (Experimental)** to the existing Spotify settings page, **off by default**
- In the CarPlay process, reads the previously verified native `DBAppDockViewController.activeBundleIdentifier` getter to confirm `com.spotify.client` is the foreground app
- Sends only active/inactive Darwin notifications to `CarPlayTemplateUIHost`; its styling code never reads Spotify's app data, track metadata, artwork, contacts or personal text
- Targets native `CPSImageRowCell` panels only when their geometry and four-button artwork structure match the v0.2.48 Home diagnostics; changes the opaque grey background to a faint translucent material while preserving the original frame, corner radius, artwork, labels, navigation and touch areas
- Remembers original cell colours and restores them when Spotify is no longer foreground; native CarPlay home/dashboard, other media apps and Airaw are not styling targets
- No changes to the four-column artwork layout, Spotify templates, playback controls, queue or Now Playing presentation
- Keeps the existing Spotify report capture, the dock, wallpaper assets, diagnostics and other preference keys unchanged
- **Requires GitHub compilation and on-device WinPlay testing** — turn on the switch, restart CarPlay Services while parked, compare Home panels against the same screenshot, then switch to another media app and back. The appearance is experimental and may not resemble iOS 26 until the underlying table background is understood

# CarPlay26 v0.2.48 — Spotify template diagnostics

## v0.2.48 — Spotify settings page and read-only renderer report

- Added a dedicated Spotify page to CarPlay26 Settings under **App Appearance**, preserving all existing settings and preference keys
- Added **Capture on Host Launch** (off by default) and **Capture Spotify Layout Report** for the `CarPlayTemplateUIHost` process
- Uses a one-shot Darwin notification for manual capture, avoiding dependence on cross-sandbox preference reads in RootHide
- The bounded view-tree report includes UIKit class names, frames, dimensions, background colours, opacity, corner radii and controller class names, but never reads track titles, playlists, contact names, messages or album artwork
- Saves the report to a writable location owned by CarPlayTemplateUIHost; subsequent captures overwrite it
- Does not alter Spotify, the template host's rendering, the CarPlay dock, dashboard, wallpapers, layout, Airaw, or media playback
- **Requires compilation and iOS 16.4.1 device testing** — the diagnostic build does not yet implement Spotify's iOS 26 appearance

# CarPlay26 v0.2.47 — Smaller wallpaper package

## v0.2.47 — Wallpaper optimisation (source update)

- Compresses all six patterned iOS 26 wallpaper colourways in both light/dark appearances to 2048×2048 JPEG for full images and 512×512 JPEG for thumbnails
- High-fidelity JPEG quality 92 with 4:4:4 colour sampling and optimised encoding; the original 4000×2182 source PNG files, centre crop and downsampling are unchanged
- Keeps the three solid-colour wallpapers and their light/dark thumbnails as small, lossless PNGs
- Updates only the central `CP26WallpaperImage` loader to request JPEG for patterned images while retaining a legacy PNG fallback; native wallpaper selection, persistent identifiers, caches, light/dark switching, and image dimensions stay the same
- Changes the existing build workflow only to verify that the package contains exactly 24 JPEGs and 12 PNGs; all build and publishing behaviour is otherwise unchanged
- No change to launcher, dashboard cards, notification badges, labels, dock, diagnostic controls, or Airaw
- **Requires compilation and on-device confirmation** of all six pattern colours in the picker, full screen, light and dark modes

# CarPlay26 v0.2.46 — App-aware launcher


## v0.2.46 — Launcher icon inside apps

- Extends **iOS 26 App Launcher Icon** to show the nine-square grid while Phone, Maps, Spotify, Messages or any other foreground CarPlay app is open, as well as on the Dashboard
- Keeps the outlined rounded-square glyph exclusive to the Home app-grid pages
- Reads the iOS 16 native `DBAppDockViewController.activeBundleIdentifier` state after app switches and combines it with the existing native Dashboard page geometry; no app-launch interception, gesture changes, extra polling, or assumptions about fixed page offsets
- Preserves the existing 0.22-second glyph crossfade, native Home button hit target, badge-safe icon rims, icon labels, card glass, wallpaper assets and Airaw grid settings
- **Test required:** open an app, return to Home, enter Dashboard and switch apps in WinPlay before relying on the new state detection

## v0.2.45 — Native-material dashboard tint and sandbox-safe diagnostics
**Requires device verification** — The visible Glass Dashboard Cards effect now targets the native MTMaterialView inside each lower dashboard widget rather than the opaque-covered outer widget. It uses an in-place translucent three-stop tint, without a second outline or manually added inset/corner shape, and should leave system card geometry, blur and controls intact. The main diagnostic log now uses process-owned cache/tmp fallbacks (and records its successful destination in the system log), following the existing wallpaper relay approach. v0.2.44's badge masking and v0.2.42's approved icon label styling remain untouched. Confirm that enabling Glass Dashboard Cards visibly changes the cards without adding another rim; inspect the new report if necessary.

## v0.2.44 — Single-surface dashboard cards and badge-safe icon rims
**Requires device verification** — Uses the outer native DBWidgetView as the decorative glass target for the two lower dashboard cards instead of drawing a second rounded panel inside MTMaterialView. The added glass layer has no extra border, is beneath the native controls and does not alter map, widget placement, or touch handling. Badge-aware icon rims now stay visible except exactly where the native notification badge overlaps the rim; the native badge remains unmodified. Preserves v0.2.43's home/dashboard launcher crossfade, v0.2.42's approved light/dark label backgrounds, Airaw layout, dock and wallpapers. Check card edges and badge arrival/removal on device; compilation alone is insufficient.

## v0.2.43 — Launcher transition, badge-safe icon rims, dashboard cards
**Requires build/device verification** — The previously prepared (not yet installed) 0.2.43 launcher animation remains: the outlined square on the app grid crossfades to a nine-square Dashboard icon without replacing the native home button. The icon rim now stays below native icon accessory views; it is suppressed while the icon cell exposes a visible notification badge, so the rim cannot draw across badge text. The two lower dashboard cards in light appearance receive a less washed-out slate-blue tint and quieter outlines, while the native map, widget/card geometry, media actions, dark labels, existing light label backdrops, dock, wallpaper and Airaw grid are untouched. The Home tile's saved places and the media tile's playing state remain native and depend on available data. Test badge arrival/removal and dashboard transitions in WinPlay.

## v0.2.42 — Balanced light labels and refined dashboard glass
**Device verification required** — Light-mode icon label backdrops use intermediate smoky-grey opacity, retaining text-measured capsule widths, centred placement and unchanged native white app titles. Both fallback and native material paths updated; all dark-mode label colours untouched. Lower-dashboard native material cards gain a very subtle cool glass gradient, blue-grey hairline and 20-point decorative rounding. Media control decorative borders are toned down (controls remain native). No map style changes, layout changes, new hooks, or new preferences. Other CarPlay26 and Airaw functionality remains untouched. Compare light/dark grid and dashboard screenshots before further adjustments.

## v0.2.41 — Higher contrast labels in light mode
**Device verification required** — Increased the dark smoky-grey opacity of the glass label backing only when both the selected glass appearance and native CarPlay appearance are light. Native-material and fallback-label paths use the same treatment. Retained white native text, measured/centred label widths, label border treatment, all dark-mode colours, icon arrangement, Airaw compatibility, dock, dashboard and wallpaper implementation. No new switch; existing Glass Icon Labels controls the change.

## v0.2.40 — Adaptive-width glass icon labels
**Experimental — device verification required** — The native material or fallback backdrop now measures each icon's own accessible title using its native label font when available, adds balanced horizontal padding and centres the capsule in the existing label slot. Short titles such as Maps should have narrower backdrops than longer titles such as Messages. Existing Airaw grid spacing, native text, icons, dock, dashboard glass, wallpapers, and other preferences are unchanged. A native mask owned by another tweak is never overwritten; an unavailable title leaves the existing backing width intact. No new preference switch — uses Glass Icon Labels.

## v0.2.39 — Subtle iOS 26 label and dashboard glass
**Development update — device testing required** — Refined the existing Glass Icon Labels treatment in both native-material and fallback-label paths with darker muted fills and thin, low-contrast borders. Glass Dashboard Cards now uses a less saturated background tint, a more subtle edge, and up to 16-point fallback corner rounding (without changing native layout or clipping). Glass App Icon Rims, Glass Media Controls, dock, launcher and wallpaper logic are unchanged. Settings switches and stored preference keys are preserved. No Airaw grid hooks were added.

## v0.2.38 — Experimental Other Functions (development branch)
**Unverified prototypes; not released to Sileo** — Added optional switches for (1) hiding splash artwork in the separate CarPlaySplashScreen process without terminating it, (2) requesting dark UIKit appearance only in Apple Maps CarPlay windows, and (3) hiding the CarPlay-only _DBCornerRadiusWindow overlay when present. All default OFF, may have no effect where the receiver or OS owns rendering, and require device testing to validate. No bypass of the driving-related Phone keypad access restriction. Airaw must not enable corresponding features simultaneously during testing


## v0.2.37 — iOS 26-style app launcher icon
**Awaiting device test** — Added an opt-in visual-only native `DBStatusBarHomeButton` outline, matching the rounded-square iOS 26-style launcher glyph. No changes to app shortcuts, the dock capsule, wallpaper selection or hit targets. The option defaults off and requires a CarPlay Services restart. Based on v0.2.15 dock inventory from iOS 16.4.1; confirm visually on v0.2.37

Entries describe what was built or confirmed, not a promise that experimental features work on all devices

## v0.2.36 — Stock iOS 26 CarPlay wallpapers + Settings pages
**Awaiting build/device confirmation** — Replaced nine native image wallpaper slots with the six archived iOS 26 colourways (light/dark PNG pairs) and three flat-colour choices, removed all diagnostic test banners and added dedicated Diagnostics and Changelog pages

Source images are supplied by a third-party stock wallpaper archive; format/resolution is checked at build time, but authenticity cannot be cryptographically confirmed against Apple firmware

## v0.2.35 — Home-screen wallpaper test
**Confirmed** — In-memory green test banner appeared on the native CarPlay home screen after respring and disappeared when a different wallpaper was selected

## v0.2.34 — Home-screen renderer trace
**Observed** — Confirmed CarPlayWallpaper creates the selected wallpaper controller and displays a 2048×2048 image in its own CarPlay window.

## v0.2.33 — Picker and preview proof
**Confirmed** — Successfully overlaid a blue test banner on the top-left wallpaper thumbnail and preview; the actual home screen remained unchanged.

## v0.2.32 — Image-source tracing
**Confirmed** — Identified the 11 stock wallpaper IDs, 512×512 picker thumbnails and 2048×2048 full images in CRSUIWallpaper.

## v0.2.31 — Wallpaper model inspection
**Diagnostic** — Inspected CRSUIWallpaper and preference methods, with synchronous, read-only model hooks.

## v0.2.30 — Delayed wallpaper checks
**Diagnostic** — Added delayed native class detection and independent capture attempts.

## v0.2.29 — Direct wallpaper hooks
**Diagnostic** — Tested native wallpaper controller hooks and gathered the first focused CarPlay class inventory.

## v0.2.28 — Automatic wallpaper capture
**Diagnostic** — Added automatic native wallpaper screen capture attempts without relying on a shared setting.

## v0.2.27 — Grouped diagnostic switches
**Settings and diagnostic** — Consolidated diagnostic switches on the main page and added Capture Wallpaper Report.

## v0.2.26 — Focused wallpaper probe
**Diagnostic** — Narrowed inspection to native CarPlay wallpaper picker and display classes.

## v0.2.25 — Diagnostic write locations
**Diagnostic** — Improved fallback output paths for wallpaper reports.

## v0.2.24 — Wallpaper handshake
**Diagnostic** — Added a deterministic startup report and explicit requests to wallpaper processes.

## v0.2.23 — Wallpaper relay
**Diagnostic** — Tested a cross-process diagnostic relay.

## v0.2.22 — Wallpaper startup probe
**Diagnostic** — Added process startup diagnostics and sandbox-aware report paths.

## v0.2.21 — Native wallpaper research
**Diagnostic** — Introduced read-only hooks to inspect the official CarPlay wallpaper picker.

## v0.2.20 — iOS 26-style dock finish
**Confirmed** — Added optional Liquid Glass-inspired reflections and highlights to the working dock.

## v0.2.19 — Pinned dock app fix
**Confirmed** — Successfully pinned Messages in the right-hand native dock shortcut position, retaining other shortcuts.

## v0.2.18 — Pinned dock investigation
**Experimental** — Introduced an initial pinned shortcut experiment and supporting instrumentation.

## v0.2.17 — Dock shortcut analysis
**Diagnostic** — Inspected the native dock buttons and recent-app selection methods.

## v0.2.16 — No-flash dock fix
**Confirmed** — Fixed white background flashes between CarPlay app pages by guarding the native dock backing.

## v0.2.15 — Dock transition refinement
**Experimental** — Continued testing the independent glass dock backing and transition behaviour.

## v0.2.14 — Independent dock material
**Experimental** — Tested a distinct glass dock material while retaining native controls.

## v0.2.13 — Dock clipping and restart
**Experimental** — Updated glass dock capsule clipping and added Restart CarPlay Services.

## v0.2.12 — Dock transition adjustments
**Experimental** — Refined the glass dock transition behaviour.

## v0.2.11 — Dock backing transparency
**Experimental** — Tested transparent backing changes to the native dock.

## v0.2.10 — Glass dock refinements
**Experimental** — Iterated on the experimental native dock capsule and its rendering.

## v0.2.9 — Experimental glass dock
**Experimental** — Introduced a native glass dock appearance experiment.

## v0.2.8 — Dock structure diagnostics
**Diagnostic** — Expanded native dock and status bar inspection.

## v0.2.7 — Respring button
**Confirmed** — Added a working Respring action to CarPlay26 settings.

## v0.2.6 — Dashboard updates
**Confirmed** — Improved immediate glass styling on dashboard cards and media controls.

## v0.2.5 — Icon label fallback
**Confirmed** — Added glass label backgrounds for icon views without a usable native backdrop.

## v0.2.4 — App icon transitions
**Confirmed** — Fixed glass styling appearing late when scrolling between CarPlay app pages.

## v0.2.3 — Glass effects test
**Confirmed** — Added separate glass surface options and validated that the tweak changes WinPlay appearance.

## v0.2.2 — Native material experiments
**Experimental** — Tested overlay effects on existing CarPlay material views.

## v0.2.1 — Appearance and dock experiment
**Experimental** — Added initial automatic appearance handling and experimental dock styling.

## v0.2.0 — Initial RootHide preview
**Experimental** — Introduced an independent experimental CarPlay26 tweak and icon appearance preview.
