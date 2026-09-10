# Website

`index.html` is intentionally blank. Put images, videos, styles, and scripts in `assets/`. No framework, dependencies, or build step.

Live at [hinge.noveum.ai](https://hinge.noveum.ai/). The app download is [hinge.noveum.ai/download](https://hinge.noveum.ai/download).

## Deploy once, then just push

Import `Noveum/hinge` into Vercel, choose `web` as the root directory, and use `main` as the production branch. The included configuration selects a plain static site. Every subsequent push to `main` deploys automatically through Vercel's Git integration; branches get preview deployments.

For downloads from this private repository, add a server-only `GITHUB_TOKEN` environment variable in Vercel with read-only Contents access to `Noveum/hinge`. A future download button can link to `/download`. The endpoint redirects to the latest release's `Hinge.dmg` without exposing the token or sending the installer through a function response.

To preview only the HTML locally:

```sh
python3 -m http.server 8080 --directory web
```

Use Vercel's local development command when working on the download endpoint.
