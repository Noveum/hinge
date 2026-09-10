# Motion reference

Studied on September 10, 2026. The implementation targets the real macOS desktop effect, with a matching miniature preview.

## Reference files

| Reference | Local file in the adjacent References folder | Duration |
| --- | --- | --- |
| [Bendy website](https://trybendy.app/) | website-demo.mp4 | 19.17 seconds, 1080 × 1920, 30 fps |
| [Bendy launch post](https://x.com/adrianabelarde_/status/2097998552517759106) | launch-demo.mp4 | 33.02 seconds, 1920 × 1080, 30 fps |
| Captured website scroll interaction | website-scroll.mp4 | About 8.12 seconds, 1280 × 720 |
| [Expo Duo context](https://x.com/nater02/status/2097776349217771912) | expo-duo-demo.mp4 | About 10 seconds, 864 × 720 |
| Bendy settings | settings.png | 1286 × 1126 |

The website scroll recording is assembled from 100 browser captures at an average of about 12.3 captures per second. The original embedded videos preserve their source frame rate.

## Complete sequence review

The portrait website video begins partly closed. At roughly 0 to 3 seconds the lid opens and the desktop sharpens. At 4 to 7 seconds it closes almost completely. From 8 to 11 seconds it reopens. A second close happens around 12 to 15 seconds, followed by an open and clear around 16 to 19 seconds. The bottom edge remains readable much longer than the top.

The landscape launch video shows three physical close/open cycles over approximately 0 to 23 seconds. A closer review at quarter-second intervals around 9 to 12 seconds shows that the desktop narrows progressively at the top while the base and Dock stay anchored. Blur increases before the lid approaches fully closed. The last roughly 24 to 33 seconds demonstrate the website's scroll-controlled miniature fold and its return.

The Expo clip shows the folding device and layout transitions. The published `expo-duo` 0.0.0 archive contains only `package.json`; it has no source, entry-point implementation, or native module to port. It serves as visual context rather than a code dependency.

## Measured website behavior

These values are observable in the public website's animation code:

| Component | Website behavior | Native implementation |
| --- | --- | --- |
| Fold drive | Scroll travel of 900 pixels, normalized and smoothstepped | Physical lid angle normalized below the clear threshold |
| Projection | Perspective 1400 pixels, maximum X rotation 72 degrees | Bottom-anchored homogeneous projection with the same aspect-scaled perspective and maximum angle |
| Anchor | Horizontal center, bottom edge | Both bottom corners remain fixed |
| Easing | Progress interpolation by 0.08 each browser frame | Time-based smoothing on the live render loop |
| Blur | Three layers at 6, 16, and 36 pixels | Three masked blur bands in SwiftUI; weighted GPU sampling in Metal |
| Blur falloff | Bands fade by 75%, 52%, and 34% of image height | Matching band boundaries |
| Feathering | Top edge expands to 22% of image height | Progressive top mask plus a small edge falloff |
| Shadows | Two dark top corners and a top-to-bottom shade | Matching directional shading, adjustable strength |
| Clear state | Zero fold, zero progressive blur and shadow | Overlay removed so the actual desktop is visible |

## Native motion and controls

The physical hinge is read at 30 Hz with an IOKit HID feature report. Live desktop capture and rendering target 60 Hz. Smoothing is based on elapsed time, so its feel is not tied to a particular refresh rate.

The clear threshold defaults to 110 degrees and is adjustable from 70 to 135 degrees. Full folding approaches 8 degrees. A smoothstep curve normalizes the interval. These thresholds are prototype tuning choices; the reference does not expose its complete native mapping.

The desktop demo has a one-second open hold, a 2.4-second close to 12 degrees, a 0.6-second closed hold, a 1.8-second open, and a final one-second settle. Manual control interrupts the miniature preview. The lid-driven effect follows the physical movement rather than playing a fixed timeline.

Silk uses the baseline blur and shade. Shade increases corner shading and reduces blur. Frost increases blur and adds a slight pale tint at the top. The exact native preset coefficients are not public, so these are visual approximations guided by the settings screenshot and videos.

The source website clicks at a closing threshold. Its product description says the macOS app clicks when opening clears the desktop. This prototype follows the macOS description and reuses the site's downloaded click sound for local comparison.

## Implementation references

- [Bendy](https://trybendy.app/): public demo, settings reference, and web projection behavior.
- [LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor): HID sensor identifiers and feature-report layout. The prototype reads the little-endian angle directly through IOKit.
- [expo-duo package metadata](https://registry.npmjs.org/expo-duo): inspected 0.0.0 package contents.

No claim of exact native shader equivalence is made. The original application's private renderer was not available. The prototype independently recreates the observable motion with adjustable parameters.
