# Repository checks

Pull requests run the same checks that gate releases from `main`. No test cases or test jobs are included.

| Files | Checks |
| --- | --- |
| Every tracked text file, including dotfiles and lockfiles | No comments or docstrings, no literal or encoded em dashes, explicit language classification |
| JavaScript, TypeScript, CSS, HTML and JSON | [Biome](https://biomejs.dev/) recommended lint rules and formatting |
| Swift | [swift-format](https://github.com/swiftlang/swift-format) lint and compilation |
| Metal | Shader compilation and comment policy |
| Shell | [ShellCheck](https://www.shellcheck.net/) |
| Python | [Ruff](https://docs.astral.sh/ruff/) lint and formatting |
| Workflows and YAML | [actionlint](https://github.com/rhysd/actionlint) and [yamllint](https://yamllint.readthedocs.io/) |
| JSON, TOML and Xcode XML | Parsing, plus plist validation on macOS |
| Links in every tracked text file | [Lychee](https://lychee.cli.rs/) local-file and external-link checks |
| App icon and website media | Explicit binary classification and file signature validation |

The file list comes from `git ls-files`, not a source-folder glob. Unknown file types and unclassified binary files fail the policy check. The generated npm lockfile is parsed and policy-checked, while Biome leaves its generated formatting intact.

Comments in Markdown code fences and workflow shell blocks are checked too. Executable shebangs and compiler preprocessor directives remain allowed because they affect execution. Prose documentation and string literals are not code comments.

The link checker excludes historical X posts that require interactive access, runtime GitHub API URL templates that require authentication, and the Apple plist DTD identifier. The public `/download` endpoint remains checked. Absolute website asset URLs resolve against local tracked assets so new media can pass before deployment. The exact exclusions are in `.lychee.toml`.

## Run locally

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -r scripts/requirements.txt
npm ci
brew install actionlint shellcheck lychee yamllint swift-format
npm run check
npm run check:native
npm run check:links
make build
xcrun -sdk macosx metal -c Resources/Fold.metal -o build/Fold.air
```

Stage newly added files before running checks so they are included in the tracked-file list.
