# Hinge

A local macOS app that applies a soft perspective and progressive blur to your actual desktop as you close the lid. SwiftUI controls, ScreenCaptureKit capture, and Metal rendering.

## Run

Open the adjacent **Hinge.app**. Put your lid at a comfortable viewing angle and turn **On**. Allow Screen Recording if macOS asks, then quit and reopen Hinge if required.

The current angle becomes the open position each time you turn it on. Use **Set open position** after adjusting your normal viewing angle. Closing the settings window leaves Hinge in the menu bar. Turn it off or quit from there.

There is one effect and two controls. No demo playback, alternate styles, sound, or keyboard interception.

## Build

Open `Hinge.xcodeproj`, select **Hinge**, and run on **My Mac**. No package dependencies or developer account are required. Alternatively:

```sh
make build
```

The app is written to `build/Hinge.app`. Requires an Apple silicon MacBook, macOS 14 or later, and Xcode for building. The supplied binary is arm64. The undocumented hinge sensor is not available on every MacBook model.

## Version 0.3

- Replaces the collapsing website miniature projection with the full-height treatment observed in the native reference video.
- Reads the sensor on a dedicated queue targeting 120 Hz. The display drives rendering, up to 120 Hz on supported displays.
- Reduces motion smoothing from 85 ms to 12 ms, enough to soften integer-degree sensor steps without a long trailing animation.
- Precomputes three Gaussian blur levels on the GPU when a new desktop frame arrives. Each output pixel blends two samples instead of repeatedly sampling dozens of blur offsets.
- Keeps the menu bar and Dock outside the effect in the normal desktop layout.
- Removes the settings preview, custom styles, sound, manual angle sliders, and Escape shortcut.

Capture targets 60 fps at up to 2400 pixels wide. Animation can continue at the display refresh rate independently of captured frame arrival. Rendering pauses completely at the open position. The overlay is excluded from capture and passes input through to the desktop.

Frames stay in memory. No audio is captured, and no frames are saved or uploaded. Protected windows may appear black. The effect applies to the built-in display.

Swift and Metal compilation are checked locally. A six-second synthetic rendering check produced 699 frames at a 3024 x 1800 drawable size without GPU errors. After startup, mean frame spacing was 8.33 ms and the 95th percentile was 9.10 ms. These measurements cover rendering, not physical sensor latency. Physical lid responsiveness and sleep/wake behavior require a hardware trial. The native reference's private renderer is unavailable, so its exact coefficients cannot be verified. See `MOTION.md` for the reference analysis.
