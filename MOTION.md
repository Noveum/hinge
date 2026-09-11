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

Three cached Gaussian blur levels at nominal widths of 6, 16, and 36 pixels per 786-pixel reference width provide continuous progressive blur. Blur strength varies with closure and fades toward the lower tenth of the desktop. Subtle top-corner shading and side feathering complete the single effect. The side gaps are filled with the nearest desktop edge, stretched from a broad blur of the reduced frame, or with black, as chosen in Settings. The fill and the desktop are blurred as one surface: every blur level is computed from a composite that places the fill in a side margin around the reduced frame, so blurred content spreads across the fold's edge toward the top while the lower edge stays sharp. Each captured frame adds one scale and one copy into that composite. The blurred fill also runs a quarter-size broad blur and one stretch; the black fill clears the margin instead. On an M1 Max the blurred fill's chain measured about 0.2 ms per captured frame, up from 0.11 ms. An inverse projection in the fragment shader preserves the fold geometry while covering the full overlay.

The effect covers the built-in screen's usable desktop area, excluding the normal menu bar and Dock. A non-activating panel joins fullscreen Spaces without taking keyboard focus. Space changes refresh the capture area: fullscreen content uses the whole display, while the regular desktop keeps the menu bar and Dock stationary.

## Motion timing

The default open position is 100 degrees. The calibration button captures a comfortable viewing angle and saves it across launches. Enabling the effect does not overwrite the chosen position. The baseline stays fixed while the user holds the lid partly closed and is retained across sleep and capture reinitialization.

The input is a stream of integer-degree readings. A 0.6-degree noise band prevents alternating adjacent readings from constantly moving the target. Angular velocity is estimated with a 60 ms time constant. Prediction looks ahead by 35 ms and is limited to 0.75 degrees. Closure is mapped from the calibrated baseline toward eight degrees.

A critically damped second-order filter maintains continuous position and velocity. Its response increases from 30 to 55 radians per second as estimated motion speeds up. The output keeps its direction between readings until the sensor indicates a reversal. This avoids small backward corrections from decaying predictions. Long gaps between rendered frames reset the integration step, preventing an initial jump after resting.

There is no fixed playback timeline or additional SwiftUI animation in the motion path. The speed-dependent smoothing follows the general principle described by the [1 Euro filter authors](https://github.com/casiez/OneEuroFilter), using stronger smoothing at low speeds. The implementation uses a damped second-order response rather than that library's first-order filter.

The sensor reads feature reports on a dedicated queue at 120 Hz while the effect is enabled and 10 Hz while disabled. It does not wait for input notifications, which did not track physical movement reliably. Repeated readings still advance the estimator clock; consecutive failed reads clear the effect instead of leaving an old position on screen. A view-owned display link schedules drawing at a steady 60 Hz, passing the expected presentation timestamp to the motion estimator. MTKView remains in explicit-draw mode so only that display link controls cadence. Captured content arrives separately at up to 60 fps. The selected draw cadence avoids repeated drawable stalls observed when requesting 120 Hz. A synthetic run measured 16.67 ms average frame spacing and 16.79 ms at the 95th percentile, with a first motion draw taking 1.10 ms on the CPU. These are local rendering measurements, not sensor-to-display latency. Each newly captured frame generates cached GPU blur levels; lid movement only changes the final projection and blur blend. The renderer reuses the latest content and does not wait for a new capture frame to move.

The previous 12 ms first-order filter followed individual degree changes too closely. High rendering frame rates did not eliminate the visible stair-step input. The current motion filter smooths position and velocity together and suppresses quantization jitter. A synthetic replay checks slow and fast closure at 30, 60, and 120 input samples per second, held adjacent-degree noise, and reopening.

Before On appears, an offscreen GPU pass initializes the blur textures, Gaussian kernels, and fold pipeline, and capture supplies its first frame. A transparent window stays ordered at rest with drawing paused, so closing does not need to allocate a new window surface. The first 2.5 percent of closure smoothly blends the captured image into the live desktop. That blend is derived from progress alone, so it cannot cover a session that starts with the fold already underway: progress is past the threshold on the first drawn frame and the overlay would appear opaque and folded over a desktop that was flat one frame earlier. Those sessions also fade in over 160 ms of wall clock. The shader takes the lower of the two values, so the entry fade never shows more than the progress blend would allow, and a normal close from rest is unaffected because no entry fade is started for it. At full reopening, a transparent frame is presented before drawing pauses.

These checks do not measure physical end-to-end latency, which also depends on the sensor, capture, GPU, and display.

## Capture at rest

macOS shows its screen recording indicator for as long as a capture stream runs, and an app cannot suppress it. Pausing capture at rest is optional and on by default. The stream stops three seconds after the fold returns to rest and a new one is built when the next fold begins, so the indicator tracks lid movement instead of staying lit for the whole session.

The renderer keeps its last frame across a pause, so a fold starts on retained content while the new stream spins up rather than waiting on capture. The content filter and stream configuration are cached, which lets a resume skip shareable content enumeration and the blur warm up. Building the stream is deliberately kept off the main actor: the display link that drives drawing is scheduled on the main run loop, so constructing the stream and attaching its output there stole frames from the first moments of a fold, which is exactly when a resume happens. Included windows are refreshed just before a suspend rather than after a resume, for the same reason. Enumerating shareable content is expensive and updating the content filter disturbs capture, and at rest there is time to spare. Turning the option off keeps a single stream running for the whole session, which is the earlier behavior.

## Implementation reference

[LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) supplies the observed HID identifiers and feature-report layout. Hinge reads the little-endian angle through IOKit. Exact native Bendy shader parameters and sensor timing remain unavailable.

## Recovery

Sensor loss cancels both startup and active capture. Switching Spaces uses the full display frame directly, without enumerating shareable content. Capture restarts only when the display area changes. Wake recovery waits up to five seconds for the sensor, and duplicate wake notifications do not interrupt an active session. Turning Hinge off cancels pending recovery.
