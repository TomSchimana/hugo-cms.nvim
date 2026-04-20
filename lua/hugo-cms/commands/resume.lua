-- `:Hugo resume` — reopen the last content page edited for the active
-- site. The path is tracked by an autocmd in `init.lua` whenever the
-- user enters a buffer inside `<site>/content/**`, and persisted in the
-- site registry so it survives Neovim restarts.

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

  local path = config.get_last_content(site.key)
  if not path or path == "" then
    notify("no previous content page for '" .. site.name
      .. "' — open one first", vim.log.levels.WARN)
    return
  end

  if vim.fn.filereadable(path) == 0 then
    notify("last content page no longer exists: " .. path,
      vim.log.levels.WARN)
    return
  end

  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

return M
