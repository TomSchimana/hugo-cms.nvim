-- `:Hugo site` subcommand.
--
-- Manages the plugin's site registry. The plugin does NOT create or
-- delete Hugo sites on disk — it only tracks which already-existing
-- sites Neovim knows about. Use `hugo new site <name>` in a shell to
-- scaffold a fresh site; come back here once a config file exists.
--
-- Top-level entry shows a picker with register / switch / unregister /
-- pattern actions. Direct sub-subcommands (`:Hugo site register`,
-- etc.) are also supported.

local M = {}

local config = require("hugo-cms.config")
local content = require("hugo-cms.content")
local picker = require("hugo-cms.picker")

local function notify(msg, level)
  vim.notify("hugo-cms: " .. msg, level or vim.log.levels.INFO)
end

local function expand_path(input)
  if not input or input == "" then return nil end
  return vim.fs.normalize(vim.fn.expand(input))
end

-- Hugo accepts several config layouts:
--   * root-level `hugo.{toml,yaml,yml,json}` (modern)
--   * root-level `config.{toml,yaml,yml,json}` (legacy)
--   * config directory: `config/_default/{hugo,config}.{toml,yaml,yml,json}`
local function is_hugo_root(path)
  local bases = { "hugo", "config" }
  local exts = { "toml", "yaml", "yml", "json" }

  for _, base in ipairs(bases) do
    for _, ext in ipairs(exts) do
      local f = path .. "/" .. base .. "." .. ext
      if vim.fn.filereadable(f) == 1 then
        return true, base .. "." .. ext
      end
    end
  end

  local default_dir = path .. "/config/_default"
  if vim.fn.isdirectory(default_dir) == 1 then
    for _, base in ipairs(bases) do
      for _, ext in ipairs(exts) do
        local f = default_dir .. "/" .. base .. "." .. ext
        if vim.fn.filereadable(f) == 1 then
          return true, "config/_default/" .. base .. "." .. ext
        end
      end
    end
  end

  return false
end

local function prompt_path(on_done)
  vim.ui.input({
    prompt = "Hugo site path: ",
    default = vim.fn.getcwd(),
    completion = "dir",
  }, function(input)
    if not input or input == "" then
      return
    end
    local path = expand_path(input)
    if vim.fn.isdirectory(path) == 0 then
      notify("path is not a directory: " .. path, vim.log.levels.ERROR)
      return
    end
    local ok, which = is_hugo_root(path)
    if not ok then
      notify("no Hugo config found in " .. path, vim.log.levels.ERROR)
      return
    end
    on_done(path, which)
  end)
end

local function prompt_name(default, on_done)
  vim.ui.input({
    prompt = "Site name: ",
    default = default,
  }, function(input)
    if not input or input == "" then
      return
    end
    on_done(input)
  end)
end

function M.register()
  prompt_path(function(path)
    local default_name = vim.fs.basename(path)
    prompt_name(default_name, function(name)
      local key = config.register_site(path, name)
      local active = config.get_active()
      local suffix = (active and active.key == key) and " (active)" or ""
      notify("registered site '" .. name .. "' [" .. key .. "]" .. suffix)
    end)
  end)
end

local function format_site(site)
  local marker = site.active and "* " or "  "
  return marker .. site.name .. "  —  " .. site.path
end

function M.switch()
  local sites = config.list_sites()
  if #sites == 0 then
    notify("no sites registered. Use :Hugo site register first.",
      vim.log.levels.WARN)
    return
  end
  picker.select(sites, {
    prompt = "Switch active site",
    format_item = format_site,
  }, function(choice)
    if not choice then return end
    if config.set_active(choice.key) then
      notify("active site: " .. choice.name)
    end
  end)
end

function M.unregister()
  local sites = config.list_sites()
  if #sites == 0 then
    notify("no sites registered.", vim.log.levels.WARN)
    return
  end
  picker.select(sites, {
    prompt = "Unregister site",
    format_item = format_site,
  }, function(choice)
    if not choice then return end
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Unregister '" .. choice.name
        .. "'? (site files on disk are not touched)",
    }, function(answer)
      if answer ~= "Yes" then return end
      if config.unregister_site(choice.key) then
        notify("unregistered site: " .. choice.name)
      end
    end)
  end)
end

function M.pattern()
  local site = config.get_active()
  if not site then
    notify("no active site.", vim.log.levels.ERROR)
    return
  end
  local archetypes = content.scan_archetypes(site.path)
  if #archetypes == 0 then
    notify("no archetypes in " .. site.path .. "/archetypes", vim.log.levels.ERROR)
    return
  end
  picker.select(archetypes, {
    prompt = "Archetype to edit pattern for",
    format_item = function(a)
      local current = config.get_archetype_pattern(site.key, a.name)
      local suffix = current and ("  [" .. current .. "]") or "  (no pattern)"
      return a.name .. suffix
    end,
  }, function(archetype)
    if not archetype then return end
    require("hugo-cms.commands.new").edit_pattern(site, archetype)
  end)
end

local actions = {
  register = M.register,
  switch = M.switch,
  unregister = M.unregister,
  pattern = M.pattern,
}

function M.complete(arglead)
  local names = {}
  for name in pairs(actions) do
    if name:find("^" .. vim.pesc(arglead)) then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

function M.run(args)
  local sub = args and args[1]
  if sub then
    local action = actions[sub]
    if not action then
      notify("unknown site subcommand: " .. sub, vim.log.levels.ERROR)
      return
    end
    action()
    return
  end

  local active = config.get_active()
  local header = active
    and ("Active: " .. active.name .. " (" .. active.path .. ")")
    or "No active site"

  local items = {
    { key = "register", label = "Register site" },
    { key = "switch", label = "Switch active site" },
    { key = "unregister", label = "Unregister site" },
    { key = "pattern", label = "Edit archetype pattern" },
  }
  picker.select(items, {
    prompt = header,
    format_item = function(item) return item.label end,
  }, function(choice)
    if not choice then return end
    actions[choice.key]()
  end)
end

return M
