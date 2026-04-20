-- `:Hugo new` — create content from an archetype.
--
-- Pattern model (Modell A): exactly one path pattern per archetype per
-- site, stored as a *prefix* (no `{slug}` placeholder). The prefix is
-- expanded with date placeholders and used to prefill the path input;
-- the user types the slug at the end. Editing the pattern itself
-- happens via `:Hugo site` → "Edit archetype pattern".

local M = {}

local config = require("hugo-cms.config")
local content = require("hugo-cms.content")
local frontmatter = require("hugo-cms.frontmatter")
local hugo = require("hugo-cms.hugo")
local picker = require("hugo-cms.picker")
local slug_mod = require("hugo-cms.slug")

local function notify(msg, level)
  vim.notify("hugo-cms: " .. msg, level or vim.log.levels.INFO)
end

local function require_active_site()
  local site = config.get_active()
  if not site then
    notify("no active site. Use :Hugo site register first.",
      vim.log.levels.ERROR)
    return nil
  end
  return site
end

local function default_prefix(archetype_name)
  if archetype_name == "default" then return "" end
  return "posts/{year}/"
end

local function expand_prefix(prefix)
  local now = os.date("*t")
  local out = prefix
  out = out:gsub("{year}", string.format("%04d", now.year))
  out = out:gsub("{month}", string.format("%02d", now.month))
  out = out:gsub("{day}", string.format("%02d", now.day))
  return out
end

local function ensure_md_suffix(path, is_bundle)
  if is_bundle then return path end
  if path:match("%.md$") then return path end
  return path .. ".md"
end

local function created_file_path(site_path, path_arg, is_bundle)
  local file = site_path .. "/content/" .. path_arg
  if is_bundle then file = file .. "/index.md" end
  return file
end

-- Collect all `index(.lang)?.md` files Hugo materialised from a bundle
-- archetype (one per language variant present in the archetype).
local function bundle_index_files(bundle_dir)
  local out = {}
  local handle = vim.loop.fs_scandir(bundle_dir)
  if not handle then return out end
  while true do
    local name, ftype = vim.loop.fs_scandir_next(handle)
    if not name then break end
    if ftype == "file"
      and (name == "index.md" or name:match("^index%.[%w%-]+%.md$")) then
      out[#out + 1] = bundle_dir .. "/" .. name
    end
  end
  return out
end

local function call_hugo_new(site, archetype, rel_path, title)
  local path_arg = ensure_md_suffix(rel_path, archetype.bundle)
  local kind = archetype.name ~= "default" and archetype.name or nil
  local result = hugo.new(site.path, path_arg, kind)
  if not result.ok then
    notify(
      "hugo new failed (exit " .. tostring(result.code) .. "): "
        .. (result.stderr ~= "" and result.stderr or result.stdout),
      vim.log.levels.ERROR
    )
    return
  end

  local file = created_file_path(site.path, path_arg, archetype.bundle)

  if title and title ~= "" then
    local targets = archetype.bundle
      and bundle_index_files(site.path .. "/content/" .. path_arg)
      or { file }
    for _, target in ipairs(targets) do
      if vim.fn.filereadable(target) == 1 then
        local ok, err = frontmatter.set_title(target, title)
        if not ok then
          notify("title not set on " .. target .. ": " .. (err or "?"),
            vim.log.levels.WARN)
        end
      end
    end
  end

  if vim.fn.filereadable(file) == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(file))
  else
    notify("file was created but not found at " .. file, vim.log.levels.WARN)
  end
  notify("created " .. rel_path)
end

-- Prompt for a new pattern for this archetype, persist on confirm.
-- Called from `:Hugo new` (first use) and from `:Hugo site` (edit).
function M.edit_pattern(site, archetype, on_done)
  local current = config.get_archetype_pattern(site.key, archetype.name)
  local prefill = current or default_prefix(archetype.name)
  vim.ui.input({
    prompt = "Path pattern for '" .. archetype.name
      .. "' (prefix, placeholders {year} {month} {day}, end with /): ",
    default = prefill,
  }, function(input)
    if not input or input == "" then return end
    config.set_archetype_pattern(site.key, archetype.name, input)
    notify("pattern saved: " .. input)
    if on_done then on_done(input) end
  end)
end

-- Two-step flow: title first, then path prefilled with the slug derived
-- from that title. Empty title is allowed (no frontmatter override).
local function prompt_title_and_path(prefix, on_done)
  vim.ui.input({ prompt = "Title: " }, function(title)
    if title == nil then return end
    local derived_slug = title ~= "" and slug_mod.slugify(title) or ""
    vim.ui.input({
      prompt = "Path (append/edit slug): ",
      default = expand_prefix(prefix) .. derived_slug,
    }, function(rel_path)
      if not rel_path or rel_path == "" then return end
      on_done(rel_path, title)
    end)
  end)
end

function M.run()
  local site = require_active_site()
  if not site then return end

  local archetypes = content.scan_archetypes(site.path)
  if #archetypes == 0 then
    notify("no archetypes found in " .. site.path .. "/archetypes", vim.log.levels.ERROR)
    return
  end

  picker.select(archetypes, {
    prompt = "Archetype",
    format_item = function(a)
      return a.name .. (a.bundle and "  (bundle)" or "")
    end,
  }, function(archetype)
    if not archetype then return end

    local prefix = config.get_archetype_pattern(site.key, archetype.name)
    if prefix then
      prompt_title_and_path(prefix, function(rel_path, title)
        call_hugo_new(site, archetype, rel_path, title)
      end)
    else
      -- First use: set pattern, then title + path.
      M.edit_pattern(site, archetype, function(new_prefix)
        prompt_title_and_path(new_prefix, function(rel_path, title)
          call_hugo_new(site, archetype, rel_path, title)
        end)
      end)
    end
  end)
end

return M
