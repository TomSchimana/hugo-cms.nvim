-- Thin wrapper around snacks.nvim's picker.select.
--
-- snacks.nvim is a hard requirement for this plugin — we don't keep a
-- `vim.ui.select` fallback because the fallback path would be untested
-- and give a worse UX than the snacks picker anyway.

local M = {}

-- Snacks' default "select" preset caps the popup at max_width = 100 and
-- height = 0.4 of the terminal, which feels cramped when entries carry a
-- path column + title (e.g. `:Hugo open`, `:Hugo media`). We override the
-- preset with wider defaults while keeping the preset's other layout
-- choices (border, list-height sizing, etc.).
local LAYOUT = {
  preset = "select",
  layout = {
    width = 0.8,
    max_width = 160,
    height = 0.6,
  },
}

-- Show a simple selection list. `items` is a list of tables, `opts.format_item`
-- turns each item into its display string. `callback` receives the picked item
-- (or nil on cancel).
function M.select(items, opts, callback)
  opts = opts or {}
  require("snacks").picker.select(items, {
    prompt = opts.prompt,
    format_item = opts.format_item or tostring,
    snacks = { layout = LAYOUT },
  }, function(choice)
    callback(choice)
  end)
end

return M
