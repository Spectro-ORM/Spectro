#!/usr/bin/env python3
"""Check the static site's links, fragments, images, fonts, styles, and enhancement targets."""
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
import re

ROOT = Path(__file__).resolve().parent
PAGES_ROOT = "/Spectro/"  # Project Pages root used by the 404 document.
FORBIDDEN = ("orange", "Spectro-ORM", "maartz")


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.ids = []
        self.urls = []
        self.targets = []
        self.images = []
        self.classes = set()
        self.feed(text)

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if "id" in attrs:
            self.ids.append(attrs["id"])
        self.classes.update((attrs.get("class") or "").split())
        self.urls.extend(attrs[key] for key in ("href", "src") if key in attrs)
        self.targets.extend(attrs[key] for key in ("data-copy", "data-panel") if key in attrs)
        for key in ("aria-controls", "aria-labelledby", "aria-describedby", "for"):
            self.targets.extend(attrs.get(key, "").split())
        if tag == "img":
            self.images.append(attrs)


errors = []
if not (ROOT / "index.html").is_file():
    errors.append("missing index.html")

used_classes = set()
for path in ROOT.glob("*.html"):
    page = Page(path.read_text())
    used_classes |= page.classes
    errors.extend(f"{path.name}: duplicate id {key}" for key, count in Counter(page.ids).items() if count > 1)
    errors.extend(f"{path.name}: missing target #{target}" for target in page.targets if target not in page.ids)
    for image in page.images:
        if "alt" not in image:
            errors.append(f"{path.name}: image without alt text: {image.get('src')}")
    for address in page.urls:
        url = urlsplit(address)
        if url.scheme or url.netloc or url.path == PAGES_ROOT:
            continue
        target = ROOT / (url.path or path.name)
        if url.path and not target.exists():
            errors.append(f"{path.name}: missing file {url.path}")
        if url.fragment and target.is_file() and target.suffix == ".html":
            if url.fragment not in Page(target.read_text()).ids:
                errors.append(f"{path.name}: missing fragment {address}")

for path in [*ROOT.glob("*.html"), *ROOT.glob("*.css"), *ROOT.glob("*.js")]:
    text = path.read_text()
    errors.extend(f"{path.name}: contains {word!r}" for word in FORBIDDEN if word in text)

for stylesheet in ROOT.glob("*.css"):
    text = stylesheet.read_text()
    for asset in re.findall(r"url\(['\"]?([^)'\"]+)", text):
        if not urlsplit(asset).scheme and not (stylesheet.parent / asset).is_file():
            errors.append(f"{stylesheet.name}: missing asset {asset}")
    rules = re.sub(r"/\*.*?\*/|url\([^)]*\)", "", text, flags=re.S)
    selectors = " ".join(re.findall(r"([^{}]+)\{", rules))
    for name in sorted(set(re.findall(r"\.(-?[_a-zA-Z][\w-]*)", selectors)) - used_classes):
        errors.append(f"{stylesheet.name}: unused class .{name}")

if errors:
    raise SystemExit("\n".join(errors))
print("Site check passed: links, fragments, images, fonts, styles, and enhancement targets.")
