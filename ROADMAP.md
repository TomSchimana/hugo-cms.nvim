# Roadmap

What's on the horizon for `hugo-cms.nvim`. Nothing here is promised —
it's a catalogue of ideas, sorted by rough priority. Feedback and
suggestions welcome via issues.

## Toward v1.0

The path from the current v0.1 beta to v1.0:

- Shake out bugs reported from real use.
- Lock the public API (module layout, command names, config keys).
  Anything breaking lands before v1.0; after v1.0 it waits for v2.
- Basic automated lint in CI so typos don't sneak through.

## Feature ideas

Things that would genuinely improve daily use. Not all of them will
necessarily be built.

- **`:Hugo translate`** — scaffold a language sibling next to an
  existing bundle. Today this is a manual copy + edit; a dedicated
  command could prompt for the target language, duplicate
  `index.md` → `index.<lang>.md`, optionally ask for a per-language
  slug, and translate the title field (or leave it blank for the
  writer).

- **`description` prompt in `:Hugo new`** — meta description is one of
  the most-forgotten frontmatter fields. Optional prompt during post
  creation would help.

- **Per-language slug prompt in `:Hugo translate`** — when scaffolding
  a translation, inherit nothing and ask. See `COOKBOOK.md` for why
  per-language slugs matter.

- **Link checker** — scan `{{< ref >}}` and `{{< relref >}}` across
  the content tree and report anything that doesn't resolve. Hugo
  itself catches this at build time, but a pre-publish sanity pass
  inside the editor is useful.

- **`description` surfaced in `:Hugo open`** — second line or preview
  pane so you can spot posts still missing it.

- **Archetype-aware completion / validation** — flag frontmatter
  fields that diverge from the archetype (missing required fields,
  unknown extra fields). Would need an explicit opt-in; Hugo is
  flexible here and hugo-cms.nvim shouldn't override that by default.

## Infrastructure

- Stylua + luacheck in GitHub Actions.
- Smoke-test script or plenary-based test suite.
- Screenshots / GIF in the README once the UI has stabilised.

## Not an active goal

Feasible, but nothing's being pursued here right now. Clear demand or a
contributor stepping up could change that.

- **Windows support.** Most OS integration (`open`, `xdg-open`,
  `hugo server` process management, path handling) currently assumes a
  POSIX environment. A Windows port is possible but would need someone
  running Windows to drive and maintain it.

## Not planned

- **Hugo site scaffolding.** hugo-cms.nvim manages existing sites; it
  intentionally does not run `hugo new site`. One fewer thing to go
  wrong, and you only do it once per site anyway.

- **Theme-specific frontmatter helpers.** hugo-cms.nvim is archetype-
  driven by design — it only writes fields your archetype already
  defines. Adding "PaperMod cover support", "Anubis SEO helper" etc.
  would break that model. Themes can be served by user-defined
  archetypes; hugo-cms.nvim should stay neutral.
