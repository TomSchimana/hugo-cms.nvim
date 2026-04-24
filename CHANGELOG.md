# Changelog

All notable changes to this project. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project
follows semantic versioning, with the understanding that anything
pre-1.0 is allowed to break between minor versions.

## [Unreleased]

### Changed

- **`:Hugo publish`** no longer runs `hugo` itself — it now runs
  `deploy.sh` directly. The script is responsible for both the build
  and the upload. This gives full control over `hugo` flags
  (`--minify`, `--gc`, custom environments …) and keeps deploy
  transport entirely in the user's hands. If no `deploy.sh` exists,
  the command aborts with an error instead of silently building.

## [0.1.0] — 2026-04-20

First public release. Beta.

### Added

- `:Hugo site` — register, switch, and unregister Hugo sites. Registry
  is persisted as JSON under `$XDG_DATA_HOME/nvim/hugo-cms/sites.json`.
- `:Hugo new` — create content from archetypes. Per-site, per-archetype
  path patterns (`blog/{year}/` etc.) keep repeat creation fast. Slug
  derivation handles German umlauts and common Latin diacritics.
- `:Hugo open` — picker over all content, all languages. Shared column
  layout used by every content picker (draft flag + language + path +
  title).
- `:Hugo resume` — reopen the last content page for the active site
  across Neovim restarts.
- `:Hugo search` — live full-text search over `content/` via LazyVim's
  picker.
- `:Hugo rename` — bundle-aware move / rename.
- `:Hugo delete` — bundle-aware delete with a second picker for the
  bundle-scope vs single-language-file choice.
- `:Hugo draft` — toggle draft flag, synced across all language
  siblings of a bundle.
- `:Hugo tags` / `:Hugo categories` — toggle taxonomy lists against a
  sitewide-collected value set. Writes YAML in block form, TOML in
  inline form.
- `:Hugo media import` — copy any file from disk into the site with a
  two-step picker (source + destination).
- `:Hugo media insert page | image | link | shortcode` — insert
  references at the cursor. Shortcode insertion discovers named
  parameters from the template body.
- `:Hugo media cover` — archetype-driven cover image: writes
  `cover.image` to every language sibling, prompts for `cover.alt`
  only if the field already exists in the archetype, and never
  fabricates theme-specific fields.
- `:Hugo media rename` / `delete` — manage media files. Runs a
  ripgrep scan afterwards and reports any remaining references.
- `:Hugo filebrowser` — open current folder in the system file
  manager.
- `:Hugo preview` — `hugo server` in a terminal split, browser opens
  at the current buffer's page. Winbar acts as status line and
  separator. Safe shutdown on Neovim exit.
- `:Hugo publish` — build + run `deploy.sh` with an explicit confirm
  prompt.
- `:help hugo-cms` — full command reference in the Neovim help viewer.

### Known limitations

- Windows is untested; some features may not work there.
- Unusual permalink configs and `defaultContentLanguageInSubdir` are
  not reflected in the preview URL.
- `:Hugo media rename` / `delete` do not rewrite markdown references —
  the ripgrep scan surfaces remaining references but does not auto-fix
  them.
- JSON frontmatter is readable but not supported for writes.

[Unreleased]: https://github.com/TomSchimana/hugo-cms.nvim/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/TomSchimana/hugo-cms.nvim/releases/tag/v0.1.0
