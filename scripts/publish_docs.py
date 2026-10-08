#!/usr/bin/env python3
"""Publish each release's documentation archive into a GitHub Pages site.

Usage: python3 scripts/publish_docs.py SITE_DIR --repository OWNER/NAME

Every published release asset named *.doccarchive.zip is transformed for static
hosting at /NAME/TAG/. SITE_DIR/docs/ lists the versions, newest first, and
SITE_DIR/docs/latest/ redirects to the newest one. Requires gh (authenticated
through GH_TOKEN), ditto, and docc, so run it on macOS.
"""

import argparse
import html
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def run(arguments, **kwargs):
    return subprocess.run([str(argument) for argument in arguments], check=True, **kwargs)


def gh(*arguments):
    return run(["gh", *arguments], stdout=subprocess.PIPE, text=True).stdout


def version_key(tag):
    numbers = [int(part) for part in re.findall(r"\d+", tag)]
    return (bool(numbers), numbers)


def redirect(path, target):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        '<!doctype html><meta charset="utf-8">'
        f'<meta http-equiv="refresh" content="0; url={target}">'
        f'<link rel="canonical" href="{target}"><a href="{target}">Documentation</a>\n'
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("site", type=Path, help="the Pages site directory being assembled")
    parser.add_argument("--repository", required=True, help="OWNER/NAME; NAME is the Pages path")
    args = parser.parse_args()
    name = args.repository.split("/")[-1]
    docc = shutil.which("docc") or run(["xcrun", "--find", "docc"], stdout=subprocess.PIPE, text=True).stdout.strip()

    releases = json.loads(gh("release", "list", "--repo", args.repository, "--limit", "200",
                             "--json", "tagName,isDraft,isPrerelease"))
    tags = sorted((r["tagName"] for r in releases if not r["isDraft"] and not r["isPrerelease"]),
                  key=version_key, reverse=True)
    published = []
    with tempfile.TemporaryDirectory(prefix="docs-") as temporary:
        for tag in tags:
            assets = json.loads(gh("release", "view", tag, "--repo", args.repository, "--json", "assets"))["assets"]
            if not any(asset["name"].endswith(".doccarchive.zip") for asset in assets):
                continue
            download = Path(temporary) / tag
            gh("release", "download", tag, "--repo", args.repository,
               "--pattern", "*.doccarchive.zip", "--dir", download)
            for archive_zip in download.glob("*.doccarchive.zip"):
                run(["ditto", "-x", "-k", archive_zip, download])
            archive = next(download.glob("*.doccarchive"))
            output = args.site / tag
            output.mkdir(parents=True)
            run([docc, "process-archive", "transform-for-static-hosting", archive,
                 "--output-path", output, "--hosting-base-path", f"{name}/{tag}"])
            # DocC keeps the archive's own base path in the root page; send visitors to the docs.
            redirect(output / "index.html", "documentation/")
            published.append(tag)
            print(f"Published {name} {tag} documentation", flush=True)

    items = "\n".join(
        f'    <li><a href="../{html.escape(tag)}/documentation/">{html.escape(tag)}</a>'
        + (" (latest)" if index == 0 else "") + "</li>"
        for index, tag in enumerate(published))
    body = f"  <ul>\n{items}\n  </ul>" if published else "  <p>No release documentation has been published yet.</p>"
    docs = args.site / "docs"
    docs.mkdir(parents=True, exist_ok=True)
    (docs / "index.html").write_text(f"""<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(name)} documentation</title>
<style>body {{ font: 16px/1.5 system-ui, sans-serif; max-width: 40rem; margin: 3rem auto; padding: 0 1rem; }}</style>
<main>
  <h1>{html.escape(name)} documentation</h1>
  <p>Documentation for each release. <a href="../">Back to the {html.escape(name)} website</a>.</p>
{body}
</main>
</html>
""")
    if published:
        redirect(docs / "latest" / "index.html", f"../../{published[0]}/documentation/")


if __name__ == "__main__":
    main()
