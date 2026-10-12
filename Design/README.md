# Clicky identity

The current logos use a flat rounded C with soft capsule ends. The app icon places charcoal on muted apricot; the menu bar uses a monochrome alpha template that macOS tints for its current appearance. Both were generated with the built-in image generation tool.

Final assets:

- App icon master: `ClickyAppIcon.png`.
- System app icon: `../Clicky/Resources/Clicky.icns`.
- Header and application image: `../Clicky/Assets.xcassets/ClickyLogo.imageset/`.
- Menu mark master: `ClickyMenuMark.png`.
- Menu bar exports: `../Clicky/Assets.xcassets/ClickyMark.imageset/`.

Run `bash Tools/export_icons.sh` from the project root to regenerate the ICNS and smaller PNG sizes. The export removes its temporary iconset automatically. The header loads its dedicated image directly, and application startup sets the application image from the same asset.

The system app icon uses the standalone `Clicky.icns` resource named by `CFBundleIconFile`, without a catalog app-icon entry or `CFBundleIconName`. On the tested macOS installation, the catalog icon decoded correctly inside Clicky but Icon Services returned a placeholder to system callers such as Settings. Verification now compares the icon returned by `NSWorkspace` with the bundled ICNS. Temporary verification builds use a separate bundle identifier and unregister on cleanup so they do not replace the user's Clicky registration.

## App icon generation prompt

> Use case: logo-brand. Asset type: final macOS application icon for Clicky, a small neutral keyboard sound utility. Primary request: replace the former sculptural gaming-like C with a timeless flat TWO DIMENSIONAL logo. One simple capital C, charcoal (#26272C), made from a smooth rounded geometric open ring with uniform bold stroke and completely rounded capsule ends. Friendly and understated, broad audience, no angular cuts, no notches, no lightning shapes, no gaming details. Center the C on a solid muted warm apricot (#F2C69E) rounded square macOS tile. No gradients at all, no 3D, no bevel, no extrusion, no surface texture, no lighting, no shadows, no gloss, no highlights, no perspective. Crisp flat vector-style graphic. Large C centered with generous clear space, suitable at tiny sizes. The outer tile fills 86 percent of a square 1024x1024 canvas; actual alpha transparent outer margins. Only this icon, no words, no captions, no mockup, no watermark.

## Menu bar generation prompt

Reference image: the new app icon master above. Transparent background enabled for both generations.

> Use case: logo-brand. Asset type: macOS menu bar template icon. Reference image: the new approved flat Clicky logo. Create exactly its smooth simple capital C as one solid pure black silhouette on an actual transparent background. Remove the apricot tile entirely. The C must be a smooth rounded geometric open ring with uniform bold stroke and fully rounded capsule tips, front-facing and two dimensional. Friendly and neutral. No corners, no angular notches or cuts, no extra objects, no background, no gradients, no shadows, no highlights, no texture, no perspective, no 3D, no words. Make its outline crisp and clean; the only visible pixels belong to the black C. Center the glyph on a square canvas with just 8 percent transparent padding, readable at 18 pixels.
