-- `:Hugo search` — live full-text search over the active site's content/.
--
-- Delegates to `LazyVim.pick.open("live_grep", ...)`, which routes to
-- whichever picker LazyVim is configured with (snacks / telescope /
-- fzf-lua). Requires ripgrep on PATH — same requirement as LazyVim's
-- own `<leader>sg`.

local M = {}

local config = require("hugo-cms.config")

local function notify(msg, level)
  vim.notify("hugo-cms: " .. msg, level or vim.log.levels.INFO)
end

function M.run()
  local site = config.get_active()
  if not site then
    notify("no active site.", vim.log.levels.ERROR)
    return
  end

  local content_dir = site.path .. "/content"
  if vim.fn.isdirectory(content_dir) == 0 then
    notify("no content/ directory at " .. content_dir, vim.log.levels.WARN)
    return
  end

  if not _G.LazyVim or not LazyVim.pick then
    notify("LazyVim.pick not available (requires LazyVim)", vim.log.levels.ERROR)
    return
  end

  LazyVim.pick.open("live_grep", { cwd = content_dir })
end

return M
