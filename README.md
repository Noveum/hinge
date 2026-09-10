# Bendy Prototype

A local macOS app that bends your actual desktop as you close your MacBook lid. SwiftUI provides the controls and preview. ScreenCaptureKit streams the built-in display into a Metal overlay, driven by the lid's HID sensor.

## Run

Open the supplied **Bendy Prototype.app**. Select **Enable on my Mac**, allow Screen Recording when macOS asks, then reopen the app if requested. Enable it again and move the lid.

**Try on desktop** plays a complete close-and-open animation on your real desktop without moving the lid. It also works when the lid sensor is unavailable.

Press **Escape** to immediately stop the desktop effect. The menu bar icon also provides a Stop command. Closing the settings window leaves the app in the menu bar; Quit stops capture and removes the overlay.

## Controls

- **Silk, Shade, Frost:** three finishes for the fold.
- **Perspective, Variable blur, Shadow:** adjust the live effect and preview.
- **Follow lid:** use the physical lid angle. Switch it off to scrub the effect manually with the angle slider.
- **Clear at:** the angle above which the overlay disappears. Default: 110 degrees.
- **Opening sound:** plays a click when the desktop clears.
- **Preview play button or Space:** plays the miniature animation.

Appearance preferences persist between launches. Live capture starts only when explicitly enabled. It is intended to resume after sleep if it was active beforehand.

## Build

Open `BendyPrototype.xcodeproj`, select **BendyPrototype**, and run on **My Mac**. No package dependencies or developer account are required.

Alternatively, from this directory:

```sh
make build
```

The application is written to `build/Bendy Prototype.app`.

Requirements: Apple silicon MacBook, macOS 14 or later, and Xcode for building. The supplied binary is arm64. Sensor availability varies by model because the hinge report is not a documented Apple API.

## Behavior and limits

The live effect uses a bottom-anchored perspective projection, progressive blur, top-corner shadows, and a feathered top edge. Capture runs at up to 60 frames per second and 2400 pixels wide. The effect applies to the built-in display; external displays remain unchanged.

The app excludes its own windows from capture to avoid feedback. While the overlay is visible, the settings window is therefore absent from the captured desktop. Input passes through the overlay. Protected content may be black in captured frames.

No audio is captured. Desktop frames are held in memory and are never written to disk or uploaded. No account, license server, analytics, or network requests are part of the desktop effect.

Swift and Metal compilation completed. Physical lid movement, Screen Recording authorization, and sleep/wake behavior are left for the user's test.

The adjacent `References` folder contains the downloaded reference videos, a recording of the website scroll interaction, and the original settings screenshot. See `MOTION.md` for the animation breakdown.
