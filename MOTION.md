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

The current comfortable open position is measured when enabling Hinge. An explicit calibration button handles later adjustments. The baseline does not move downward while the user holds the lid partly closed. It is retained across sleep and reinitialization of the capture stream.

Closure is mapped linearly from that baseline to eight degrees with a 0.75-degree deadband at rest. A single 12 ms exponential filter softens integer sensor steps. There is no spring, fixed playback timeline, or additional SwiftUI animation in the motion path.

The sensor targets 120 samples per second on a dedicated queue. MTKView schedules drawing at the display refresh rate, up to 120 Hz. Captured content arrives separately at up to 60 fps. Each newly captured frame generates cached GPU blur levels; lid movement only changes the final projection and blur blend. The renderer reuses the latest content and does not wait for a new capture frame to move.

The prior 85 ms filter alone took about 255 ms to approach 95 percent of a new target. A 12 ms filter takes about 36 ms. These figures describe the filter response, not measured physical end-to-end latency, which also includes the sensor, GPU, and display.

## Implementation reference

[LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) supplies the observed HID identifiers and feature-report layout. Hinge reads the little-endian angle through IOKit. Exact native Bendy shader parameters and sensor timing remain unavailable.
