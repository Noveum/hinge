export const dynamic = "force-dynamic";

export async function GET() {
  const token = process.env.GITHUB_TOKEN;
  const headers: Record<string, string> = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  try {
    const release = await fetch("https://api.github.com/repos/Noveum/hinge/releases/latest", {
      headers,
      cache: "no-store",
      signal: AbortSignal.timeout(10000),
    });
    if (!release.ok) throw new Error("Release unavailable");
    const data = await release.json();
    const asset = data.assets?.find((item: { name: string; id: number }) => item.name === "Hinge.dmg");
    if (!asset || !Number.isSafeInteger(asset.id)) throw new Error("Installer unavailable");
    const download = await fetch(`https://api.github.com/repos/Noveum/hinge/releases/assets/${asset.id}`, {
      headers: { ...headers, Accept: "application/octet-stream" },
      redirect: "manual",
      cache: "no-store",
      signal: AbortSignal.timeout(10000),
    });
    const location = download.headers.get("location");
    if (location && [301, 302, 303, 307, 308].includes(download.status)) {
      const destination = new URL(location);
      if (destination.protocol !== "https:" || destination.hostname !== "release-assets.githubusercontent.com") throw new Error("Unexpected download destination");
      return new Response(null, { status: 302, headers: { Location: destination.href, "Cache-Control": "no-store" } });
    }
    if (!download.ok || !download.body) throw new Error("Download unavailable");
    return new Response(download.body, {
      headers: {
        "Content-Type": "application/x-apple-diskimage",
        "Content-Disposition": 'attachment; filename="Hinge.dmg"',
        "Cache-Control": "no-store",
      },
    });
  } catch {
    return new Response("The download is not ready yet. Please try again shortly.", {
      status: 503,
      headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store", "Retry-After": "60" },
    });
  }
}
