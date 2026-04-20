-- `:Hugo publish` — build the active site with `hugo` and, if the site
-- has a `deploy.sh`, run it. Both steps stream into a terminal split at
-- the bottom so the build and deploy can be followed live.
--
-- Guarded by a confirmation prompt that spells out the exact commands
-- that will run. The two steps are chained via `sh -c "hugo && sh
-- deploy.sh"`, so if `hugo` fails, `deploy.sh` is not executed.

local M = {}

local config = require("hugo-cms.config")

local function notify(msg, level)
  vim.notify("hugo-cms: " .. msg, level or vim.log.levels.INFO)
end

local function file_exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

function M.run()
  local site = config.get_active()
  if not site then
    notify("no active site.", vim.log.levels.ERROR)
    return
  end

  local has_deploy = file_exists(site.path .. "/deploy.sh")
  local deploy_line = has_deploy
    and "  -> sh deploy.sh"
    or "  -> (no deploy.sh — skipping)"

  local msg = string.format(
    "Publish site '%s'?\n\n  -> hugo (build into public/)\n%s\n\nCwd: %s",
    site.name, deploy_line, site.path
  )

  local answer = vim.fn.confirm(msg, "&Yes\n&No", 2)
  if answer ~= 1 then
    notify("publish cancelled")
    return
  end

  local shell_cmd = has_deploy and "hugo && sh deploy.sh" or "hugo"

  -- Fresh scratch buffer in a bottom split becomes the terminal target.
  vim.cmd("botright 8new")
  local term_buf = vim.api.nvim_get_current_buf()
  local term_win = vim.api.nvim_get_current_win()

  -- winbar doubles as visual separator (users running `laststatus=3`
  -- have no per-window statusline) and status indicator.
  local function set_winbar(status)
    if not vim.api.nvim_win_is_valid(term_win) then return end
    local text = " hugo publish — " .. site.name .. " — " .. status
    -- Escape `%` so statusline format doesn't try to interpret it.
    text = text:gsub("%%", "%%%%")
    vim.api.nvim_set_option_value("winbar", text, { win = term_win })
  end
  set_winbar("running")

  local job_id = vim.fn.jobstart({ "sh", "-c", shell_cmd }, {
    term = true,
    cwd = site.path,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          set_winbar("done")
          notify("publish succeeded (" .. site.name .. ")")
        else
          set_winbar("failed (exit " .. tostring(code) .. ")")
          notify("publish failed (exit " .. tostring(code) .. ")",
            vim.log.levels.ERROR)
        end
      end)
    end,
  })

  if job_id <= 0 then
    vim.cmd("bwipeout!")
    notify("failed to start publish", vim.log.levels.ERROR)
    return
  end

  pcall(vim.api.nvim_buf_set_name, term_buf,
    "hugo-publish://" .. site.name)

  -- Return focus to the previous window so editing isn't interrupted.
  vim.cmd("wincmd p")
end

return M
