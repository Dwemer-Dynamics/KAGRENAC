#!/usr/bin/env python3
"""Build reviewed client/server release archives from one repository (Python 3 stdlib)."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import unicodedata
import zipfile

MAX_FILES = 20000
MAX_BYTES = 512 * 1024 * 1024
MAX_AUTHOR = 80


def run(*args, cwd=None):
    result = subprocess.run(args, cwd=cwd, capture_output=True, check=True)
    return result.stdout.decode("utf-8").strip()


def relative(value):
    if not isinstance(value, str) or not value or len(value) > 200 or "\\" in value:
        raise ValueError("Use a relative POSIX path of at most 200 characters.")
    if any(not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9._-]*", p) for p in value.split("/")):
        raise ValueError("Paths cannot contain hidden, empty or traversal segments: " + value)
    if any(p.endswith(".") or re.fullmatch(r"(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])", p.split(".")[0]) for p in value.split("/")):
        raise ValueError("Package paths cannot use Windows device names or trailing dots.")
    return value


def matches(path, pattern):
    # Component-aware glob: * never crosses /; ** matches zero or more components.
    segments = pattern.split("/")
    parts = path.split("/")

    def visit(i, j):
        if i == len(segments):
            return j == len(parts)
        if segments[i] == "**":
            return visit(i + 1, j) or (j < len(parts) and visit(i, j + 1))
        expression = re.escape(segments[i]).replace(r"\*", "[^/]*").replace(r"\?", "[^/]")
        return j < len(parts) and re.fullmatch(expression, parts[j]) is not None and visit(i + 1, j + 1)

    return visit(0, 0)


def selection(spec):
    if not isinstance(spec, dict) or set(spec) - {"root", "include", "exclude", "install"}:
        raise ValueError("Package rules contain unsupported fields.")
    root = spec.get("root", ".")
    if not isinstance(root, str):
        raise ValueError("Package root must be a relative directory.")
    root = root.rstrip("/")
    if root != ".":
        relative(root)
    for key in ("include", "exclude"):
        patterns = spec.get(key, [] if key == "exclude" else None)
        if not isinstance(patterns, list) or len(patterns) > 64 or (key == "include" and not patterns):
            raise ValueError("Each package needs a non-empty include list (at most 64 patterns).")
        for pattern in patterns:
            if not isinstance(pattern, str) or len(pattern) > 200 or any(
                    p in ("", ".", "..") or not re.fullmatch(r"[A-Za-z0-9_.*?][A-Za-z0-9._*?-]*", p)
                    for p in pattern.split("/")):
                raise ValueError("Unsupported package pattern: " + str(pattern))
    return root


def validate(manifest):
    if not isinstance(manifest, dict):
        raise ValueError("dwemer-mod.json must be an object.")
    if type(manifest.get("schema_version")) is not int or manifest["schema_version"] != 2:
        raise ValueError("Publishing needs dwemer-mod.json schema_version 2; existing v1 installs stay unchanged.")
    required = {"schema_version", "id", "name", "dashboard_path", "health_path", "requirements", "setup", "game", "distribution"}
    optional = {"description", "project_url", "assets", "branches", "server_folder", "features", "testing", "author"}
    if required - set(manifest) or set(manifest) - required - optional:
        raise ValueError("Manifest has missing or unsupported version 2 fields.")
    if not re.fullmatch(r"[a-z][a-z0-9-]{1,30}[a-z0-9]", manifest.get("id", "")):
        raise ValueError("Use your own 3-32 character mod id.")
    if "--" in manifest["id"] or manifest["id"] == "example-server":
        raise ValueError("Use your own mod id, not the template identity or repeated hyphens.")
    for key, maximum in (("name", 60), ("description", 300)):
        value = manifest.get(key, "" if key == "description" else None)
        if not isinstance(value, str) or len(value) > maximum or (key == "name" and not value.strip()) or any(ord(c) < 32 for c in value):
            raise ValueError("Invalid manifest " + key)
    if "author" in manifest:
        # Optional author/team display name, matched by Core; without it the launcher shows the repository owner.
        author = manifest["author"]
        if not isinstance(author, str) or not author.strip() or len(author.strip()) > MAX_AUTHOR:
            raise ValueError("author must be a name of at most 80 characters.")
        if any(unicodedata.category(c) in {"Cc", "Cf", "Cs", "Zl", "Zp"} for c in author):
            raise ValueError("author contains control characters.")
    if manifest["requirements"] != {"php": "8.2", "postgresql": True} or manifest["requirements"].get("postgresql") is not True:
        raise ValueError("requirements must specify PHP 8.2 and PostgreSQL.")
    setup = manifest["setup"]
    if not isinstance(setup, dict) or set(setup) != {"config_template", "config_path", "migrate_script", "token_placeholder", "database_placeholder"}:
        raise ValueError("Use the standard server setup fields.")
    if not setup["config_path"].startswith("config/") or setup["config_path"] == setup["config_template"]:
        raise ValueError("Private config must be separate from its template and beneath config/.")
    for key in ("token_placeholder", "database_placeholder"):
        if not isinstance(setup[key], str) or not re.fullmatch(r"[A-Za-z0-9_]{6,64}", setup[key]):
            raise ValueError("Config placeholders must be 6-64 letters, digits or underscores.")
    if setup["token_placeholder"] == setup["database_placeholder"]:
        raise ValueError("Config placeholders must differ.")
    relative(manifest["health_path"])
    if manifest["dashboard_path"] != "/":
        relative(manifest["dashboard_path"].rstrip("/"))
    assets = manifest.get("assets", {})
    if not isinstance(assets, dict) or set(assets) - {"icon", "banner"}:
        raise ValueError("assets supports icon and banner only.")
    for path in assets.values():
        relative(path)
        if not path.lower().endswith((".png", ".jpg", ".jpeg")):
            raise ValueError("Artwork must be PNG or JPEG.")
    if manifest.get("server_folder") and not re.fullmatch(r"[A-Z][A-Za-z0-9]{0,40}Server", manifest["server_folder"]):
        raise ValueError("server_folder must be a name such as MyModServer.")
    features = manifest.get("features", [])
    if not isinstance(features, list) or len(features) > 16 or any(not isinstance(f, str) or not f.strip() or len(f) > 120 or any(ord(c) < 32 for c in f) for f in features):
        raise ValueError("features must list at most 16 short gameplay descriptions.")
    testing = manifest.get("testing", {})
    if not isinstance(testing, dict) or set(testing) - {"summary", "evidence_path"}:
        raise ValueError("testing supports summary and a repository-relative evidence_path.")
    if "summary" in testing and (not isinstance(testing["summary"], str) or len(testing["summary"]) > 500):
        raise ValueError("testing.summary must be at most 500 characters.")
    if "evidence_path" in testing:
        relative(testing["evidence_path"])
    distribution = manifest.get("distribution", {})
    if set(distribution) != {"server", "client"}:
        raise ValueError("distribution must contain server and client package rules.")
    selection(distribution["server"])
    selection(distribution["client"])
    game = manifest.get("game", {})
    if not game.get("name") or not game.get("id"):
        raise ValueError("game.id and game.name are required.")
    relative(game.get("executable"))
    install = distribution["client"].get("install", {})
    if set(install) != {"profile", "path", "config_path"} or install["profile"] != "game-directory":
        raise ValueError("client.install needs game-directory profile, path and config_path.")
    relative(install["path"])
    relative(install["config_path"])
    if not install["config_path"].endswith(".json"):
        raise ValueError("The game-directory profile pairs a private Kagrenac JSON client config.")
    for field in ("config_template", "config_path", "migrate_script"):
        relative(manifest["setup"][field])
    return manifest


def private_file(path, config_path):
    segments = path.lower().split("/")
    return (path.casefold() in {config_path.casefold(), config_path.casefold() + ".lock"} or any(p in {".git", ".env", "node_modules", "__pycache__"} for p in segments)
            or segments[-1].endswith((".pem", ".key", ".pfx", ".dump"))
            or segments[-1] in {"config.json", "credentials.json", "secrets.json"})


def pick(spec, files, private):
    chosen = {}
    for path, data in files:
        if not any(matches(path, pattern) for pattern in spec["include"]):
            continue
        if any(matches(path, pattern) for pattern in spec.get("exclude", [])):
            continue
        if private_file(path, private):
            raise ValueError("Package rules selected private/runtime data: " + path)
        relative(path)
        chosen[path] = data
    if not chosen or len(chosen) > MAX_FILES or sum(map(len, chosen.values())) > MAX_BYTES:
        raise ValueError("Package is empty or exceeds 20,000 files / 512 MiB.")
    if len({p.casefold() for p in chosen}) != len(chosen):
        raise ValueError("Package has paths which collide on Windows.")
    return chosen


def write_package(directory, name, files):
    destination = directory / name
    with zipfile.ZipFile(destination, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for path, data in sorted(files.items()):
            info = zipfile.ZipInfo(path, (2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    return {"asset": name, "sha256": hashlib.sha256(destination.read_bytes()).hexdigest(),
            "size": destination.stat().st_size,
            "files": [{"path": p, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
                      for p, data in sorted(files.items())]}


def package(args):
    repo = Path(args.repo).resolve()
    if run("git", "rev-parse", "--show-toplevel", cwd=repo).replace("\\", "/").casefold() != repo.as_posix().casefold():
        raise ValueError("--repo must name the repository root.")
    if run("git", "status", "--porcelain", "--untracked-files=normal", cwd=repo):
        raise ValueError("Commit the reviewed source first; packaging refuses a dirty repository.")
    commit = run("git", "rev-parse", "HEAD", cwd=repo)
    raw = subprocess.check_output(["git", "show", "HEAD:dwemer-mod.json"], cwd=repo)
    if len(raw) > 16384:
        raise ValueError("dwemer-mod.json exceeds Core's 16 KiB manifest limit.")
    manifest = validate(json.loads(raw))
    repository = manifest.get("project_url", "").removesuffix(".git").rstrip("/")
    if not re.fullmatch(r"https://github.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Set project_url to this mod's public GitHub repository.")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}", args.version):
        raise ValueError("Use a simple version/tag, such as v1.0.0.")
    spec = manifest["distribution"]["server"]
    source_root = selection(spec)
    prefix = "" if source_root == "." else source_root + "/"
    entries = subprocess.check_output(["git", "ls-tree", "-r", "-l", "-z", "HEAD"], cwd=repo).split(b"\0")
    evidence = manifest.get("testing", {}).get("evidence_path")
    if evidence and not any(item.split(b"\t", 1)[-1].decode("utf-8") == evidence for item in filter(None, entries)):
        raise ValueError("testing.evidence_path must name a committed source file.")
    server_files = []
    server_bytes = 0
    for item in filter(None, entries):
        metadata, path_raw = item.split(b"\t", 1)
        path = path_raw.decode("utf-8")
        if not path.startswith(prefix):
            continue
        short = path[len(prefix):]
        if any(matches(short, p) for p in spec["include"]) and not any(matches(short, p) for p in spec.get("exclude", [])):
            if not metadata.startswith((b"100644 blob ", b"100755 blob ")):
                raise ValueError("Packages cannot contain symlinks or submodules: " + path)
            server_bytes += int(metadata.split()[3])
            if server_bytes > MAX_BYTES or len(server_files) >= MAX_FILES:
                raise ValueError("Server package exceeds 20,000 files / 512 MiB.")
            data = subprocess.check_output(["git", "show", "HEAD:" + path], cwd=repo)
            server_files.append((short, data))
    server = pick(spec, server_files, manifest["setup"]["config_path"])
    server["dwemer-mod.json"] = raw
    required = [manifest["health_path"], manifest["setup"]["config_template"], manifest["setup"]["migrate_script"]]
    required += list(manifest.get("assets", {}).values())
    for path in required:
        if path not in server:
            raise ValueError("Rules excluded a required runtime/artwork file: " + path)
    template = server[manifest["setup"]["config_template"]].decode("utf-8")
    for key in ("token_placeholder", "database_placeholder"):
        if sum(template.count(q + manifest["setup"][key] + q) for q in ("'", '"')) != 1:
            raise ValueError("Config placeholders must each occur once as quoted PHP strings.")
    client_dir = Path(args.client_dir).resolve()
    if client_dir == repo or repo in client_dir.parents:
        raise ValueError("Client build output must be outside source.")
    client_spec = manifest["distribution"]["client"]
    client_root = selection(client_spec)
    base = client_dir if client_root == "." else client_dir / client_root
    if base.resolve() != base or not base.is_dir():
        raise ValueError("Client root must be a plain build directory, without links or junctions.")
    client_files = []
    client_bytes = 0
    for current, dirs, names in os.walk(base, followlinks=False):
        for name in dirs[:]:
            path = Path(current) / name
            short = path.relative_to(base).as_posix()
            if any(matches(short, pattern) for pattern in client_spec.get("exclude", [])):
                dirs.remove(name)
            elif path.resolve() != path:
                raise ValueError("Client build output contains a linked directory.")
        for name in names:
            path = Path(current) / name
            short = path.relative_to(base).as_posix()
            if not any(matches(short, pattern) for pattern in client_spec["include"]) or any(matches(short, pattern) for pattern in client_spec.get("exclude", [])):
                continue
            if path.resolve() != path or not path.is_file():
                raise ValueError("Client build output contains a link.")
            client_bytes += path.stat().st_size
            if client_bytes > MAX_BYTES or len(client_files) >= MAX_FILES:
                raise ValueError("Client package exceeds 20,000 files / 512 MiB.")
            client_files.append((short, path.read_bytes()))
    client = pick(client_spec, client_files, client_spec["install"]["config_path"])
    directory = Path(args.output).resolve()
    if directory == repo or repo in directory.parents:
        raise ValueError("Release output must be outside source.")
    directory.mkdir(parents=True, exist_ok=False)
    packages = {"server": write_package(directory, manifest["id"] + "-server.zip", server),
                "client": write_package(directory, manifest["id"] + "-client.zip", client)}
    document = {"schema_version": 1, "repository": repository, "commit": commit, "version": args.version,
                "manifest": manifest, "packages": packages}
    (directory / "kagrenac-release.json").write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(directory), "commit": commit, "version": args.version,
                      "packages": {k: {"files": len(v["files"]), "bytes": v["size"], "sha256": v["sha256"]}
                                   for k, v in packages.items()}}, indent=2))


def publish(args):
    directory = Path(args.output).resolve()
    document = json.loads((directory / "kagrenac-release.json").read_text(encoding="utf-8"))
    repository = document["repository"].removeprefix("https://github.com/")
    if args.confirm_publish != repository:
        raise ValueError("Review the package, then authorize publication with --confirm-publish " + repository)
    actual = json.loads(run("gh", "repo", "view", repository, "--json", "nameWithOwner,isPrivate"))
    if actual["isPrivate"]:
        raise ValueError("This public catalog cannot publish private repositories or change their visibility.")
    run("gh", "api", "repos/" + repository + "/git/commits/" + document["commit"])
    refs = json.loads(run("gh", "api", "repos/" + repository + "/git/matching-refs/tags/" + document["version"]))
    exact = next((ref["object"] for ref in refs if ref["ref"] == "refs/tags/" + document["version"]), None)
    if exact:
        for _ in range(4):
            if exact["type"] != "tag":
                break
            exact = json.loads(run("gh", "api", "repos/" + repository + "/git/tags/" + exact["sha"]))["object"]
        if exact["type"] != "commit" or exact["sha"] != document["commit"]:
            raise ValueError("An existing release tag points to another commit. Choose a new version.")
    assets = [directory / "kagrenac-release.json"]
    for package_info in document["packages"].values():
        path = directory / relative(package_info["asset"])
        if hashlib.sha256(path.read_bytes()).hexdigest() != package_info["sha256"]:
            raise ValueError("Release archive changed after packaging.")
        assets.append(path)
    notes = document["manifest"].get("description", "") + "\n\n" + "\n".join("- " + feature for feature in document["manifest"].get("features", []))
    notes += "\n\nAuthor-reported testing: " + document["manifest"].get("testing", {}).get("summary", "Not provided.")
    notes += "\n\nClient and server built from " + document["commit"]
    run("gh", "release", "create", document["version"], "--repo", repository, "--draft", "--target",
        document["commit"], "--title", document["manifest"]["name"] + " " + document["version"],
        "--notes", notes, *map(str, assets))
    run("gh", "release", "edit", document["version"], "--repo", repository, "--draft=false")
    run("gh", "repo", "edit", repository, "--add-topic", "kagrenac-mod")
    print("Published " + document["repository"] + "/releases/tag/" + document["version"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("package", help="Build and preview; does not publish.")
    build.add_argument("--repo", default=str(Path(__file__).resolve().parent.parent))
    build.add_argument("--client-dir", required=True)
    build.add_argument("--version", required=True)
    build.add_argument("--output", required=True)
    upload = commands.add_parser("publish", help="Publish already reviewed packages and opt into discovery.")
    upload.add_argument("--output", required=True)
    upload.add_argument("--confirm-publish", required=True, help="Exact owner/repo authorized for publication.")
    args = parser.parse_args()
    try:
        (package if args.command == "package" else publish)(args)
    except (ValueError, KeyError, TypeError, AttributeError, RecursionError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print("[FAIL] " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
