# Clicky identity

Both logos were generated with the built-in image generation tool. The amber, sculpted C borrows the stepped edges of a mechanical keycap. The menu bar version simplifies the same shape into a monochrome template that macOS tints for light and dark menu bars.

Final assets:

- App icon master: `../Clicky/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.
- Menu mark master: `ClickyMenuMark.png`.
- Menu bar exports: `../Clicky/Assets.xcassets/ClickyMark.imageset/`.

Run `bash Tools/export_icons.sh` from the project root to regenerate the smaller PNG sizes. These are shipping artwork assets, not build artifacts. The app icon has transparent outer margins; the menu bar mark uses only its alpha silhouette.

The prompts below omit the local output destination.

## App icon generation prompt

> Use case: logo-brand. Asset type: final macOS application icon for Clicky, a menu bar app that gives laptop keys real mechanical switch sounds. Design one polished, creative icon based on a capital letter C. The C is a bold sculptural continuous keycap-shaped ribbon, rounded squared outline with an open right side; stepped mechanical keycap edges subtly suggest depth. Its open terminals have two short offset rhythm notches suggesting a satisfying click, without any separate pictograms. Warm amber/copper C on a dark graphite softly rounded square keycap tile, matching the app's existing graphite (#1B1C20) and amber (#F2B880) interface. Refined tactile satin material, restrained highlights and shallow depth, front-facing near orthographic, elegant and extremely readable at small sizes. One centered icon fills about 85% of a square 1024x1024 canvas, with transparent outer margins and rounded macOS-style tile corners. Use actual alpha transparency outside the tile. No other letters, no wordmark, no caption, no watermark, no extra objects, no mockup.

## Menu bar generation prompt

Reference image: the approved app icon master above. Transparent background enabled for both generations.

> Use case: logo-brand. Asset type: final macOS menu bar template icon for Clicky. Input image is the approved Clicky app icon, a reference for identity. Create its matching small monochrome mark: retain the recognizable capital C with rounded square corners and the stepped/notched upper and lower open-right terminals. Simplify it into one perfectly flat solid BLACK silhouette on an actual transparent background, with clean smooth geometric edges. No tile, no rounded-square backdrop, no shadow, no gradients, no texture, no highlights, no perspective, no outline, no additional letters, no separate sound wave objects. A generous open right side and large clear inner negative space; make the letter's strokes bold and consistent so it reads at 18 pixels. Straight front-facing view. The C is centered in a square canvas and occupies 90 percent of width and height. The only visible pixels must belong to the black C.
