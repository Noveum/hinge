# Website

A plain HTML landing page with system light and dark themes, a pausable illustrated preview, and a direct app download. Styles and scripts live in `assets/`. No framework or build step.

Live at [hinge.noveum.ai](https://hinge.noveum.ai/). The download button uses [hinge.noveum.ai/download](https://hinge.noveum.ai/download).

## Deploy

Vercel uses `web` as the root directory and `main` as the production branch. Push to `main` to deploy. Branches get preview deployments.

Downloads from the private repository need a server-only `GITHUB_TOKEN` environment variable in Vercel with read-only Contents access to `Noveum/hinge`. The endpoint redirects to the latest release's `Hinge.dmg` without exposing the token.

## Preview

```sh
python3 -m http.server 8080 --directory web
```

Use `vercel dev` from this folder to work on the download endpoint.

## Add the recording

The current laptop animation is an illustration, labeled on the page. When the final public demo is ready, add it to `assets/` and replace the illustrated preview with a video. Keep playback controls and a static poster for visitors who prefer reduced motion.
