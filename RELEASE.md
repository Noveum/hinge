# Shipping Hinge

Every push to `main` builds the app and saves `Hinge.dmg` and its SHA-256 checksum as the `Hinge-macOS` workflow artifact. There are no test jobs.

## Local installer

```sh
scripts/package.sh
```

The installer appears in `dist/Hinge.dmg`. Open it and drag Hinge into Applications. Allow Screen Recording when prompted, then reopen Hinge if needed.

Local builds use an installed Apple Development identity when available. The hosted build currently uses ad-hoc signing because no certificate secrets are configured. These are prototype builds, not notarized releases; macOS may require approving the app under Privacy & Security before first launch.

## Release publishing

Automatic GitHub release publishing is pending. The current publishing tool cannot upload an installer of this size. The build artifact is available to repository members from the Actions run in the meantime.

The website's `/download` endpoint is ready for a published release containing an asset named `Hinge.dmg`. Each future release must be published as the latest release so the URL always serves the current installer.

## Website

Import the repository into Vercel with `web` as its root directory and `main` as its production branch. No build or install command is needed. Once connected, Vercel deploys future pushes automatically.

The page is intentionally empty. Add the design and media to `web/index.html` and `web/assets/`. Connect a download link to `/download` when the first release is published. For this private repository, configure a server-only `GITHUB_TOKEN` in Vercel with read-only Contents access to `Noveum/hinge`.
