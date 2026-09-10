# Hinge website

```sh
npm install
npm run dev
```

For Vercel, choose `web` as the root directory. The page follows the system theme automatically.

Set `GITHUB_TOKEN` to a fine-grained token with read-only Contents access to `Noveum/hinge`. The download route serves the latest release's `Hinge.dmg`, keeping the token on the server. Until that release exists, downloads return a short unavailable message.

Set `DEMO_VIDEO_URL` to the URL of the final recording, or add the recording to `public/demo.mp4` and use `/demo.mp4`. Until then, the page shows an illustrated animation.
