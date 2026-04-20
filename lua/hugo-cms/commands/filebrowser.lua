-- `:Hugo filebrowser` — open the system file manager at the current
-- content location, or at the site root when the current buffer is not
-- part of the active site.

local M = {}

local config = require("hugo-cms.config")

local function notify(msg, level)
  vim.notify("hugo-cms: " .. msg, level or vim.log.levels.INFO)
end

local function starts_with(s, prefix)
  return s:sub(1, #prefix) == prefix
end

-- Pick the directory to reveal. Prefers the active buffer's directory
-- when it lives inside the active site; falls back to the site root.
local function target_dir(site)
  local name = vim.api.nvim_buf_get_name(0)
  if name and name ~= "" then
    local path = vim.fs.normalize(name)
    local root = vim.fs.normalize(site.path) .. "/"
    if starts_with(path, root) then
      return vim.fs.dirname(path)
    end
  end
  return vim.fs.normalize(site.path)
end

-- Return the OS-appropriate argv to open a directory in the system file
-- manager, or nil + error when unsupported.
local function open_argv(dir)
  if vim.fn.has("mac") == 1 then
    return { "open", dir }
  end
  if vim.fn.has("unix") == 1 then
    return { "xdg-open", dir }
  end
  return nil, "unsupported platform (only macOS and Linux)"
end

function M.run()
  local site = config.get_active()
  if not site then
    notify("no active site.", vim.log.levels.ERROR)
    return
  end

  local dir = target_dir(site)
  local argv, err = open_argv(dir)
  if not argv then
    notify(err, vim.log.levels.ERROR)
    return
  end

  vim.system(argv, { detach = true })
  notify("opened " .. dir)
end

return M
