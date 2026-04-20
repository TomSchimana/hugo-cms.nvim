-- `:Hugo delete` — bundle-aware content deletion.
--
-- For single-file entries the picker leads straight to a Yes/No confirm.
-- For bundle-language entries (`index.en.md` etc.) a second picker asks
-- whether to delete the whole bundle directory (all languages + page
-- resources) or only the selected language file.

local M = {}

local config = require("hugo-cms.config")
local content = require("hugo-cms.content")
local content_label = require("hugo-cms.content_label")
local picker = require("hugo-cms.picker")

local function notify(msg, level)
  vim.notify("hugo-cms: " .. msg, level or vim.log.levels.INFO)
end

local function rmdir_recursive(dir)
  local handle = vim.loop.fs_scandir(dir)
  if handle then
    while true do
      local name, ftype = vim.loop.fs_scandir_next(handle)
      if not name then break end
      local abs = dir .. "/" .. name
      if ftype == "directory" then
        rmdir_recursive(abs)
      else
        vim.loop.fs_unlink(abs)
      end
    end
  end
  vim.loop.fs_rmdir(dir)
end

local function confirm_and_delete(kind, target, description)
  vim.ui.select({ "Yes", "No" }, {
    prompt = "Delete " .. description .. "?",
  }, function(answer)
    if answer ~= "Yes" then return end
    if kind == "bundle" then
      rmdir_recursive(target)
    else
      vim.loop.fs_unlink(target)
    end
    if vim.loop.fs_stat(target) then
      notify("failed to delete " .. target, vim.log.levels.ERROR)
    else
      notify("deleted " .. description)
    end
  end)
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
    prompt = "Delete content",
    format_item = format_item,
  }, function(entry)
    if not entry then return end

    if entry.kind ~= "bundle" then
      confirm_and_delete("file", entry.file, "file '" .. entry.file_rel .. "'")
      return
    end

    local siblings = content.language_siblings(entry)
    local basename = vim.fs.basename(entry.file)

    local scopes = {
      {
        scope = "bundle",
        label = "Whole bundle  (" .. #siblings
          .. " lang file(s) + page resources in '"
          .. entry.bundle_rel .. "/')",
      },
      {
        scope = "file",
        label = "Only " .. basename
          .. "  (keep bundle, remove just this language)",
      },
    }

    picker.select(scopes, {
      prompt = "Delete scope",
      format_item = function(s) return s.label end,
    }, function(choice)
      if not choice then return end
      if choice.scope == "bundle" then
        confirm_and_delete("bundle", entry.bundle_dir,
          "bundle '" .. entry.bundle_rel .. "'")
      else
        confirm_and_delete("file", entry.file,
          basename .. " (in bundle '" .. entry.bundle_rel .. "')")
      end
    end)
  end)
end

return M
