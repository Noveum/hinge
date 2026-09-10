import hashlib
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ORIGIN = "https://hinge.noveum.ai"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def request(path, headers=None):
    return urllib.request.urlopen(
        urllib.request.Request(ORIGIN + path, headers=headers or {}), timeout=20
    )


def verify():
    names = (
        subprocess.check_output(
            ["git", "ls-files", "-z", "web/index.html", "web/assets"], cwd=ROOT
        )
        .decode()
        .split("\0")
    )
    for name in filter(None, names):
        local = ROOT / name
        if local.name.startswith("."):
            continue
        path = "/" if local.name == "index.html" else "/" + name.removeprefix("web/")
        with request(path) as response:
            if response.status != 200 or digest(response.read()) != digest(
                local.read_bytes()
            ):
                raise ValueError(f"Deployment has not updated {path}")
    with request("/assets/demo.mp4", {"Range": "bytes=0-1023"}) as response:
        if (
            response.status != 206
            or response.read() != (ROOT / "web/assets/demo.mp4").read_bytes()[:1024]
        ):
            raise ValueError("Video seeking is unavailable")
    expected = (ROOT / "dist/Hinge.dmg.sha256").read_text().split()[0]
    with request("/download") as response:
        if response.status != 200 or digest(response.read()) != expected:
            raise ValueError("Public download does not match this release")


def main():
    deadline = time.monotonic() + 240
    while True:
        try:
            verify()
            print("Live website assets, video seeking, and release download verified")
            return
        except (OSError, urllib.error.URLError, ValueError) as error:
            if time.monotonic() >= deadline:
                raise SystemExit(str(error)) from error
            print(f"Waiting for deployment: {error}", flush=True)
            time.sleep(15)


if __name__ == "__main__":
    main()
