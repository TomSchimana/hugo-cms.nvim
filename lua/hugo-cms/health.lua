-- `:checkhealth hugo-cms` — diagnose the plugin's environment.
--
-- Neovim discovers this automatically because the module path is
-- `hugo-cms.health` and exports `check()`.

local M = {}

local function has_executable(name)
  return vim.fn.executable(name) == 1
end

local function has_module(name)
  local ok = pcall(require, name)
  return ok
end

function M.check()
  local health = vim.health

  -- Neovim version --------------------------------------------------------
  health.start("hugo-cms: Neovim")
  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim " .. tostring(vim.version()) .. " meets the 0.10+ requirement")
  else
    health.error(
      "Neovim 0.10 or newer is required (current: "
        .. tostring(vim.version()) .. ")"
    )
  end

  -- Hard dependencies -----------------------------------------------------
  health.start("hugo-cms: hard dependencies")

  if has_module("snacks") then
    health.ok("snacks.nvim is loadable")
  else
    health.error(
      "snacks.nvim not found — install folke/snacks.nvim. "
        .. "Every picker and prompt in the plugin goes through snacks."
    )
  end

  if has_executable("hugo") then
    health.ok("`hugo` is in PATH")
  else
    health.error(
      "`hugo` not found in PATH. Install Hugo: https://gohugo.io/installation/"
    )
  end

  -- Optional dependencies -------------------------------------------------
  health.start("hugo-cms: optional dependencies")

  if has_executable("rg") then
    health.ok("`rg` (ripgrep) is in PATH")
  else
    health.warn(
      "`rg` (ripgrep) not found — `:Hugo search` and the "
        .. "broken-reference scan after `:Hugo media rename` / `delete` "
        .. "will not work. Install: `brew install ripgrep` or "
        .. "`apt install ripgrep`."
    )
  end

  local is_mac = vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1
  local is_linux = vim.fn.has("unix") == 1 and not is_mac
  if is_mac then
    if has_executable("open") then
      health.ok("`open` is available for browser and file-manager integration")
    else
      health.warn("`open` not found — `:Hugo preview` and `:Hugo filebrowser` may fail")
    end
  elseif is_linux then
    if has_executable("xdg-open") then
      health.ok("`xdg-open` is available for browser and file-manager integration")
    else
      health.warn(
        "`xdg-open` not found — `:Hugo preview` and `:Hugo filebrowser` "
          .. "may fail. Install `xdg-utils`."
      )
    end
  else
    health.warn(
      "Unrecognised platform. hugo-cms currently targets macOS and Linux; "
        .. "behaviour elsewhere is untested."
    )
  end

  if has_module("lazyvim") then
    health.ok("LazyVim is loadable — `:Hugo search` will work")
  else
    health.info(
      "LazyVim not detected. `:Hugo search` requires LazyVim "
        .. "(delegates to `LazyVim.pick.open(\"live_grep\", …)`). "
        .. "Every other command works without it."
    )
  end

  -- Plugin state ----------------------------------------------------------
  health.start("hugo-cms: plugin state")

  local ok_config, config = pcall(require, "hugo-cms.config")
  if not ok_config then
    health.error("failed to load hugo-cms.config: " .. tostring(config))
    return
  end

  local sites = config.list_sites and config.list_sites() or {}
  local count = #sites

  if count == 0 then
    health.info(
      "No sites registered yet. Run `:Hugo site register` to add one."
    )
  else
    health.ok(count .. " site(s) registered")
    local active = config.get_active and config.get_active() or nil
    if active then
      local stat = vim.loop.fs_stat(active.path)
      if stat and stat.type == "directory" then
        health.ok("active site: " .. active.name .. " (" .. active.path .. ")")
      else
        health.warn(
          "active site '" .. active.name .. "' points at "
            .. active.path .. " which is not a directory"
        )
      end
    else
      health.info("No active site. Pick one with `:Hugo site switch`.")
    end
  end
end

return M
