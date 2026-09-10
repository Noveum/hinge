# Motion reference

Reviewed on September 10, 2026 using the original downloaded videos and local prototype recordings. Recordings are not included in this repository.

## Sources

| Reference | Reviewed media | Duration |
| --- | --- | --- |
| [Bendy website](https://trybendy.app/) | website-demo.mp4 | 19.17 seconds, 1080 x 1920, 30 fps |
| [Bendy launch post](https://x.com/adrianabelarde_/status/2097998552517759106) | launch-demo.mp4 | 33.02 seconds, 1920 x 1080, 30 fps |
| Website scroll recording | website-scroll.mp4 | About 8.12 seconds, 1280 x 720 |
| [Expo Duo context](https://x.com/nater02/status/2097776349217771912) | expo-duo-demo.mp4 | About 10 seconds, 864 x 720 |

The website scroll recording comprises 100 browser captures. The embedded videos preserve their original frame rates. The published expo-duo 0.0.0 archive contains only package metadata, with no implementation to port.

## Native video

The portrait video opens around 0 to 3 seconds, closes around 4 to 7, reopens around 8 to 11, closes again around 12 to 15, and reopens around 16 to 19. Blur builds toward the top while the bottom remains readable longer.

The landscape launch video contains three physical close/open cycles through approximately 23 seconds. Frames at 10.5 and 11.25 seconds show the key distinction: content still fills nearly the entire physical screen height. The top narrows mildly, the upper content blurs progressively, and dark corners deepen. The menu bar and Dock stay sharp and anchored. Some apparent perspective comes from the camera viewing the physical lid, so it must not be duplicated as software rotation.

The final portion of that video shows a separate website miniature. Its 72-degree rotation, 1400-pixel perspective, and large top-edge fade create an intentionally collapsing card. Earlier prototype versions incorrectly transferred that geometry to the real desktop. Local prototype recordings showed the resulting mismatch: a large black area opened above a heavily compressed desktop.

## Current reconstruction

The new projection keeps the top and bottom edges at their original height. Its homogeneous horizontal taper grows from zero to a maximum top-edge inset of approximately 11.5 percent on each side. This is a visual approximation of the native footage, not a recovered native coefficient.

Three cached Gaussian blur levels at nominal widths of 6, 16, and 36 pixels per 786-pixel reference width provide continuous progressive blur. Blur strength varies with closure and fades toward the lower tenth of the desktop. Subtle top-corner shading and side feathering complete the single effect.

The effect covers the built-in screen's usable desktop area, excluding the normal menu bar and Dock. The native video supports keeping these elements stationary. Auto-hidden system UI and fullscreen layouts may change the available area.

## Motion timing

The default open position is 100 degrees. The calibration button captures a comfortable viewing angle and saves it across launches. Enabling the effect does not overwrite the chosen position. The baseline stays fixed while the user holds the lid partly closed and is retained across sleep and capture reinitialization.

The input is a stream of integer-degree readings. A 0.6-degree noise band prevents alternating adjacent readings from constantly moving the target. Angular velocity is estimated with a 60 ms time constant. Prediction looks ahead by 35 ms and is limited to 0.75 degrees. Closure is mapped from the calibrated baseline toward eight degrees.

A critically damped second-order filter maintains continuous position and velocity. Its response increases from 30 to 55 radians per second as estimated motion speeds up. The output keeps its direction between readings until the sensor indicates a reversal. This avoids small backward corrections from decaying predictions. Long gaps between rendered frames reset the integration step, preventing an initial jump after resting.

There is no fixed playback timeline or additional SwiftUI animation in the motion path. The speed-dependent smoothing follows the general principle described by the [1 Euro filter authors](https://github.com/casiez/OneEuroFilter), using stronger smoothing at low speeds. The implementation uses a damped second-order response rather than that library's first-order filter.

The sensor delivers input reports on a dedicated dispatch queue. At rest, this Mac delivered a heartbeat about once per second. A low-frequency watchdog verifies the connection if those reports stop. Sparse reports do not clear a healthy held position. A view-owned display link schedules drawing at a steady 60 Hz, passing the expected presentation timestamp to the motion estimator. MTKView remains in explicit-draw mode so only that display link controls cadence. Captured content arrives separately at up to 60 fps. The selected draw cadence avoids repeated drawable stalls observed when requesting 120 Hz. A synthetic run measured 16.67 ms average frame spacing and 16.79 ms at the 95th percentile, with a first motion draw taking 1.10 ms on the CPU. These are local rendering measurements, not sensor-to-display latency. Each newly captured frame generates cached GPU blur levels; lid movement only changes the final projection and blur blend. The renderer reuses the latest content and does not wait for a new capture frame to move.

The previous 12 ms first-order filter followed individual degree changes too closely. High rendering frame rates did not eliminate the visible stair-step input. The current motion filter smooths position and velocity together and suppresses quantization jitter. A synthetic replay checks slow and fast closure at 30, 60, and 120 input samples per second, held adjacent-degree noise, and reopening.

Before On appears, an offscreen GPU pass initializes the blur textures, Gaussian kernels, and fold pipeline, and capture supplies its first frame. A transparent window stays ordered at rest with drawing paused, so closing does not need to allocate a new window surface. The first 2.5 percent of closure smoothly blends the captured image into the live desktop. At full reopening, a transparent frame is presented before drawing pauses.

These checks do not measure physical end-to-end latency, which also depends on the sensor, capture, GPU, and display.

## Implementation reference

[LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) supplies the observed HID identifiers and feature-report layout. Hinge reads the little-endian angle through IOKit. Exact native Bendy shader parameters and sensor timing remain unavailable.
