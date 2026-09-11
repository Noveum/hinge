# Hinge

Give your MacBook desktop a little bend. Close the lid and watch your screen softly fold and blur. Open it and everything comes back.

## For the nerds

Hinge reads the lid angle 120 times a second and turns it into a continuous animation. Slow tilt, slow bend. Quick tilt, quick bend. A little smoothing takes the steps out of whole-degree sensor readings.

ScreenCaptureKit supplies your live desktop, and Metal adds perspective and progressive blur at 60 fps. Everything stays in memory on your Mac. No recordings, no uploads.

## Install

Requires an Apple silicon MacBook with a supported lid sensor and macOS 14 or later. Not every MacBook has one; Hinge tells you if yours doesn't.

[Download Hinge](https://hinge.noveum.ai/download), open the DMG, and drag Hinge into Applications. This prototype is not notarized; macOS may ask you to approve it under Privacy & Security.

Prefer building it yourself? Grab Xcode, then:

```sh
git clone https://github.com/Noveum/hinge.git
cd hinge
make build
open build/Hinge.app
```

Allow Screen Recording, reopen Hinge if prompted, and turn it on. It turns itself back on the next time you open it. The starting angle is 100°. Prefer something else? Get comfy and click **Set open position**. Hinge remembers.

Hinge speaks your Mac's language: English, Simplified and Traditional Chinese, Japanese, Korean, German, French, Spanish, Italian, Brazilian Portuguese, Russian, Dutch, Turkish, Polish, Arabic and Vietnamese. To use a different one, pick it under **Settings > Controls > Language**.

## Got an idea?

Feature requests are welcome. [Open an issue](https://github.com/Noveum/hinge/issues) or just shoot a PR. Small fixes, smoother motion, fun ideas: come play.

[Development checks and setup](CHECKS.md).
