# Website

A plain HTML landing page with system light and dark themes, the original 19-second demo recording, and a direct app download. Styles and scripts live in `assets/`. No framework or build step.

Live at [hinge.noveum.ai](https://hinge.noveum.ai/). The download button uses [hinge.noveum.ai/download](https://hinge.noveum.ai/download).

## Deploy

Vercel uses `web` as the root directory and `main` as the production branch. Push to `main` to deploy. Branches get preview deployments.

The repository is public, so downloads work without credentials. An optional server-only `GITHUB_TOKEN` environment variable in Vercel, with read-only Contents access to `Noveum/hinge`, raises the GitHub API limit from 60 to 5,000 requests per hour. The endpoint redirects to the latest release's `Hinge.dmg` without exposing the token.

## Preview

```sh
python3 -m http.server 8080 --directory web
```

Use `vercel dev` from this folder to work on the download endpoint.

## Recording

`assets/demo.mp4` is the original recording converted to a silent, browser-compatible H.264 MP4 with fast start and personal metadata removed. Playback controls remain available. Reduced-motion visitors see the poster until they press play.
