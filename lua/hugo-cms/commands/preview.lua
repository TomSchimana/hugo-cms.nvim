-- `:Hugo preview` — run `hugo server` in a terminal split and open the
-- page corresponding to the current buffer in the system browser.
--
-- The split at the bottom of the screen is both the status indicator
-- (you can see builds, requests, and errors live) and the kill switch
-- (closing the terminal buffer stops the server).
--
-- Calling `:Hugo preview` while a preview is already running does NOT
-- stop it — it opens the current buffer's page in the browser again.
-- Use `:Hugo preview stop` to shut the server down explicitly. The
-- server is also killed on Neovim exit so no orphan processes survive.

local M = {}

local config = require("hugo-cms.config")

local function notify(msg, level)
  vim.notify("hugo-cms: " .. msg, level or vim.log.levels.INFO)
end

-- Module-level state: at most one Hugo server running at a time.
local state = {
  job_id = nil,
  site_name = nil,
  term_buf = nil,
}

local function is_running()
  return state.job_id ~= nil
end

-- Split a path (relative to `content/`) into (dir, stem, lang).
-- `dir` is "" at content root, otherwise forward-slash joined.
-- `lang` is nil when no language suffix is present.
local function split_content_path(rel)
  local dir = vim.fs.dirname(rel)
  if dir == "." then dir = "" end
  local base = vim.fs.basename(rel):match("^(.+)%.md$")
  if not base then return nil end
  local stem, lang = base:match("^(.+)%.([%w][%w%-]*)$")
  if not stem or not lang or #lang > 5 then
    stem, lang = base, nil
  end
  return dir, stem, lang
end

-- Compute the preview URL for the current buffer under the given site.
-- Falls back to the site root when the buffer isn't a content file.
-- Does not account for unusual permalink configs or
-- `defaultContentLanguageInSubdir`.
local function preview_url(site)
  local base = "http://localhost:1313"
  local buf = vim.api.nvim_buf_get_name(0)
  if not buf or buf == "" then return base .. "/" end
  local path = vim.fs.normalize(buf)
  local content_root = vim.fs.normalize(site.path .. "/content") .. "/"
  if path:sub(1, #content_root) ~= content_root then
    return base .. "/"
  end
  local rel = path:sub(#content_root + 1)
  local dir, stem, lang = split_content_path(rel)
  if not dir then return base .. "/" end

  local url_path
  if stem == "index" or stem == "_index" then
    url_path = dir == "" and "" or (dir .. "/")
  else
    url_path = (dir == "" and stem or (dir .. "/" .. stem)) .. "/"
  end

  local prefix = lang and ("/" .. lang) or ""
  return base .. prefix .. "/" .. url_path
end

local function open_browser(url)
  local argv
  if vim.fn.has("mac") == 1 then
    argv = { "open", url }
  elseif vim.fn.has("unix") == 1 then
    argv = { "xdg-open", url }
  else
    notify("no browser opener for this platform", vim.log.levels.WARN)
    return
  end
  vim.system(argv, { detach = true })
end

-- Forward declaration so the BufWipeout autocmd can call stop().
local stop

-- Escape `%` so a string is rendered literally by winbar/statusline.
local function escape_winbar(s)
  return (s:gsub("%%", "%%%%"))
end

local function start(site)
  -- Fresh scratch buffer in a bottom split; `jobstart({ term = true })`
  -- attaches the hugo process to it as a pty terminal.
  vim.cmd("botright 8new")
  local term_buf = vim.api.nvim_get_current_buf()
  local term_win = vim.api.nvim_get_current_win()

  -- winbar doubles as visual separator (users running `laststatus=3`
  -- have no per-window statusline) and quick status indicator.
  vim.api.nvim_set_option_value(
    "winbar",
    escape_winbar(" hugo server — " .. site.name
      .. " — http://localhost:1313"),
    { win = term_win }
  )

  local job_id = vim.fn.jobstart({
    "hugo", "server",
    "--buildDrafts", "--buildFuture",
    "--navigateToChanged",
  }, {
    term = true,
    cwd = site.path,
    on_exit = function(_, code)
      vim.schedule(function()
        -- If job_id is already nil, stop() initiated the exit; don't
        -- raise a false alarm.
        local intentional = state.job_id == nil
        state.job_id = nil
        state.site_name = nil
        state.term_buf = nil
        if not intentional and code ~= 0 then
          notify("hugo server exited (code " .. tostring(code) .. ")",
            vim.log.levels.ERROR)
        end
      end)
    end,
  })

  if job_id <= 0 then
    vim.cmd("bwipeout!")
    notify("failed to start hugo server", vim.log.levels.ERROR)
    return
  end

  state.job_id = job_id
  state.site_name = site.name
  state.term_buf = term_buf

  -- Wiping the terminal buffer (e.g. `:bd`) tears the server down too.
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = term_buf,
    once = true,
    callback = function()
      if state.job_id then stop(true) end
    end,
  })

  -- Return focus to the previous window so editing isn't interrupted.
  vim.cmd("wincmd p")

  local url = preview_url(site)
  -- Give Hugo a brief head-start before the browser connects.
  vim.defer_fn(function() open_browser(url) end, 700)
  notify("preview started → " .. url)
end

stop = function(silent)
  local job_id = state.job_id
  local name = state.site_name
  local term_buf = state.term_buf
  state.job_id = nil
  state.site_name = nil
  state.term_buf = nil

  if job_id then
    pcall(vim.fn.jobstop, job_id)
  end
  if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
    pcall(vim.api.nvim_buf_delete, term_buf, { force = true })
  end
  if not silent and job_id then
    notify("preview stopped (" .. (name or "?") .. ")")
  end
end

function M.run(args)
  args = args or {}
  local sub = args[1]

  if sub == "stop" then
    if is_running() then
      stop()
    else
      notify("preview is not running")
    end
    return
  end

  if sub and sub ~= "" then
    notify("unknown preview subcommand: " .. sub, vim.log.levels.ERROR)
    return
  end

  local site = config.get_active()
  if not site then
    notify("no active site.", vim.log.levels.ERROR)
    return
  end

  if is_running() then
    if state.site_name ~= site.name then
      notify("preview is running for '" .. tostring(state.site_name)
        .. "' — stop it first or switch back to that site",
        vim.log.levels.WARN)
      return
    end
    local url = preview_url(site)
    open_browser(url)
    notify("→ " .. url)
    return
  end

  start(site)
end

function M.complete(arglead)
  local subs = { "stop" }
  local out = {}
  for _, s in ipairs(subs) do
    if s:find("^" .. vim.pesc(arglead)) then
      out[#out + 1] = s
    end
  end
  return out
end

-- Kill the child on Neovim exit so the hugo server doesn't survive us.
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("HugoCmsPreview", { clear = true }),
  callback = function() stop(true) end,
})

return M
