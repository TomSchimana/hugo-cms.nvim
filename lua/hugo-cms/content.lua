-- Content and archetype scanning helpers.
--
-- Each "entry" returned by `scan_content` is one pickable item: a single
-- Markdown page, or one language version of a leaf bundle.

local M = {}

local frontmatter = require("hugo-cms.frontmatter")

-- Split a filename base into (stem, language). `index.en` -> "index","en";
-- `index` -> "index",nil; `my-post.fr` -> "my-post","fr". The language code
-- is assumed to be 2–5 alphanumeric characters (enough for "en", "de", "pt-br",
-- etc.).
local function split_language(basename_no_ext)
  local stem, lang = basename_no_ext:match("^(.+)%.([%w][%w%-]*)$")
  if stem and lang and #lang <= 5 then
    return stem, lang
  end
  return basename_no_ext, nil
end

local function join(a, b)
  if a == "" then return b end
  return a .. "/" .. b
end

local function walk(dir, relative, out)
  local handle = vim.loop.fs_scandir(dir)
  if not handle then return end
  while true do
    local name, ftype = vim.loop.fs_scandir_next(handle)
    if not name then break end
    local abs = dir .. "/" .. name
    local rel = join(relative, name)
    if ftype == "directory" then
      -- Leaf bundle?  directory containing any `index(.lang)?.md`.
      local index_entries = {}
      local sub = vim.loop.fs_scandir(abs)
      if sub then
        while true do
          local n, t = vim.loop.fs_scandir_next(sub)
          if not n then break end
          if t == "file" then
            local stem_ext = n:match("^(.+)%.md$")
            if stem_ext then
              local stem, lang = split_language(stem_ext)
              if stem == "index" then
                index_entries[#index_entries + 1] = {
                  file = abs .. "/" .. n,
                  lang = lang,
                }
              end
            end
          end
        end
      end

      if #index_entries > 0 then
        for _, ie in ipairs(index_entries) do
          out[#out + 1] = {
            kind = "bundle",
            bundle_dir = abs,
            bundle_rel = rel,
            file = ie.file,
            lang = ie.lang,
            section = rel:match("^([^/]+)") or rel,
          }
        end
      else
        walk(abs, rel, out)
      end
    elseif ftype == "file" then
      local stem_ext = name:match("^(.+)%.md$")
      if stem_ext then
        local stem, lang = split_language(stem_ext)
        -- Skip `index.*.md` without a sibling bundle directory (handled above).
        if stem ~= "index" or relative ~= "" then
          if stem ~= "_index" then
            out[#out + 1] = {
              kind = "single",
              file = abs,
              file_rel = rel,
              lang = lang,
              stem = stem,
              section = rel:match("^([^/]+)") or rel,
            }
          end
        end
      end
    end
  end
end

-- Scan `<site_path>/content/` and return a flat list of entries, each
-- enriched with title/draft read from frontmatter.
function M.scan_content(site_path)
  local content_dir = site_path .. "/content"
  if vim.fn.isdirectory(content_dir) == 0 then
    return {}
  end
  local entries = {}
  walk(content_dir, "", entries)
  for _, e in ipairs(entries) do
    e.title = frontmatter.read_title(e.file)
    e.draft = frontmatter.read_draft(e.file)
  end
  table.sort(entries, function(a, b)
    if a.section ~= b.section then return a.section < b.section end
    local ak = a.kind == "bundle" and a.bundle_rel or a.file_rel
    local bk = b.kind == "bundle" and b.bundle_rel or b.file_rel
    if ak ~= bk then return ak < bk end
    return (a.lang or "") < (b.lang or "")
  end)
  return entries
end

-- For bundles, return all language files in the bundle directory. For
-- single-file entries, return just that file. Useful for bundle-aware
-- operations (delete, draft toggle).
function M.language_siblings(entry)
  if entry.kind == "bundle" then
    local out = {}
    local sub = vim.loop.fs_scandir(entry.bundle_dir)
    if sub then
      while true do
        local n, t = vim.loop.fs_scandir_next(sub)
        if not n then break end
        if t == "file" then
          local stem_ext = n:match("^(.+)%.md$")
          if stem_ext then
            local stem, lang = split_language(stem_ext)
            if stem == "index" then
              out[#out + 1] = {
                file = entry.bundle_dir .. "/" .. n,
                lang = lang,
              }
            end
          end
        end
      end
    end
    return out
  end
  return { { file = entry.file, lang = entry.lang } }
end

-- Scan `<site_path>/archetypes/`. Returns list of { name, path, bundle }.
-- `default` is always listed (even if only `default.md` exists).
function M.scan_archetypes(site_path)
  local dir = site_path .. "/archetypes"
  if vim.fn.isdirectory(dir) == 0 then return {} end
  local out = {}
  local seen = {}
  local handle = vim.loop.fs_scandir(dir)
  if not handle then return out end
  while true do
    local name, ftype = vim.loop.fs_scandir_next(handle)
    if not name then break end
    local abs = dir .. "/" .. name
    if ftype == "directory" then
      local index = abs .. "/index.md"
      if vim.fn.filereadable(index) == 1 and not seen[name] then
        out[#out + 1] = { name = name, path = abs, bundle = true }
        seen[name] = true
      end
    elseif ftype == "file" then
      local base = name:match("^(.+)%.md$")
      if base and not seen[base] then
        out[#out + 1] = { name = base, path = abs, bundle = false }
        seen[base] = true
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

return M
