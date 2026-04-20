-- `:Hugo rename` — rename/move content, bundle-aware.

local M = {}

local config = require("hugo-cms.config")
local content = require("hugo-cms.content")
local content_label = require("hugo-cms.content_label")
local picker = require("hugo-cms.picker")

local function notify(msg, level)
  vim.notify("hugo-cms: " .. msg, level or vim.log.levels.INFO)
end

local function ensure_parent_dir(path)
  local parent = vim.fn.fnamemodify(path, ":h")
  if parent ~= "" and vim.fn.isdirectory(parent) == 0 then
    vim.fn.mkdir(parent, "p")
  end
end

function M.run()
  local site = config.get_active()
  if not site then
    notify("no active site.", vim.log.levels.ERROR)
    return
  end

  local entries = content.scan_content(site.path)
  if #entries == 0 then
    notify("no content found.", vim.log.levels.WARN)
    return
  end

  local format_item = content_label.prepare(entries)

  picker.select(entries, {
    prompt = "Rename / move content",
    format_item = format_item,
  }, function(entry)
    if not entry then return end

    local current_rel, is_bundle, source
    if entry.kind == "bundle" then
      current_rel = entry.bundle_rel
      is_bundle = true
      source = entry.bundle_dir
    else
      current_rel = entry.file_rel
      is_bundle = false
      source = entry.file
    end

    vim.ui.input({
      prompt = "New path (relative to content/): ",
      default = current_rel,
    }, function(new_rel)
      if not new_rel or new_rel == "" or new_rel == current_rel then return end
      if not is_bundle and not new_rel:match("%.md$") then
        new_rel = new_rel .. ".md"
      end
      local target = site.path .. "/content/" .. new_rel
      if vim.loop.fs_stat(target) then
        notify("target already exists: " .. new_rel, vim.log.levels.ERROR)
        return
      end
      ensure_parent_dir(target)
      local ok, err = vim.loop.fs_rename(source, target)
      if not ok then
        notify("rename failed: " .. tostring(err), vim.log.levels.ERROR)
        return
      end
      notify("renamed " .. current_rel .. "  ->  " .. new_rel)
    end)
  end)
end

return M
