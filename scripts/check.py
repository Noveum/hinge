import json
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import yaml
from pygments import lex
from pygments.lexers import get_lexer_by_name, get_lexer_for_filename
from pygments.token import Comment, String
from pygments.util import ClassNotFound

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib

ROOT = Path(__file__).resolve().parent.parent
BIOME = {".js", ".jsx", ".ts", ".tsx", ".json", ".jsonc", ".css", ".html"}
XML = {".plist", ".pbxproj", ".xcscheme", ".xml", ".svg"}
PLAIN = {"LICENSE", "web/assets/.gitkeep"}
SHELL = {
    "scripts/requirements.txt",
    ".gitignore",
    "web/.vercelignore",
    "web/.env.example",
}


def tracked():
    data = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT)
    return [Path(name.decode()) for name in data.split(b"\0") if name]


def run(arguments):
    subprocess.run(arguments, cwd=ROOT, check=True)


def lexer_for(path):
    if path.as_posix() in PLAIN:
        return get_lexer_by_name("text")
    if path.as_posix() in SHELL:
        return get_lexer_by_name("bash")
    if path.suffix in XML:
        return get_lexer_by_name("xml")
    if path.suffix == ".metal":
        return get_lexer_by_name("cpp")
    if path.name == ".swift-format" or path.suffix == ".xcstrings":
        return get_lexer_by_name("json")
    return get_lexer_for_filename(path.name)


def text_files():
    for path in tracked():
        if (ROOT / path).is_symlink():
            raise ValueError(
                f"{path}: tracked symlinks require explicit policy coverage"
            )
        data = (ROOT / path).read_bytes()
        if path.as_posix() == "Resources/AppIcon.icns":
            if not data.startswith(b"icns"):
                raise ValueError(f"{path}: invalid icon signature")
            continue
        signatures = {
            "web/assets/demo.mp4": (4, b"ftyp"),
            "web/assets/demo-poster.jpg": (0, b"\xff\xd8\xff"),
            "web/assets/og.png": (0, b"\x89PNG\r\n\x1a\n"),
        }
        if path.as_posix() in signatures:
            offset, signature = signatures[path.as_posix()]
            if data[offset : offset + len(signature)] != signature:
                raise ValueError(f"{path}: invalid media signature")
            continue
        try:
            yield path, data.decode("utf-8")
        except UnicodeDecodeError as error:
            raise ValueError(f"{path}: unclassified binary file") from error


def comment_errors(path, text, lexer, line=1):
    errors = []
    for kind, value in lex(text, lexer):
        directive = (
            kind in Comment.Preproc
            or kind in Comment.PreprocFile
            or (line == 1 and value.startswith("#!"))
        )
        if (kind in Comment and not directive) or kind in String.Doc:
            errors.append(f"{path}:{line}: comments and docstrings are forbidden")
        line += value.count("\n")
    return errors


def policy():
    errors = []
    count = 0
    for path, text in text_files():
        count += 1
        for number, line in enumerate(text.splitlines(), 1):
            if any(
                marker in line.lower()
                for marker in [
                    chr(0x2014),
                    chr(0x2014).encode("unicode_escape").decode(),
                    f"&#{0x2014};",
                    f"&#x{0x2014:x};",
                    "&" + "mdash;",
                ]
            ):
                errors.append(f"{path}:{number}: em dash is forbidden")
            if path.suffix == ".md" and (
                "<!--" in line or re.match(r"\s*\[//?\]:\s*#", line)
            ):
                errors.append(f"{path}:{number}: Markdown comment is forbidden")
        try:
            lexer = lexer_for(path)
        except ClassNotFound:
            errors.append(
                f"{path}: add an explicit language classification before tracking this file"
            )
            continue
        errors.extend(comment_errors(path, text, lexer))
        if path.suffix == ".md":
            for block in re.finditer(
                r"(?m)^(```|~~~)([^\n]*)\n(.*?)(?=^\1\s*$)", text, re.S
            ):
                language = block.group(2).strip().split()
                if language:
                    try:
                        code_lexer = get_lexer_by_name(language[0])
                    except ClassNotFound:
                        errors.append(
                            f"{path}: unsupported fenced language {language[0]}"
                        )
                        continue
                    first_line = text[: block.start(3)].count("\n") + 1
                    errors.extend(
                        comment_errors(path, block.group(3), code_lexer, first_line)
                    )
        if path.suffix in {".json", ".xcstrings"} or path.name == ".swift-format":
            try:
                json.loads(text)
            except ValueError as error:
                errors.append(f"{path}: invalid JSON: {error}")
        if path.suffix == ".toml":
            tomllib.loads(text)
        if path.suffix in {".yml", ".yaml"}:
            parsed = yaml.safe_load(text)
            if path.as_posix().startswith(".github/workflows/"):
                for job in (parsed or {}).get("jobs", {}).values():
                    for step in job.get("steps", []):
                        if isinstance(step.get("run"), str):
                            shell = step.get("shell", "bash").split()[0]
                            shell = {"pwsh": "powershell"}.get(shell, shell)
                            errors.extend(
                                comment_errors(
                                    path, step["run"], get_lexer_by_name(shell)
                                )
                            )
        if path.suffix in XML:
            try:
                ET.fromstring(text)
            except ET.ParseError as error:
                errors.append(f"{path}: invalid XML: {error}")
    if errors:
        raise ValueError("\n".join(errors))
    print(f"Policy passed for {count} tracked text files and classified binary assets")


def biome():
    files = [
        str(p) for p in tracked() if p.suffix in BIOME and p.name != "package-lock.json"
    ]
    run([str(ROOT / "node_modules/.bin/biome"), "ci", "--colors=off", *files])


def native():
    files = tracked()
    swift = [str(p) for p in files if p.suffix == ".swift"]
    if swift:
        formatter = (
            ["swift-format"]
            if shutil.which("swift-format")
            else ["xcrun", "swift-format"]
        )
        run([*formatter, "lint", "--strict", *swift])
    for path in files:
        if path.suffix in {".plist", ".pbxproj"}:
            run(["plutil", "-lint", str(path)])
    shell = [str(p) for p in files if p.suffix == ".sh"]
    if shell:
        run(["shellcheck", *shell])
    yaml = [str(p) for p in files if p.suffix in {".yml", ".yaml"}]
    if yaml:
        run(
            [
                "yamllint",
                "-d",
                "{extends: default, rules: {document-start: disable, line-length: disable, truthy: {check-keys: false}}}",
                *yaml,
            ]
        )
    workflows = [p for p in yaml if p.startswith(".github/workflows/")]
    if workflows:
        run(["actionlint", *workflows])
    python = [str(p) for p in files if p.suffix == ".py"]
    if python:
        run(["ruff", "check", *python])
        run(["ruff", "format", "--check", *python])


def links():
    files = [str(path) for path, _ in text_files()]
    run(
        [
            "lychee",
            "--config",
            ".lychee.toml",
            "--no-progress",
            "--root-dir",
            str(ROOT / "web"),
            "--remap",
            r"[f]ile://.*/web/download$ https://hinge.noveum.ai/download",
            "--remap",
            rf"[h]ttps://hinge\.noveum\.ai/assets/(.*) {(ROOT / 'web/assets').as_uri()}/$1",
            *files,
        ]
    )


if __name__ == "__main__":
    try:
        commands = {"policy": policy, "biome": biome, "native": native, "links": links}
        commands[sys.argv[1]]()
    except (ValueError, KeyError, IndexError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
