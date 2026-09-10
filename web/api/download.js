module.exports = async function handler(request, response) {
  response.setHeader("Cache-Control", "no-store");
  if (request.method !== "GET" && request.method !== "HEAD") {
    response.setHeader("Allow", "GET, HEAD");
    return response.status(405).end();
  }
  const headers = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
  };
  if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  try {
    const release = await fetch("https://api.github.com/repos/Noveum/hinge/releases/latest", {
      headers,
      signal: AbortSignal.timeout(10000),
    });
    if (!release.ok) throw new Error("Release unavailable");
    const data = await release.json();
    const asset = data.assets?.find(item => item.name === "Hinge.dmg");
    if (!asset || !Number.isSafeInteger(asset.id)) throw new Error("Installer unavailable");
    const download = await fetch(`https://api.github.com/repos/Noveum/hinge/releases/assets/${asset.id}`, {
      headers: { ...headers, Accept: "application/octet-stream" },
      redirect: "manual",
      signal: AbortSignal.timeout(10000),
    });
    const location = download.headers.get("location");
    if (!location || ![301, 302, 303, 307, 308].includes(download.status)) throw new Error("Download unavailable");
    const destination = new URL(location);
    if (destination.protocol !== "https:" || destination.hostname !== "release-assets.githubusercontent.com") throw new Error("Unexpected destination");
    response.setHeader("Location", destination.href);
    return response.status(302).end();
  } catch {
    response.setHeader("Retry-After", "60");
    return response.status(503).send("The download is not ready yet. Please try again shortly.");
  }
};
