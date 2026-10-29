# fleet-ci

Shared continuous-integration checks for a small fleet of personal
websites, packaged as GitHub Actions **reusable workflows**.

The main workflow is
[`.github/workflows/fleet-ci.yml`](.github/workflows/fleet-ci.yml).
Other repositories run it with one short caller job:

```yaml
jobs:
  fleet-ci:
    uses: andrewdhorowitz/fleet-ci/.github/workflows/fleet-ci.yml@main
```

Four more fleet workflows live here on the same pattern
(kit v3.7): `fleet-links.yml` (Markdown link-rot check),
`fleet-lighthouse.yml` (report-only Lighthouse audit of a
caller's public page — the caller passes its URL),
`fleet-tests.yml` (pytest runner), and `fleet-smoke.yml`
(Playwright smoke runner). Each is called the same way, from a
thin caller file in the repository that uses it.

## What the main workflow checks

- **Python** — lint and byte-compile for the Python files a caller
  names (ruff).
- **Web** — syntax-checks the JavaScript embedded in a site's HTML
  pages and validates the HTML, using the caller's own validation
  config when it provides one.
- **Workflows** — lints the caller's workflow files themselves
  (actionlint).

Every step whose files are absent skips cleanly, so one workflow
serves plain pages, small apps, and documentation sites alike.

## Why this repository is public

GitHub's rule is that a **public** repository can only call reusable
workflows hosted in **public** repositories, so the shared workflow
lives here, in the open, where every site in the fleet can reach it.
Nothing private belongs in this repository: it holds the workflow
file and this README, by design.

## Maintenance

The workflow's source of truth is maintained with the owner's
private site-template kit; improvements are copied into this
repository when they land, and callers pick them up automatically
on their next run (they pin `@main`).
