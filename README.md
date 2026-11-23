# CarPlay26 v0.2.47 — Optimised native wallpapers

## v0.2.47 — Smaller package, same wallpapers

- Six patterned wallpaper choices in light and dark: high-quality JPEG, full 2048×2048, thumbnail 512×512
- Three solid wallpaper choices in light and dark: unchanged PNG, full 2048×2048, thumbnail 512×512
- Wallpaper picker selection, native identifier mappings, vehicle light/dark switching and the actual Home wallpaper renderer use the same existing hooks and image dimensions
- `tools/prepare-wallpapers.py` still downloads and validates the original high-resolution PNGs at build time, then emits 24 JPEGs + 12 PNGs in `layout/usr/lib/TweakInject/CarPlay26Wallpapers`
- No files from the earlier wallpaper optimisation *preview* ZIP need to be copied into the source repository; the GitHub build generates all the resources automatically
- `WallpaperAssets.m` reads the two types and can fall back to legacy PNG for patterned wallpaper when available
- All other working features are left untouched, including the v0.2.46 launcher icon
- Compilation and live WinPlay light/dark wallpaper testing required before considering this change verified

# CarPlay26 v0.2.46 — launcher inside applications

## v0.2.46 — Native application-aware launcher

- **iOS 26 App Launcher Icon**: outlined square on Home, nine-square grid on Dashboard and inside an active CarPlay application
- Observes the existing iOS 16 dock controller's `activeBundleIdentifier` and follows the native Dashboard-page fraction, without altering app launch, native Home actions, dock layout, wallpaper, labels, widgets or Airaw settings
- The app state hook is enabled only if the native getter and setter exist, and only while the launcher preference is enabled
- There is no continuous new polling; app changes trigger a lightweight refresh, and existing scroll events still follow page swipes
- **Important:** This update needs on-device validation across returning to Home and switching directly between apps; the source ZIP is not a compiled tweak

## v0.2.45 — Visible dashboard glass and diagnostic report repair

- Restores a translucent three-stop tint on the **actual MTMaterialView** in the Home and Now Playing lower dashboard widgets; the v0.2.44 outer-layer tint was hidden under native card material
- Uses **no separate border or inset** and adopts native material clipping, retaining native widgets, media controls, touch regions and the map
- Main `CarPlay26-diagnostics.txt` now falls back to writable per-process cache/temporary directories rather than silently failing at `/var/mobile/Documents`
- The successful diagnostic path is logged once in CarPlay's process log; inspect or locate it with `find` on the iPhone after reconnecting
- Notification badge rim masking, app labels, launcher transition, dock and wallpapers are unchanged; test on WinPlay before declaring it complete

## v0.2.44 — Dashboard edges and notification badges

- Removes the extra inset panel from **Glass Dashboard Cards** and styles only the outer native lower widget container (single card outline, existing map and controls unchanged)
- Uses a faint three-stop glass tint below the existing native dashboard content; no second decorative border is drawn
- **Glass App Icon Rims** no longer vanishes in full when Messages receives a badge; the rim remains except for a short masked section behind the visible notification badge
- Keeps the native notification badge, app icon, icon text, dynamic label width, Home/Dashboard launcher transition, Airaw layout, dock, pinned shortcuts and wallpapers unchanged
- Source-only update; build and parked WinPlay testing are required to confirm visuals and toggling badges

## v0.2.43 — Appearance corrections (revised source ZIP)

- App-grid icon rims render beneath the system's notification-badge accessory layers; if an icon cell has a visible native badge view, the optional rim is hidden while the badge is present so it never crosses notification text
- The lower Dashboard Home and Now Playing cards in light appearance use a slightly deeper, less white-blue glass gradient and quieter decorative borders; native card content, music controls, layout and map stay untouched
- The existing v0.2.42 dynamic light/dark label backgrounds remain byte-for-byte unchanged in the relevant label branches
- Includes the previously prepared 0.2.43 launcher animation; **use this revised ZIP instead of the earlier 0.2.43 ZIP**, and test it before relying on it while driving

## v0.2.43 — Native page-aware launcher

- With **iOS 26 App Launcher Icon** on, the native status-bar Home button draws an outlined square over the app grid and a nine-square glyph on the Dashboard
- Tracks native dashboard-page visibility within DBIconScrollView; the two glyphs crossfade on a transition without changing the native button or app-grid position
- Supports both CarPlay dark and light appearance, with no additional preference switches or diagnostics
- No changes to wallpaper selection, Airaw grid, dock capsule or pinned app shortcuts, map content, widget geometry, media controls or input handling
- v0.2.43 had no app-hosted state handling; v0.2.46 adds the native dock active-application signal
- Build and test in WinPlay while parked; a successful compilation alone cannot verify the transition

## v0.2.42 — Balanced labels and dashboard glass

- Intermediate smoky-grey background tint only for light-mode labels, between the v0.2.40 and v0.2.41 finishes; leaves dark-mode icon labels unchanged
- Retains the adaptive title-measured label widths, native text and Airaw's app grid
- Refines the two lower dashboard widget material overlays with more rounded decorative corners, restrained three-stop cool glass gradient, and a faint blue-grey rim
- Softens decorative borders on the native Now Playing controls without moving or changing their actions
- Leaves dashboard Map view, tile arrangement, wallpaper assets, dock, launcher, shortcuts, and stored preferences untouched
- Build and on-device WinPlay verification required

## v0.2.41 — Light-mode contrast

- Dark mode is unchanged from v0.2.40
- In light CarPlay appearance, Glass Icon Labels draws a darker smoky-grey backing behind the unchanged white app titles, in both native-material and fallback-label paths
- Dynamic title-measured capsule widths remain unchanged, including compatibility with Airaw's grid placement
- No changes to the dashboard, dock, launcher, wallpaper, app behavior or stored preferences
- Build/visual test required on-device before claiming the appearance is confirmed

## v0.2.40 — Adaptive glass labels

- When **Glass Icon Labels** is enabled, the dark background width now follows the measured visible app title plus balanced side padding, capped at the native material slot
- No changes to title text or font, Airaw layout or icon positions, dashboard, dock or wallpaper
- Title measurement is conservative: if the title is unavailable, or a native mask belongs to UIKit or another tweak, preserve the original behavior rather than risk clipped UI
- This requires an on-device WinPlay check to confirm the native label's accessible title is exposed and verify the geometry

## v0.2.39 — Appearance refinement
- Uses the existing **Glass Icon Labels** and **Glass Dashboard Cards** switches — both already enabled in the user's screenshot; no preference reset or new switch
- Softer icon labels: dark translucent backing, less prominent bright outline
- Dashboard panels: muted glass tint, restrained borders, smoother fallback corner radius, native window layout untouched
- No changes to the wallpaper pack, Airaw icon grid, launcher button, dock, pinned apps, Maps, playback controls, or diagnostics
- Requires real-device screenshots for confirmation; a successful build cannot validate visual fidelity

## v0.2.38 — Other Functions experiments (previous version)
- **Other Functions — Experimental** adds independent, opt-in options to hide the startup splash artwork, attempt dark appearance in Apple Maps CarPlay windows, and hide a known native corner-radius overlay
- All three options default off; they require iOS 16.4.1 device tests; startup splash and map rendering may be controlled by other processes and the receiver may still paint black corners
- Does not duplicate Airaw's Phone keypad lockout bypass, which removes an in-car driving safety restriction
- While testing, disable the corresponding Airaw setting to avoid competing hooks
- A successful GitHub build is not proof of device behavior; test each item carefully before relying on it

## v0.2.37 addition

- Optional **iOS 26 App Launcher Icon** switch in Settings > CarPlay26 > Dock (off by default)
- Replaces only the visible glyph of native `DBStatusBarHomeButton` with a small rounded-square outline, retaining the button and all interactions
- Does not alter the glass dock background, position of the home button, three app shortcuts, clock, status indicators, carLy or wallpapers
- Restart CarPlay Services after enabling; **not yet device-tested**

## v0.2.36 wallpaper and Settings changes

## What changed

- Six patterned iOS 26 CarPlay stock colourways (Red, Blue, Gray, Purple, Green, Brown) with separate original archived light/dark images
- Three additional solid-colour choices (White, Light Blue, Beige), each with a dark variant
- Nine native image wallpaper slots replaced in place; two original solid wallpaper identifiers remain untouched
- Native picker 512x512, full preview 2048x2048, and actual CarPlayWallpaper home renderer 2048x2048
- No test banner, no cache overwrite, no network access on the device
- Diagnostics and Changelog as separate Settings subpages, preserving existing defaults keys
- Fixed version text in Settings, and maintained CHANGELOG.md

## Wallpaper source provenance

The six iOS 26 CarPlay colourways come from archived high-resolution stock
wallpapers published by Beta Profiles (https://betaprofiles.com/wallpaper/ios-26-carplay-wallpapers/)
All six colours are corroborated by contemporaneous 9to5Mac / MacRumors coverage
The archive describes 4000x2182 PNG files as original iOS 26 CarPlay artwork
**No firmware-level cryptographic match has been established** — do not label the
source as independently Apple-verified. No AI-generated or hand-drawn imitations are used for the six
patterned designs. Three solid colours are simple locally generated uniform fills,
with approximate Apple stock palettes, not extracted Apple texture files.

The build downloads those source files inside GitHub Actions, validates that
all 12 files are 4000x2182 PNGs and center-crops without distortion to
2048x2048 and 512x512 native images. The build **fails** if any download is
missing or invalid, rather than substituting fake artwork.

Apple owns the underlying wallpaper designs; review redistribution permissions
before distributing the resulting DEB publicly

## Build

Extract into the existing CarPlay26 project, including .github/workflows/build.yml
Commit and push to the source repository. The normal action builds and publishes
via the existing automatic Sileo repo pipeline, provided all remote downloads work

## Test

1. Install 0.2.36, respring, connect WinPlay while parked
2. Open Settings > Wallpaper and inspect all nine slots (6 patterns + 3 solids)
3. Open each preview, set a wallpaper, verify the real home screen updates
4. Check light and dark modes for each chosen patterned wallpaper
5. Verify Settings > CarPlay26 > Diagnostics and Changelog open properly

Expected logs in CarPlayWallpaper's sandbox Documents:
`CarPlay26-background-CarPlayWallpaper.txt`: `HOME WALLPAPER REPLACED`

No device build or screenshots have been validated as of package generation
