# Spectro website

The public site at **https://roost-framework.github.io/Spectro/**. Plain HTML
and CSS with a small progressive-enhancement script; no build step.

Preview locally:

```sh
python3 -m http.server --directory website 8000
```

Check before pushing:

```sh
node --check website/script.js
python3 website/check.py
```

Pushing changes under `website/` to `main` deploys the site through
`.github/workflows/pages.yml`.

- The look follows the Roost site (`roost-framework/swift-roost`, `website/`).
  Shared tokens and components are copied, not linked; keep them in step by hand.
- Keep version numbers in the hero note, family strip, and install snippets
  aligned with releases.
- Code samples must compile against the latest release tag.
