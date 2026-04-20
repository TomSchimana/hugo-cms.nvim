-- `:Hugo media` — media management (import, rename, delete, insert, cover).
--
-- Top-level picker without args, or direct sub-subcommands:
--   :Hugo media import            — copy any file from disk into the site
--                                    (picker for source + destination)
--   :Hugo media rename            — rename a media file in-place
--   :Hugo media delete            — delete a media file (with confirm)
--   :Hugo media insert page       — insert [title]({{< relref "…" >}})
--   :Hugo media insert image      — insert ![](…) from site's images
--   :Hugo media insert link       — insert [text](…) from any file
--   :Hugo media insert shortcode  — insert {{< name >}} (or paired form)
--   :Hugo media cover             — set PaperMod cover.image (all lang siblings)
--
-- `rename` and `delete` do NOT rewrite markdown references. After each
-- operation a ripgrep scan under `content/` reports how many files
-- still reference the old basename so the user can fix them up.

local M = {}

local config = require("hugo-cms.config")
local content = require("hugo-cms.content")
local content_label = require("hugo-cms.content_label")
local frontmatter = require("hugo-cms.frontmatter")
local picker = require("hugo-cms.picker")

local function notify(msg, level)
  vim.notify("hugo-cms: " .. msg, level or vim.log.levels.INFO)
end

local IMAGE_EXTS = {
  png = true, jpg = true, jpeg = true, webp = true,
  gif = true, svg = true, avif = true,
}

local function is_image(name)
  local ext = name:match("%.([^.]+)$")
  return ext and IMAGE_EXTS[ext:lower()] == true
end

local function is_md(name)
  return name:match("%.md$") ~= nil
end

local function is_index_md(name)
  return name:match("^index%.md$") ~= nil
    or name:match("^index%.[%w%-]+%.md$") ~= nil
end

local function starts_with(s, prefix)
  return s:sub(1, #prefix) == prefix
end

-- Pick a non-colliding filename inside `dir` based on the desired `name`.
local function dedupe_name(dir, name)
  if vim.loop.fs_stat(dir .. "/" .. name) == nil then
    return name
  end
  local stem, ext = name:match("^(.+)(%.[^.]+)$")
  if not stem then stem, ext = name, "" end
  local i = 2
  while vim.loop.fs_stat(dir .. "/" .. stem .. "-" .. i .. ext) do
    i = i + 1
  end
  return stem .. "-" .. i .. ext
end

-- Return bundle_dir if the current buffer is an `index(.lang)?.md` inside
-- the active site's content/ tree; nil otherwise.
local function current_bundle_dir(site)
  local name = vim.api.nvim_buf_get_name(0)
  if not name or name == "" then return nil end
  local path = vim.fs.normalize(name)
  local content_root = vim.fs.normalize(site.path .. "/content") .. "/"
  if not starts_with(path, content_root) then return nil end
  local base = vim.fs.basename(path)
  if not is_index_md(base) then return nil end
  return vim.fs.dirname(path)
end

-- Non-recursive: list files in a single directory matching `filter(name)`.
local function scan_files(dir, filter)
  local out = {}
  if vim.fn.isdirectory(dir) == 0 then return out end
  local handle = vim.loop.fs_scandir(dir)
  if not handle then return out end
  while true do
    local name, ftype = vim.loop.fs_scandir_next(handle)
    if not name then break end
    if ftype == "file" and filter(name) then
      out[#out + 1] = { path = dir .. "/" .. name, name = name }
    end
  end
  return out
end

-- Recursive: walk `root` and collect all files whose basename matches
-- `filter`. Returns { path, name, rel } entries where `rel` is the path
-- relative to `root` (no leading slash).
local function scan_files_recursive(root, filter)
  local out = {}
  local function walk(dir, rel_prefix)
    local handle = vim.loop.fs_scandir(dir)
    if not handle then return end
    while true do
      local name, ftype = vim.loop.fs_scandir_next(handle)
      if not name then break end
      if not name:match("^%.") then
        local sub = dir .. "/" .. name
        local rel = rel_prefix == "" and name or (rel_prefix .. "/" .. name)
        if ftype == "directory" then
          walk(sub, rel)
        elseif ftype == "file" and filter(name) then
          out[#out + 1] = { path = sub, name = name, rel = rel }
        end
      end
    end
  end
  if vim.fn.isdirectory(root) == 1 then
    walk(root, "")
  end
  return out
end

-- Build a pool of { kind, path, name, link, cover } from current bundle
-- (non-recursive) + `static/**` (recursive), filtered by `filter(name)`.
-- `link` is the markdown-ready path, `cover` is the frontmatter form
-- (bare filename for bundle resources, `/path` for static assets).
local function build_pool(site, bundle_dir, filter)
  local pool = {}
  if bundle_dir then
    local files = scan_files(bundle_dir, function(n)
      return filter(n) and not is_index_md(n)
    end)
    table.sort(files, function(a, b) return a.name < b.name end)
    for _, f in ipairs(files) do
      pool[#pool + 1] = {
        kind = "bundle",
        path = f.path,
        name = f.name,
        link = "./" .. f.name,
        cover = f.name,
      }
    end
  end
  local static_root = site.path .. "/static"
  local statics = scan_files_recursive(static_root, filter)
  table.sort(statics, function(a, b) return a.rel < b.rel end)
  for _, f in ipairs(statics) do
    pool[#pool + 1] = {
      kind = "static",
      path = f.path,
      name = f.name,
      rel = f.rel,
      link = "/" .. f.rel,
      cover = "/" .. f.rel,
    }
  end
  return pool
end

local function format_pool_item(item)
  if item.kind == "bundle" then
    return "[bundle]  " .. item.name
  end
  return "[static]  " .. item.rel
end

-- Insert text at the current cursor position. Works in any mode; leaves
-- the cursor at the end of the inserted text.
local function insert_at_cursor(text)
  local buf = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  vim.api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, { text })
  vim.api.nvim_win_set_cursor(0, { row, col + #text })
end

-- Destination directory picker ---------------------------------------------

local DEST_ROOTS = { "content", "static", "assets" }
local DEST_EXCLUDES = {
  [".git"] = true, ["public"] = true, ["resources"] = true,
  ["themes"] = true, ["node_modules"] = true,
}

-- Recursively collect all directories (relative to site root) under
-- `content/`, `static/`, and `assets/`, skipping hidden and build dirs.
local function list_destination_dirs(site)
  local dirs = {}
  local function walk(abs, rel)
    dirs[#dirs + 1] = { rel = rel, abs = abs }
    local handle = vim.loop.fs_scandir(abs)
    if not handle then return end
    while true do
      local name, ftype = vim.loop.fs_scandir_next(handle)
      if not name then break end
      if ftype == "directory"
        and not name:match("^%.")
        and not DEST_EXCLUDES[name]
      then
        local sub_rel = rel == "" and name or (rel .. "/" .. name)
        walk(abs .. "/" .. name, sub_rel)
      end
    end
  end
  for _, top in ipairs(DEST_ROOTS) do
    local abs = site.path .. "/" .. top
    if vim.fn.isdirectory(abs) == 1 then
      walk(abs, top)
    end
  end
  table.sort(dirs, function(a, b) return a.rel < b.rel end)
  return dirs
end

-- Source path picker -------------------------------------------------------

-- Drill-down directory browser. Starts at `start_dir`, shows `../` plus
-- sorted directories (suffixed with `/`) and files. Selecting a directory
-- descends; selecting a file invokes `callback(absolute_path)`. Hidden
-- entries (dotfiles) are skipped. Uses `picker.select` so it works with
-- snacks and with plain `vim.ui.select` alike.
local function pick_source_path(callback)
  local function browse(dir)
    local handle = vim.loop.fs_scandir(dir)
    if not handle then
      notify("cannot read directory: " .. dir, vim.log.levels.ERROR)
      return
    end

    local dirs, files = {}, {}
    while true do
      local name, ftype = vim.loop.fs_scandir_next(handle)
      if not name then break end
      if not name:match("^%.") then
        if ftype == "directory" then
          dirs[#dirs + 1] = {
            kind = "dir",
            path = dir .. "/" .. name,
            label = name .. "/",
          }
        elseif ftype == "file" then
          files[#files + 1] = {
            kind = "file",
            path = dir .. "/" .. name,
            label = name,
          }
        elseif ftype == "link" then
          -- Resolve symlinks to their target type.
          local real = dir .. "/" .. name
          local stat = vim.loop.fs_stat(real)
          if stat and stat.type == "directory" then
            dirs[#dirs + 1] = {
              kind = "dir", path = real, label = name .. "/",
            }
          elseif stat and stat.type == "file" then
            files[#files + 1] = {
              kind = "file", path = real, label = name,
            }
          end
        end
      end
    end
    table.sort(dirs, function(a, b) return a.label < b.label end)
    table.sort(files, function(a, b) return a.label < b.label end)

    local entries = { { kind = "up", label = "../" } }
    for _, d in ipairs(dirs) do entries[#entries + 1] = d end
    for _, f in ipairs(files) do entries[#entries + 1] = f end

    picker.select(entries, {
      prompt = "Import: pick file to copy into the site — " .. dir,
      format_item = function(e) return e.label end,
    }, function(choice)
      if not choice then return end
      if choice.kind == "up" then
        browse(vim.fs.dirname(dir))
      elseif choice.kind == "dir" then
        browse(choice.path)
      else
        callback(choice.path)
      end
    end)
  end

  browse(vim.fn.expand("~"))
end

-- :Hugo media import -------------------------------------------------------

-- Copy a file from disk into a chosen directory inside the site.
-- Two-step picker: source, then destination.
function M.import()
  local site = config.get_active()
  if not site then
    notify("no active site.", vim.log.levels.ERROR)
    return
  end

  pick_source_path(function(src)
    if vim.fn.filereadable(src) == 0 then
      notify("file not readable: " .. src, vim.log.levels.ERROR)
      return
    end

    local dirs = list_destination_dirs(site)
    if #dirs == 0 then
      notify("no destination directories found under "
        .. table.concat(DEST_ROOTS, "/, "), vim.log.levels.WARN)
      return
    end

    local bundle_dir = current_bundle_dir(site)
    local bundle_rel
    if bundle_dir then
      bundle_rel = bundle_dir:sub(#site.path + 2)
      -- Move the current bundle to the top of the list.
      for i, d in ipairs(dirs) do
        if d.abs == bundle_dir then
          table.remove(dirs, i)
          table.insert(dirs, 1, d)
          break
        end
      end
    end

    picker.select(dirs, {
      prompt = "Import: pick destination folder inside the site",
      format_item = function(d)
        if bundle_rel and d.rel == bundle_rel then
          return d.rel .. "  (current bundle)"
        end
        return d.rel
      end,
    }, function(dst)
      if not dst then return end
      local src_basename = vim.fs.basename(src)
      local final_name = dedupe_name(dst.abs, src_basename)
      local dst_path = dst.abs .. "/" .. final_name

      local ok, err = vim.loop.fs_copyfile(src, dst_path)
      if not ok then
        notify("copy failed: " .. tostring(err), vim.log.levels.ERROR)
        return
      end
      notify("imported " .. final_name .. " → " .. dst.rel)
    end)
  end)
end

-- :Hugo media insert image -------------------------------------------------

function M.insert_image()
  local site = config.get_active()
  if not site then
    notify("no active site.", vim.log.levels.ERROR)
    return
  end

  local bundle_dir = current_bundle_dir(site)
  local pool = build_pool(site, bundle_dir, is_image)
  if #pool == 0 then
    notify("no images found in bundle or static/", vim.log.levels.WARN)
    return
  end

  picker.select(pool, {
    prompt = "Insert image",
    format_item = format_pool_item,
  }, function(item)
    if not item then return end
    insert_at_cursor("![](" .. item.link .. ")")
    notify("inserted ![](" .. item.link .. ")")
  end)
end

-- :Hugo media insert page --------------------------------------------------

-- Compute the `relref` path for an entry, relative to `content/`, without
-- a `.md` suffix and without a language suffix (Hugo resolves to the
-- current page's language automatically). Bundles use their directory.
local function relref_for(entry)
  if entry.kind == "bundle" then
    return entry.bundle_rel
  end
  local path = entry.file_rel:gsub("%.md$", "")
  if entry.lang then
    path = path:gsub("%." .. vim.pesc(entry.lang) .. "$", "")
  end
  return path
end

function M.insert_page()
  local site = config.get_active()
  if not site then
    notify("no active site.", vim.log.levels.ERROR)
    return
  end

  local entries = content.scan_content(site.path)
  if #entries == 0 then
    notify("no content found in this site", vim.log.levels.WARN)
    return
  end

  local format_item = content_label.prepare(entries)

  picker.select(entries, {
    prompt = "Insert page link",
    format_item = format_item,
  }, function(entry)
    if not entry then return end
    local ref = relref_for(entry)
    local title = entry.title or ref
    local md = "[" .. title .. "]({{< relref \"" .. ref .. "\" >}})"
    insert_at_cursor(md)
    notify("inserted page link → " .. ref)
  end)
end

-- :Hugo media insert shortcode ---------------------------------------------

-- Built-in Hugo shortcodes. `params` lists the named parameters the
-- shortcode accepts; we pre-fill these as empty strings so the user sees
-- a usable skeleton instead of a bare `{{< name >}}`.
local BUILTIN_SHORTCODES = {
  { name = "figure",    paired = false, params = { "src", "alt", "caption" } },
  { name = "gist",      paired = false, params = { "user", "id" } },
  { name = "highlight", paired = true,  params = { "lang" } },
  { name = "instagram", paired = false, params = { "id" } },
  { name = "param",     paired = false, params = { "name" } },
  { name = "ref",       paired = false, params = { "path" } },
  { name = "relref",    paired = false, params = { "path" } },
  { name = "tweet",     paired = false, params = { "user", "id" } },
  { name = "vimeo",     paired = false, params = { "id" } },
  { name = "youtube",   paired = false, params = { "id" } },
}

-- Parse a shortcode template body. Returns `paired` (true iff `.Inner`
-- is used) and an ordered list of parameter names discovered from
-- `.Get "foo"` / `.Get 'foo'` calls. Order follows first appearance and
-- duplicates are skipped.
local function parse_template_body(body)
  local paired = body:find("%.Inner") ~= nil
  local params, seen = {}, {}
  local function add(name)
    if not seen[name] then
      seen[name] = true
      params[#params + 1] = name
    end
  end
  for name in body:gmatch('%.Get%s*"([^"]+)"') do add(name) end
  for name in body:gmatch("%.Get%s*'([^']+)'") do add(name) end
  return paired, params
end

local function template_info(path)
  local f = io.open(path, "r")
  if not f then return false, {} end
  local body = f:read("*a") or ""
  f:close()
  return parse_template_body(body)
end

local function scan_shortcode_dir(dir)
  local out = {}
  if vim.fn.isdirectory(dir) == 0 then return out end
  local handle = vim.loop.fs_scandir(dir)
  if not handle then return out end
  while true do
    local name, ftype = vim.loop.fs_scandir_next(handle)
    if not name then break end
    if ftype == "file" then
      local base = name:match("^(.+)%.html$")
      if base then
        local paired, params = template_info(dir .. "/" .. name)
        out[#out + 1] = { name = base, paired = paired, params = params }
      end
    end
  end
  return out
end

-- Collect shortcodes from site, themes, and built-ins. Site-level
-- definitions shadow theme and built-in names (Hugo's own override
-- order).
local function collect_shortcodes(site)
  local seen = {}
  local pool = {}
  local function add(sc, source)
    if seen[sc.name] then return end
    seen[sc.name] = true
    pool[#pool + 1] = {
      name = sc.name,
      paired = sc.paired,
      params = sc.params or {},
      source = source,
    }
  end

  for _, sc in ipairs(scan_shortcode_dir(site.path .. "/layouts/shortcodes")) do
    add(sc, "site")
  end

  local themes_dir = site.path .. "/themes"
  if vim.fn.isdirectory(themes_dir) == 1 then
    local h = vim.loop.fs_scandir(themes_dir)
    if h then
      while true do
        local theme, ftype = vim.loop.fs_scandir_next(h)
        if not theme then break end
        if ftype == "directory" and not theme:match("^%.") then
          local sub = themes_dir .. "/" .. theme .. "/layouts/shortcodes"
          for _, sc in ipairs(scan_shortcode_dir(sub)) do
            add(sc, "theme:" .. theme)
          end
        end
      end
    end
  end

  for _, sc in ipairs(BUILTIN_SHORTCODES) do
    add(sc, "builtin")
  end

  table.sort(pool, function(a, b) return a.name < b.name end)
  return pool
end

local function format_shortcode_item(item)
  local suffix = ""
  if item.params and #item.params > 0 then
    suffix = suffix .. "  " .. #item.params .. " param(s)"
  end
  if item.paired then suffix = suffix .. "  (paired)" end
  return "[" .. item.source .. "]  " .. item.name .. suffix
end

-- Build the opening tag for a shortcode. Returns the tag string and the
-- byte offset inside it where the cursor should land:
--   no params, paired     → `{{< x >}}` — cursor after the tag (body).
--   no params, unpaired   → `{{< x  >}}` — cursor on the inner space so
--                           the user types `key="value"` straight in.
--   with params           → `{{< x a="" b="" >}}` — cursor between the
--                           quotes of the first param.
local function build_open_tag(name, params)
  if #params == 0 then
    local tag = "{{< " .. name .. "  >}}"
    local cursor = #"{{< " + #name + 1
    return tag, cursor, true
  end
  local parts = {}
  for _, p in ipairs(params) do
    parts[#parts + 1] = p .. '=""'
  end
  local tag = "{{< " .. name .. " " .. table.concat(parts, " ") .. " >}}"
  -- Cursor lands between the two quotes of the first param.
  local cursor = #"{{< " + #name + 1 + #params[1] + 2
  return tag, cursor, false
end

function M.insert_shortcode()
  local site = config.get_active()
  if not site then
    notify("no active site.", vim.log.levels.ERROR)
    return
  end

  local pool = collect_shortcodes(site)
  if #pool == 0 then
    notify("no shortcodes found", vim.log.levels.WARN)
    return
  end

  picker.select(pool, {
    prompt = "Insert shortcode",
    format_item = format_shortcode_item,
  }, function(item)
    if not item then return end

    local params = item.params or {}
    local open, cursor_offset, no_params = build_open_tag(item.name, params)
    local text = open
    if item.paired then
      text = text .. "{{< /" .. item.name .. " >}}"
      -- For paired with no params, the nicest spot is the body (between
      -- the tags), not the empty opener.
      if no_params then cursor_offset = #open end
    end

    local buf = vim.api.nvim_get_current_buf()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    vim.api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, { text })
    vim.api.nvim_win_set_cursor(0, { row, col + cursor_offset })

    notify("inserted shortcode " .. item.name .. " (" .. item.source .. ")")
  end)
end

-- :Hugo media insert link --------------------------------------------------

function M.insert_link()
  local site = config.get_active()
  if not site then
    notify("no active site.", vim.log.levels.ERROR)
    return
  end

  local bundle_dir = current_bundle_dir(site)
  local pool = build_pool(site, bundle_dir, function(n) return not is_md(n) end)
  if #pool == 0 then
    notify("no files found in bundle or static/", vim.log.levels.WARN)
    return
  end

  picker.select(pool, {
    prompt = "Insert link",
    format_item = format_pool_item,
  }, function(item)
    if not item then return end
    vim.schedule(function()
      vim.ui.input({
        prompt = "Link text: ",
        default = item.name,
      }, function(text)
        if text == nil then return end
        if text == "" then text = item.name end
        local md = "[" .. text .. "](" .. item.link .. ")"
        insert_at_cursor(md)
        notify("inserted " .. md)
      end)
    end)
  end)
end

-- Reference scan (best-effort) --------------------------------------------

-- Count content/ files that reference `basename`. Returns nil if rg is
-- unavailable or errors out (swallowed silently).
local function count_references(site, basename)
  if vim.fn.executable("rg") ~= 1 then return nil end
  local content_dir = site.path .. "/content"
  if vim.fn.isdirectory(content_dir) == 0 then return 0 end
  local res = vim.system({
    "rg", "-l", "--fixed-strings", basename, content_dir,
  }, { text = true }):wait()
  -- rg exits 0 if matches, 1 if none, 2+ on error.
  if res.code > 1 then return nil end
  local count = 0
  for _ in (res.stdout or ""):gmatch("[^\n]+") do count = count + 1 end
  return count
end

local function warn_refs(site, basename, verb)
  local n = count_references(site, basename)
  if n == nil or n == 0 then return end
  notify(n .. " file(s) under content/ still reference '" .. basename
    .. "' after " .. verb .. " — update them manually",
    vim.log.levels.WARN)
end

-- :Hugo media cover --------------------------------------------------------

function M.cover()
  local site = config.get_active()
  if not site then
    notify("no active site.", vim.log.levels.ERROR)
    return
  end

  local bundle_dir = current_bundle_dir(site)
  if not bundle_dir then
    notify("cover is bundle-specific — open a bundle index*.md first",
      vim.log.levels.ERROR)
    return
  end

  local pool = build_pool(site, bundle_dir, is_image)
  if #pool == 0 then
    notify("no images found in bundle or static/", vim.log.levels.WARN)
    return
  end

  -- The buffer the user invoked the command from identifies which
  -- language sibling is "current" — that's where the alt text lands
  -- (alt is per-language; the image itself is bundle-wide).
  local current_file = vim.fs.normalize(vim.api.nvim_buf_get_name(0))

  picker.select(pool, {
    prompt = "Set cover image",
    format_item = format_pool_item,
  }, function(item)
    if not item then return end

    local siblings = content.language_siblings({
      kind = "bundle",
      bundle_dir = bundle_dir,
    })

    -- Archetype-driven alt: prompt only if `cover.alt` already exists
    -- in the current file's frontmatter. If the author's archetype
    -- doesn't define alt, the plugin won't fabricate it.
    local existing_alt = frontmatter.read_cover_alt(current_file)

    local function apply(alt)
      local changed = 0
      for _, s in ipairs(siblings) do
        local alt_for_this = nil
        if alt ~= nil and vim.fs.normalize(s.file) == current_file then
          alt_for_this = alt
        end
        local ok, err = frontmatter.set_cover_image(
          s.file, item.cover, alt_for_this)
        if not ok then
          notify("failed on " .. s.file .. ": " .. (err or "?"),
            vim.log.levels.ERROR)
          return
        end
        changed = changed + 1
      end
      vim.cmd("checktime")
      local alt_note = alt and ", alt updated" or ""
      notify("cover = " .. item.cover
        .. " (" .. changed .. " lang variants" .. alt_note .. ")")
    end

    if existing_alt == nil then
      -- No alt field in frontmatter → skip prompt entirely.
      apply(nil)
      return
    end

    vim.schedule(function()
      vim.ui.input({
        prompt = "Alt text: ",
        default = existing_alt,
      }, function(alt)
        -- Cancelled (Esc) → don't change anything at all.
        if alt == nil then return end
        apply(alt)
      end)
    end)
  end)
end

-- :Hugo media rename -------------------------------------------------------

function M.rename()
  local site = config.get_active()
  if not site then
    notify("no active site.", vim.log.levels.ERROR)
    return
  end

  local bundle_dir = current_bundle_dir(site)
  local pool = build_pool(site, bundle_dir, function(n) return not is_md(n) end)
  if #pool == 0 then
    notify("no media files found in bundle or static/", vim.log.levels.WARN)
    return
  end

  picker.select(pool, {
    prompt = "Rename media",
    format_item = format_pool_item,
  }, function(item)
    if not item then return end
    -- Schedule so the picker fully closes before the input prompt opens.
    vim.schedule(function()
      vim.ui.input({
        prompt = "New name: ",
        default = item.name,
      }, function(new_name)
        if not new_name or new_name == "" then return end
        if new_name == item.name then return end
        if new_name:find("/") then
          notify("new name must not contain '/' — rename within the same directory only",
            vim.log.levels.ERROR)
          return
        end
        local dir = vim.fs.dirname(item.path)
        local new_path = dir .. "/" .. new_name
        if vim.loop.fs_stat(new_path) then
          notify("target already exists: " .. new_name,
            vim.log.levels.ERROR)
          return
        end
        local ok, err = vim.loop.fs_rename(item.path, new_path)
        if not ok then
          notify("rename failed: " .. tostring(err), vim.log.levels.ERROR)
          return
        end
        notify("renamed " .. item.name .. " → " .. new_name)
        warn_refs(site, item.name, "rename")
      end)
    end)
  end)
end

-- :Hugo media delete -------------------------------------------------------

function M.delete()
  local site = config.get_active()
  if not site then
    notify("no active site.", vim.log.levels.ERROR)
    return
  end

  local bundle_dir = current_bundle_dir(site)
  local pool = build_pool(site, bundle_dir, function(n) return not is_md(n) end)
  if #pool == 0 then
    notify("no media files found in bundle or static/", vim.log.levels.WARN)
    return
  end

  picker.select(pool, {
    prompt = "Delete media",
    format_item = format_pool_item,
  }, function(item)
    if not item then return end
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Delete '" .. item.name .. "'?",
    }, function(answer)
      if answer ~= "Yes" then return end
      local ok, err = vim.loop.fs_unlink(item.path)
      if not ok then
        notify("delete failed: " .. tostring(err), vim.log.levels.ERROR)
        return
      end
      notify("deleted " .. item.name)
      warn_refs(site, item.name, "delete")
    end)
  end)
end

-- Subcommand dispatch ------------------------------------------------------

local INSERT_KINDS = {
  page = M.insert_page,
  image = M.insert_image,
  link = M.insert_link,
  shortcode = M.insert_shortcode,
}

local function dispatch_insert(args)
  local kind = args and args[1]
  if kind then
    local fn = INSERT_KINDS[kind]
    if not fn then
      notify("unknown insert kind: " .. kind
        .. " (expected page|image|link|shortcode)",
        vim.log.levels.ERROR)
      return
    end
    fn()
    return
  end

  local items = {
    { key = "page", label = "Insert Page" },
    { key = "image", label = "Insert Image" },
    { key = "link", label = "Insert Link" },
    { key = "shortcode", label = "Insert Shortcode" },
  }
  picker.select(items, {
    prompt = "Insert",
    format_item = function(it) return it.label end,
  }, function(choice)
    if not choice then return end
    INSERT_KINDS[choice.key]()
  end)
end

local actions = {
  import = function() M.import() end,
  insert = dispatch_insert,
  cover = function() M.cover() end,
  rename = function() M.rename() end,
  delete = function() M.delete() end,
}

function M.complete(arglead, rest)
  rest = rest or {}
  -- Depth 1: user is completing the kind after "insert".
  if rest[1] == "insert"
    and (#rest == 1 or (#rest == 2 and arglead ~= ""))
  then
    local out = {}
    for name in pairs(INSERT_KINDS) do
      if name:find("^" .. vim.pesc(arglead)) then
        out[#out + 1] = name
      end
    end
    table.sort(out)
    return out
  end
  -- Depth 0: user is completing the first media subcommand.
  if #rest == 0 or (#rest == 1 and arglead ~= "") then
    local names = {}
    for name in pairs(actions) do
      if name:find("^" .. vim.pesc(arglead)) then
        names[#names + 1] = name
      end
    end
    table.sort(names)
    return names
  end
  return {}
end

function M.run(args)
  local sub = args and args[1]
  if sub then
    local action = actions[sub]
    if not action then
      notify("unknown media subcommand: " .. sub, vim.log.levels.ERROR)
      return
    end
    local rest = {}
    for i = 2, #args do rest[#rest + 1] = args[i] end
    action(rest)
    return
  end

  local items = {
    { key = "import", action = function() M.import() end,
      label = "Import Media" },
    { key = "rename", action = function() M.rename() end,
      label = "Rename Media" },
    { key = "delete", action = function() M.delete() end,
      label = "Delete Media" },
    { key = "insert_page", action = function() M.insert_page() end,
      label = "Insert Page" },
    { key = "insert_image", action = M.insert_image,
      label = "Insert Image" },
    { key = "insert_link", action = M.insert_link,
      label = "Insert Link" },
    { key = "insert_shortcode", action = function() M.insert_shortcode() end,
      label = "Insert Shortcode" },
    { key = "cover", action = function() M.cover() end,
      label = "Set Cover Image" },
  }
  picker.select(items, {
    prompt = "Media",
    format_item = function(it) return it.label end,
  }, function(choice)
    if not choice then return end
    choice.action()
  end)
end

return M
