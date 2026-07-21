# rms-docs

Public documentation site for the RMS service suite, built with
[MkDocs Material](https://squidfunk.github.io/mkdocs-material/) and deployed
to GitHub Pages.

This repo contains **documentation only** — no application source code or
secrets. The underlying service repositories remain private.

## Structure

```text
rms-docs/
├── docs/                  # one page per project, synced from each repo
│   ├── index.md           # landing page
│   ├── rmdb-etl.md
│   ├── rmdb-analytics.md
│   └── ...
├── scripts/
│   └── sync-docs.sh        # copies docs/documentation.md from sibling repos
├── mkdocs.yml
└── .github/workflows/docs.yml   # builds and deploys to GitHub Pages
```

## Keeping docs up to date

Whenever a source repo's `docs/documentation.md` changes:

```bash
cd rms-docs
./scripts/sync-docs.sh
git add docs/
git commit -m "Sync documentation from source repos"
git push
```

The script expects this repo to sit alongside the source repos in the same
parent directory (as it does in the Cursor workspace). Pushing to `main`
triggers the GitHub Actions workflow, which rebuilds the site with MkDocs and
publishes it to GitHub Pages.

## Local preview

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
mkdocs serve
```

Then open http://127.0.0.1:8000.

## Site URL

Once GitHub Pages is enabled (Settings → Pages → Source: GitHub Actions),
the site is published at:

```text
https://uvindu-perera.github.io/rms-docs/
```
