# Hinge

A local macOS app that applies a soft perspective and progressive blur to your actual desktop as you close the lid. SwiftUI controls, ScreenCaptureKit capture, and Metal rendering.

## Run

Build the app using the instructions below, then open **build/Hinge.app**. Put your lid at a comfortable viewing angle and turn **On**. Allow Screen Recording if macOS asks, then quit and reopen Hinge if required.

The current angle becomes the open position each time you turn it on. Use **Set open position** after adjusting your normal viewing angle. Closing the settings window leaves Hinge in the menu bar. Turn it off or quit from there.

There is one effect and two controls. No demo playback, alternate styles, sound, or keyboard interception.

## Build

Clone this repository, open `Hinge.xcodeproj`, select **Hinge**, and run on **My Mac**. No package dependencies or developer account are required. Alternatively, from the repository directory:

```sh
make build
```

The command writes the app to `build/Hinge.app`. Requires an Apple silicon MacBook, macOS 14 or later, and Xcode for building. The build targets arm64. The undocumented hinge sensor is not available on every MacBook model.

## Version 0.4

- Smooths whole-degree lid readings into continuous movement with bounded prediction and a small noise band.
- Prevents small backward movements between repeated readings while the lid is closing or opening.
- Uses stronger smoothing for slow movement and responds faster to quick movement.
- Prepares the GPU blur pipeline and waits for the first captured frame before showing On.
- Keeps a transparent rendering surface ready at rest and blends into the effect during the first few degrees.

The animation uses the full-height treatment observed in the native reference video. The normal menu bar and Dock remain outside the effect. The sensor runs on a dedicated queue targeting 120 Hz, and the display drives rendering at up to 120 Hz.

Capture targets 60 fps at up to 2400 pixels wide. Animation can continue at the display refresh rate independently of captured frame arrival. Rendering pauses completely at the open position. The overlay is excluded from capture and passes input through to the desktop.

Frames stay in memory. No audio is captured, and no frames are saved or uploaded. Protected windows may appear black. The effect applies to the built-in display.

Swift and Metal compilation are checked locally. Deterministic replays cover whole-degree input at 30, 60, and 120 Hz, slow and fast movement, alternating adjacent readings while held, and reopening. These checks verify the estimator and rendering path, not physical end-to-end latency. Physical lid responsiveness and sleep/wake behavior still require a hardware trial. The native reference's private renderer is unavailable, so its exact coefficients cannot be verified. See `MOTION.md` for the reference analysis.
