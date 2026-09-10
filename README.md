# Hinge

A local macOS app that applies a soft perspective and progressive blur to your actual desktop as you close the lid. SwiftUI controls, ScreenCaptureKit capture, and Metal rendering.

## Run

Build the app using the instructions below, then open **build/Hinge.app**. The default open angle is **100 degrees**. Turn **On** to use it, or put your lid at a comfortable viewing angle and select **Set open position** first. Allow Screen Recording if macOS asks, then quit and reopen Hinge if required.

Use **Set open position** after adjusting your normal viewing angle. Hinge remembers that calibration across launches and leaves it unchanged when you turn the effect on. Closing the settings window leaves Hinge in the menu bar. Turn it off or quit from there.

There is one effect and two controls. No demo playback, alternate styles, sound, or keyboard interception.

## Build

Clone this repository, open `Hinge.xcodeproj`, select **Hinge**, and run on **My Mac**. No package dependencies or developer account are required. Alternatively, from the repository directory:

```sh
make build
```

The command writes the app to `build/Hinge.app`. Requires an Apple silicon MacBook, macOS 14 or later, and Xcode for building. The build targets arm64. The undocumented hinge sensor is not available on every MacBook model.

## Version 0.5

- Starts at 100 degrees and saves your chosen open position.
- Receives sensor input notifications on a dedicated queue, with a low-frequency connection check if notifications stop.
- Schedules each draw with the display presentation clock.
- Smooths whole-degree lid readings into continuous movement with bounded prediction and a small noise band.
- Prevents small backward movements between repeated readings while the lid is closing or opening.
- Uses stronger smoothing for slow movement and responds faster to quick movement.
- Prepares the GPU blur pipeline and waits for the first captured frame before showing On.
- Keeps a transparent rendering surface ready at rest and blends into the effect during the first few degrees.

The animation uses the full-height treatment observed in the native reference video. The normal menu bar and Dock remain outside the effect. The sensor delivers input notifications on a dedicated queue. A display link targets a steady 60 Hz cadence and advances the motion estimate to the expected presentation time. This avoids drawable stalls seen when requesting 120 Hz on the current rendering path.

Capture targets 60 fps at up to 2400 pixels wide. Animation continues independently of captured frame arrival. Rendering pauses completely at the open position. The overlay is excluded from capture and passes input through to the desktop.

Frames stay in memory. No audio is captured, and no frames are saved or uploaded. Protected windows may appear black. The effect applies to the built-in display.

Swift and Metal compilation are checked locally. Deterministic replays cover regular and change-driven input, slow and fast movement, alternating adjacent readings while held, reopening, and a disconnected sensor. Local sensor notifications and the display-link rendering path were also checked. The six-second synthetic rendering run averaged 16.67 ms between frames, with a 16.79 ms 95th percentile and no GPU errors. These checks verify the estimator and rendering path, not physical end-to-end latency. Physical lid responsiveness and sleep/wake behavior still require a hardware trial. The native reference's private renderer is unavailable, so its exact coefficients cannot be verified. See `MOTION.md` for the reference analysis.
