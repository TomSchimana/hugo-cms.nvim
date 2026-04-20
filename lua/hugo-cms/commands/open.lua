-- `:Hugo open` — picker over the active site's content.

local M = {}

local config = require("hugo-cms.config")
local content = require("hugo-cms.content")
local content_label = require("hugo-cms.content_label")
local picker = require("hugo-cms.picker")

local function notify(msg, level)
  vim.notify("hugo-cms: " .. msg, level or vim.log.levels.INFO)
end

function M.run()
  local site = config.get_active()
  if not site then
    notify("no active site. Use :Hugo site register first.",
      vim.log.levels.ERROR)
    return
  end

  local entries = content.scan_content(site.path)
  if #entries == 0 then
    notify("no content found under " .. site.path .. "/content", vim.log.levels.WARN)
    return
  end

  local format_item = content_label.prepare(entries)

  picker.select(entries, {
    prompt = site.name .. " — content",
    format_item = format_item,
  }, function(entry)
    if not entry then return end
    vim.cmd("edit " .. vim.fn.fnameescape(entry.file))
  end)
end

return M
