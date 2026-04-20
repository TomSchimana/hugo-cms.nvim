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

The plugin sets no keymaps itself — use the prefix you prefer.

## Documentation

Run `:help hugo-cms` for the full reference. If it reports "not found",
the plugin is lazy-loaded — run any `:Hugo` command once to load it.

## Commands

Everything runs through `:Hugo` with subcommands. Tab completion is
available.

| Command             | Description                                     |
|---------------------|-------------------------------------------------|
| `:Hugo site`        | Register, switch, and unregister sites          |
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

Manages the list of Hugo sites the plugin knows about. You register an
existing site, switch between sites, and unregister when you're done.
Files on disk are never touched.

To create a new site, run `hugo new site <name>` in a terminal first,
then come back.

With no argument, `:Hugo site` opens a picker. You can also call the
subcommands directly:

- `:Hugo site register` — add a site. Prompts for its path and a display
  name. The first site registered becomes active.
- `:Hugo site switch` — change the active site.
- `:Hugo site unregister` — remove a site from the list. Your files
  stay on disk.

Registered sites and archetype path patterns are stored at
`$XDG_DATA_HOME/nvim/hugo-cms/sites.json` (typically
`~/.local/share/nvim/hugo-cms/sites.json`) — back it up if you want to
preserve your setup.

## Content commands

All content commands operate on the active site's `content/` tree.

### `:Hugo new`

Creates a post from an archetype. Pick the archetype, type a title,
confirm the path — done.

The path is prefilled with a saved pattern like `blog/{year}/` plus a
slug generated from your title. You can edit the slug before confirming.

On the very first post from a given archetype on a site, you also enter
the path pattern itself (default `posts/{year}/`). The pattern is saved
per site and per archetype, so later posts skip that step.

Supported placeholders:

| Placeholder | Expansion           |
|-------------|---------------------|
| `{year}`    | current year, YYYY  |
| `{month}`   | current month, MM   |
| `{day}`     | current day, DD     |

Umlauts and diacritics in titles are transliterated for the slug
(`Über mich` → `ueber-mich`). The `title` field in the frontmatter
keeps your original text. For multi-language bundles the title is
written to every language file — translate them when you're ready.

To change a saved pattern: `:Hugo site` → *Edit archetype pattern*.

### `:Hugo open`

Picker over every content page in your site. Each language version of
a bundle is listed separately. Draft flag, language, and title are
shown at a glance.

### `:Hugo resume`

Reopens the last content page you had open for the active site, across
Neovim restarts.

### `:Hugo search`

Live full-text search over your site's content. Uses whichever picker
LazyVim is set up with (snacks, Telescope, fzf-lua).

Use `:Hugo open` to browse by title, `:Hugo search` when you remember
a phrase from the body.

### `:Hugo rename`

Pick a page, type its new path. Bundles move as a directory, single-file
pages as files. You can leave off the `.md` suffix.

### `:Hugo delete`

Pick a page, confirm. If the page is part of a bundle, a second prompt
asks whether to delete the whole bundle (all languages + resources) or
just the selected language file — useful for retiring a translation
without touching the rest.

### `:Hugo draft`

Toggles the `draft` flag in the current buffer's frontmatter. For
multi-language bundles, the flag is synced across all language files so
drafts stay drafts everywhere.

### `:Hugo media`

Manages media in the active site. Without arguments it opens a picker;
subcommands work directly too.

- `import` copies a file from your disk into the site.
- `insert` drops a reference (page link, image, attachment, shortcode)
  into the current markdown.
- `cover` sets the cover image in the frontmatter.
- `rename` / `delete` work on files already in the site.

#### `:Hugo media import`

Copy any file from your disk into the site.

1. Pick the source file by browsing from your home directory.
2. Pick the destination folder inside the site.

Name collisions get a `-2`, `-3` suffix. The file is only copied — if
you want a link in the markdown, run `:Hugo media insert` afterwards.

#### `:Hugo media insert page`

Pick another page from the site, insert `[Title]({{< relref "path" >}})`
at the cursor. Hugo resolves the link at build time and picks the right
language automatically.

#### `:Hugo media insert image`

Pick an image from the current bundle or `static/`, insert `![](path)`
at the cursor.

#### `:Hugo media insert link`

Pick any non-markdown file (PDFs, ZIPs, etc.), enter a link text,
insert `[text](path)` at the cursor.

#### `:Hugo media insert shortcode`

Pick a shortcode — your own, the theme's, or a Hugo built-in. The
plugin reads the shortcode's template, prefills named parameters as
empty strings, and lands the cursor at the first parameter (or inside
the body for paired shortcodes).

#### `:Hugo media cover`

Set the cover image for the current bundle. Pick an image (same pool
as `insert image`); it's written as `cover.image` across all language
siblings.

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

Toggle tags (or categories) on the current page. The picker shows every
value used across the site: the ones already set on this page are
marked `[x]` and floated to the top, the rest are `[ ]`. A
`+ Create new…` entry lets you add a new value.

Enter toggles, the picker reopens so you can keep adding and removing.
Press Esc when you're done. Your set is written to the frontmatter and
synced across language siblings.

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

A confirmation prompt lists what will run and the working directory.
Default answer is No — you have to pick Yes explicitly. If `hugo`
fails, `deploy.sh` doesn't run.

## See also

- [CHANGELOG.md](CHANGELOG.md) — release notes
- [ROADMAP.md](ROADMAP.md) — planned work

## License

MIT — see [LICENSE](LICENSE).
