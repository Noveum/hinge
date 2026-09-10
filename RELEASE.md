# Shipping Hinge

Every push to `main` builds the app, saves the `Hinge-macOS` workflow artifact, and publishes a GitHub release with `Hinge.dmg` and its SHA-256 checksum. The release waits for tracked-file policy, formatting, lint, link, and compilation checks. There are no test jobs.

## Local installer

```sh
scripts/package.sh
```

The installer appears in `dist/Hinge.dmg`. Open it and drag Hinge into Applications. Allow Screen Recording when prompted, then reopen Hinge if needed.

Local builds use an installed Apple Development identity when available. The hosted build currently uses ad-hoc signing because no certificate secrets are configured. These are prototype builds, not notarized releases; macOS may require approving the app under Privacy & Security before first launch.

## Release publishing

The workflow uploads the installer to a draft release before marking it published and latest. Each run gets a unique tag, so previous installers remain available. No additional publishing secrets are required.

The website's `/download` endpoint serves the current release's `Hinge.dmg`. It follows the latest release automatically, so publishing an app update does not require editing the site.

## Website

Import the repository into Vercel with `web` as its root directory and `main` as its production branch. No build or install command is needed. Once connected, Vercel deploys future pushes automatically.

The landing page lives in `web/index.html`, with styles and the original demo recording in `web/assets/`. Its download button uses `/download` to serve the latest release. For this private repository, configure a server-only `GITHUB_TOKEN` in Vercel with read-only Contents access to `Noveum/hinge`.

CI finishes by checking the deployed website assets, video seeking, and the public installer checksum against the new release. Deployment failures leave a failed workflow instead of a false success.
