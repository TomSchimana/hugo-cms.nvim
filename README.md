# hugo-cms.nvim

A "CMS" for [Hugo](https://gohugo.io) sites, living inside Neovim. You
register your sites once and drive them from there — no leaving the
editor to poke around in the filesystem or a terminal.

> **Status:** v0.1 — first public release, beta. Every command works,
> but the API may still change before v1.0. See [CHANGELOG.md](CHANGELOG.md)
> for release notes and [ROADMAP.md](ROADMAP.md) for what's next.

## Requirements

- Neovim 0.10 or newer
- [folke/snacks.nvim](https://github.com/folke/snacks.nvim) — required.
  All pickers and prompts use it.
- [LazyVim](https://www.lazyvim.org/) — only if you want `:Hugo search`
  (live full-text grep). Everything else works without it.
- The `hugo` command, installed and callable from your shell. See the
  [Hugo installation guide](https://gohugo.io/installation/).
- The `rg` (ripgrep) command, installed and callable from your shell.
  Needed for `:Hugo search` and the broken-reference scan after media
  rename / delete. Install with `brew install ripgrep` or
  `apt install ripgrep`.
- macOS or Linux. Windows is untested and some features may not work
  there (see [ROADMAP.md](ROADMAP.md)).

## Installation

Example spec for [lazy.nvim](https://github.com/folke/lazy.nvim); adapt
to whichever plugin manager you use.

```lua
{
  "TomSchimana/hugo-cms.nvim",
  dependencies = { "folke/snacks.nvim" },
  cmd = "Hugo",
  opts = {},
  keys = {
    { "<leader>hS", "<cmd>Hugo site<cr>",    desc = "Hugo: sites" },
    { "<leader>hn", "<cmd>Hugo new<cr>",     desc = "Hugo: new content" },
    { "<leader>ho", "<cmd>Hugo open<cr>",    desc = "Hugo: open content" },
    { "<leader>hr", "<cmd>Hugo resume<cr>",  desc = "Hugo: resume last page" },
    { "<leader>hs", "<cmd>Hugo search<cr>",  desc = "Hugo: search content" },
    { "<leader>hR", "<cmd>Hugo rename<cr>",  desc = "Hugo: rename content" },
    { "<leader>hD", "<cmd>Hugo delete<cr>",  desc = "Hugo: delete content" },
    { "<leader>hd", "<cmd>Hugo draft<cr>",   desc = "Hugo: toggle draft" },
    { "<leader>ht", "<cmd>Hugo tags<cr>",    desc = "Hugo: tags" },
    { "<leader>hc", "<cmd>Hugo categories<cr>", desc = "Hugo: categories" },
    { "<leader>hm", "<cmd>Hugo media<cr>",   desc = "Hugo: media" },
    { "<leader>hf", "<cmd>Hugo filebrowser<cr>", desc = "Hugo: file browser" },
    { "<leader>hp", "<cmd>Hugo preview<cr>",      desc = "Hugo: preview" },
    { "<leader>hP", "<cmd>Hugo preview stop<cr>", desc = "Hugo: stop preview" },
    { "<leader>h!", "<cmd>Hugo publish<cr>",      desc = "Hugo: publish" },
  },
}
```

hugo-cms.nvim sets no keymaps itself — use the prefix you prefer.

## Documentation

Run `:help hugo-cms` for the full reference. If it reports "not found",
hugo-cms.nvim is lazy-loaded — run any `:Hugo` command once to load it.

## Commands

Everything runs through `:Hugo` with subcommands. Tab completion is
available.

| Command             | Description                                     |
|---------------------|-------------------------------------------------|
| `:Hugo site`        | Register / switch / unregister sites, edit patterns |
| `:Hugo new`         | Create content from an archetype                |
| `:Hugo open`        | Picker over content, all languages              |
| `:Hugo resume`      | Reopen the last content page for the active site|
| `:Hugo search`      | Live full-text search over `content/`           |
| `:Hugo rename`      | Rename / move content (bundle-aware)            |
| `:Hugo delete`      | Delete content (bundle-aware)                   |
| `:Hugo draft`       | Toggle draft flag across all languages          |
| `:Hugo tags`        | Toggle `tags` frontmatter list                  |
| `:Hugo categories`  | Toggle `categories` frontmatter list            |
| `:Hugo media`       | Import / insert / cover (bundle + static/images)|
| `:Hugo filebrowser` | Open current folder in the system file manager  |
| `:Hugo preview`     | Toggle `hugo server` + browser                  |
| `:Hugo publish`     | Build + run `deploy.sh`                         |

## `:Hugo site`

Manages the list of Hugo sites you've registered with hugo-cms.nvim. A
"site" is any folder with a Hugo config (`hugo.toml`, `hugo.yaml`, or
the older `config.toml`) in it. Register once, switch between them
whenever. Nothing on disk is ever touched.

To start a brand-new site, run `hugo new site <name>` in a terminal
first, then come back to register it.

With no argument, `:Hugo site` opens a picker. You can also call the
subcommands directly:

- `:Hugo site register` — add a site. Two prompts:

  ```
  Site path:    ~/sites/myblog      (your Hugo project root)
  Display name: My Blog             (label shown in pickers)
  ```

  The first registered site becomes active.

- `:Hugo site switch` — change the active site.

- `:Hugo site unregister` — remove a site from the list. Your files
  stay on disk.

- `:Hugo site pattern` — set or change the **path pattern** for one of
  the site's archetypes. A path pattern decides where new posts from
  that archetype land inside `content/`. Examples:

  | Pattern                | Result for a post titled "Hello"    |
  |------------------------|-------------------------------------|
  | `posts/{year}/`        | `content/posts/2026/hello.md`       |
  | `blog/{year}/{month}/` | `content/blog/2026/04/hello.md`     |
  | `notes/`               | `content/notes/hello.md` (flat)     |

  Supported placeholders (all zero-padded):

  | Placeholder | Expansion          |
  |-------------|--------------------|
  | `{year}`    | current year, YYYY |
  | `{month}`   | current month, MM  |
  | `{day}`     | current day, DD    |

  Patterns are saved per site and per archetype. The first time you run
  `:Hugo new` with a given archetype, you're prompted for the pattern;
  after that it's remembered. Run `:Hugo site pattern` to change it
  later.

Registered sites and archetype path patterns are stored at
`$XDG_DATA_HOME/nvim/hugo-cms/sites.json` (typically
`~/.local/share/nvim/hugo-cms/sites.json`) — back it up if you want to
preserve your setup.

## Content commands

All content commands operate on the active site's `content/` tree.

A **bundle** (Hugo's term) is a folder with `index.md` plus related
files — language siblings like `index.de.md`, images, attachments —
treated as one page. A **single-file page** is just a `.md` file on
its own. Most commands work on both; where they behave differently,
it's called out.

**Multilingual sites are supported.** Hugo stores translations as
language-suffixed siblings (`index.de.md`, `index.fr.md`) next to the
default-language file. hugo-cms.nvim picks that up: commands that write
metadata (draft flag, tags, categories, cover image) sync across every
sibling so translations stay in step, and `:Hugo rename` / `:Hugo delete`
move or remove the whole bundle by default with an opt-out for
per-language scope.

### `:Hugo new`

Creates a post from one of your archetypes. Three prompts:

1. **Archetype** — picker over everything in `archetypes/`. Single-file
   archetypes (`post.md`) produce a single-file page; directory
   archetypes (`post/` with `index.md` and siblings) produce a bundle
   with the same layout.
2. **Title** — plain text, e.g. `My first post`.
3. **Path** — prefilled with the archetype's path pattern plus a slug
   derived from your title. Edit the slug if you like before hitting
   enter.

A concrete run with the `post` archetype and title `My first post`:

```
Archetype: post
Title:     My first post
Path:      posts/2026/my-first-post
```

Result on disk: `content/posts/2026/my-first-post.md`, copied from the
archetype, with `title: "My first post"` filled into the frontmatter.
If the archetype is a bundle, you get a directory
`content/posts/2026/my-first-post/` with `index.md` (plus language
siblings like `index.de.md` if the archetype has them).

Umlauts and diacritics in titles are transliterated for the slug
(`Über mich` → `ueber-mich`). The frontmatter `title` keeps your
original text. For multi-language bundles the title is written to every
language file — translate them when you're ready.

The first time you use a given archetype you're prompted for its path
pattern — see `:Hugo site pattern` above for how patterns work and how
to change one later.

### `:Hugo open`

Picker over every content page in your site. Each language version of
a bundle is listed separately. Rows look like:

```
   --   posts/2026/hello                Hello world
d  --   drafts/wip                      Work in progress
   --   posts/2026/my-first-post        My first post
   de   posts/2026/my-first-post        My first post
```

Columns, left to right: draft flag (`d` for drafts, blank otherwise),
language, path inside `content/`, title. Enter opens the file.

The language column reflects the filename suffix: `de` for `index.de.md`,
`fr` for `index.fr.md`, and so on. `--` means the file has no language
suffix (e.g. plain `index.md` or `hello.md`) — Hugo treats those as the
site's **default language**. If your `defaultContentLanguage` is `en`,
every `--` row is an English page.

### `:Hugo resume`

Reopens the last content page you had open for the active site, across
Neovim restarts.

### `:Hugo search`

Live full-text search over your site's content. Uses whichever picker
LazyVim is set up with (snacks, Telescope, fzf-lua).

Use `:Hugo open` to browse by title, `:Hugo search` when you remember
a phrase from the body.

### `:Hugo rename`

Pick a page, type its new path. Bundles move as a whole directory,
single-file pages as files. You can leave off the `.md` suffix.

Example: to rename `posts/2026/hello.md` to `posts/2026/hello-world.md`,
type `posts/2026/hello-world` in the prompt. To move a post into a
different section, include the new parent: `blog/2026/hello-world`.

### `:Hugo delete`

Pick a page, confirm. If the page is part of a bundle, a second prompt
lets you choose the scope:

- **Whole bundle** — removes the directory, all language files, and
  any bundled resources (images etc. next to `index.md`).
- **This language file only** — removes just `index.de.md` (or whichever
  language you picked), leaving `index.md` and other translations
  intact. Use this to retire a single translation.

### `:Hugo draft`

*Needs a content file open in the active buffer.* Toggles the `draft`
flag in the current buffer's frontmatter. For multi-language bundles,
the flag is synced across all language files so drafts stay drafts
everywhere.

### `:Hugo media`

Manages media in the active site. Without arguments it opens a picker;
subcommands work directly too.

- `import` copies a file from your disk into the site.
- `insert` drops a reference (page link, image, attachment, shortcode)
  into the current markdown. *Needs a markdown file open in the active
  buffer — that's what gets written into.*
- `cover` sets the cover image in the frontmatter. *Needs any file
  from the target bundle open.*
- `rename` / `delete` work on files already in the site.

#### `:Hugo media import`

Copy any file from your disk into the site.

1. Pick the source file by browsing from your home directory.
2. Pick the destination folder inside the site.

Name collisions get a `-2`, `-3` suffix. The file is only copied — if
you want a link in the markdown, run `:Hugo media insert` afterwards.

#### `:Hugo media insert page`

*Needs a markdown file open.* Pick another page from the site, insert
`[Title]({{< relref "path" >}})` at the cursor. Hugo resolves the link
at build time and picks the right language automatically.

#### `:Hugo media insert image`

*Needs a markdown file open.* Pick an image from the current bundle
or `static/`, insert `![](path)` at the cursor.

#### `:Hugo media insert link`

*Needs a markdown file open.* Pick any non-markdown file (PDFs, ZIPs,
etc.), enter a link text, insert `[text](path)` at the cursor.

#### `:Hugo media insert shortcode`

*Needs a markdown file open.* Pick a shortcode — your own from
`layouts/shortcodes/`, the theme's, or a Hugo built-in. hugo-cms.nvim
reads the shortcode's template, picks up its named parameters, and
inserts them prefilled as empty strings.

Example: inserting a `figure` shortcode with parameters `src`, `alt`,
`caption` drops this at the cursor:

```
{{< figure src="" alt="" caption="" >}}
```

The cursor lands inside the first empty `""` so you can start typing.
For paired shortcodes like `{{< quote >}}…{{< /quote >}}` the cursor
lands inside the body instead.

#### `:Hugo media cover`

*Needs any file from the target bundle open.* Set the cover image for
the current bundle. Pick an image (same pool as `insert image`); it's
written as `cover.image` across all language siblings.

If the frontmatter already has a `cover.alt` field, you're also
prompted for alt text — it's written only to the current language.
Other cover fields (`relative`, `caption`, `hidden`) aren't touched:
put them in your archetype if you want them preseeded.

#### `:Hugo media rename` / `:Hugo media delete`

Rename or delete a media file in place. Markdown files aren't in the
pool. Renames can't cross directories.

Neither command updates markdown links pointing at the file. A ripgrep
scan afterwards tells you how many files still reference the old name.

### `:Hugo tags` / `:Hugo categories`

*Needs a content file open in the active buffer.* Toggle tags (or
categories) on the current page. The picker shows every
value used anywhere in the site: values already set on this page are
marked `[x]` and floated to the top, the rest are `[ ]`. A
`+ Create new…` entry at the bottom lets you add a value that doesn't
exist yet.

Example picker view on a post that already has two tags:

```
[x] photography
[x] travel
[ ] food
[ ] music
[ ] neovim
[ ] + Create new…
```

Enter toggles the selected row and reopens the picker, so you can keep
adding and removing in one flow. Press Esc when you're done. Your set
is written to the frontmatter and synced across language siblings.

### `:Hugo filebrowser`

Opens Finder (macOS) or your Linux file manager. If your current buffer
is inside the active site, its directory opens — otherwise the site
root.

### `:Hugo preview`

Starts `hugo server` in a terminal split at the bottom of the screen
and opens the browser at the current page. Drafts and future posts are
included in the preview.

URL from the current buffer:

- `content/_index.md` → `http://localhost:1313/`
- `content/posts/2026/hello.md` → `http://localhost:1313/posts/2026/hello/`
- `content/posts/2026/hello/index.de.md` → `http://localhost:1313/de/posts/2026/hello/`
- Buffers outside `content/` fall back to the site root.

The URL is derived from the file path; unusual permalink or language
configs may not be reflected exactly.

Running `:Hugo preview` again while the server is already running just
opens the current page in the browser — handy for jumping between
pages. To stop: `:Hugo preview stop`, or close the terminal. The
server also shuts down when you quit Neovim. One preview at a time.

### `:Hugo publish`

Builds the site with `hugo` and, if the site root contains a
`deploy.sh`, runs it afterwards. Output streams into a terminal split
at the bottom.

**Why a script, not a built-in uploader?** Deployment looks completely
different from site to site — `rsync` to a VPS, `sftp` into shared
hosting, `git push` to a provider that builds on their side, `aws s3
sync`, Netlify CLI, whatever. Covering all of those natively would
mean endless config knobs. A plain `deploy.sh` keeps it simple: you
write whatever your host needs, hugo-cms.nvim just runs it after a
successful build.

Minimal example — rsync to a server:

```bash
#!/usr/bin/env bash
set -euo pipefail
rsync -avz --delete public/ user@example.com:/var/www/mysite/
```

Make it executable (`chmod +x deploy.sh`) and put it at the site root
next to `hugo.toml`.

A confirmation prompt lists what will run and the working directory.
Default answer is No — you have to pick Yes explicitly. If `hugo`
fails, `deploy.sh` doesn't run.

## See also

- [CHANGELOG.md](CHANGELOG.md) — release notes
- [ROADMAP.md](ROADMAP.md) — planned work

## License

MIT — see [LICENSE](LICENSE).
