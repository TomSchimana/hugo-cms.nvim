-- hugo-cms.nvim: manage Hugo-based sites from Neovim.
--
-- Public entry point. `setup()` is optional; the `:Hugo` user command is
-- registered unconditionally by `plugin/hugo-cms.lua` so the plugin works
-- even without an explicit setup call.

local M = {}

local function notify(msg, level)
  vim.notify("hugo-cms: " .. msg, level or vim.log.levels.INFO)
end

local subcommands = {
  site = {
    run = function(args) require("hugo-cms.commands.site").run(args) end,
    complete = function(arglead)
      return require("hugo-cms.commands.site").complete(arglead)
    end,
  },
  ["new"] = { run = function() require("hugo-cms.commands.new").run() end },
  open = { run = function() require("hugo-cms.commands.open").run() end },
  resume = { run = function() require("hugo-cms.commands.resume").run() end },
  search = { run = function() require("hugo-cms.commands.search").run() end },
  rename = { run = function() require("hugo-cms.commands.rename").run() end },
  delete = { run = function() require("hugo-cms.commands.delete").run() end },
  draft = { run = function() require("hugo-cms.commands.draft").run() end },
  tags = { run = function() require("hugo-cms.commands.tags").run() end },
  categories = {
    run = function() require("hugo-cms.commands.categories").run() end,
  },
  media = {
    run = function(args) require("hugo-cms.commands.media").run(args) end,
    complete = function(arglead)
      return require("hugo-cms.commands.media").complete(arglead)
    end,
  },
  filebrowser = {
    run = function() require("hugo-cms.commands.filebrowser").run() end,
  },
  preview = {
    run = function(args) require("hugo-cms.commands.preview").run(args) end,
    complete = function(arglead)
      return require("hugo-cms.commands.preview").complete(arglead)
    end,
  },
  publish = { run = function() require("hugo-cms.commands.publish").run() end },
}

local function subcommand_names()
  local names = {}
  for name in pairs(subcommands) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

local function dispatch(args)
  if #args == 0 then
    notify("subcommand required (try <Tab> for completion)", vim.log.levels.WARN)
    return
  end
  local sub = args[1]
  local entry = subcommands[sub]
  if not entry then
    notify("unknown subcommand: " .. sub, vim.log.levels.ERROR)
    return
  end
  local rest = {}
  for i = 2, #args do rest[#rest + 1] = args[i] end
  entry.run(rest)
end

local function complete(arglead, cmdline)
  local parts = vim.split(cmdline, "%s+", { trimempty = true })
  -- When cmdline ends with a space, arglead is empty and we're starting a new
  -- token. #parts then counts the tokens already typed (including "Hugo").
  local typing_new = cmdline:sub(-1) == " "
  local position = typing_new and (#parts + 1) or #parts

  if position <= 2 then
    local out = {}
    for _, name in ipairs(subcommand_names()) do
      if name:find("^" .. vim.pesc(arglead)) then
        out[#out + 1] = name
      end
    end
    return out
  end

  local sub = parts[2]
  local entry = subcommands[sub]
  if entry and entry.complete then
    local rest = {}
    for i = 3, #parts do rest[#rest + 1] = parts[i] end
    return entry.complete(arglead, rest) or {}
  end
  return {}
end

-- Track the last content file the user visited per site. Fired on
-- BufEnter; only writes to disk when the path actually changed so
-- buffer-switching hot paths aren't a concern.
local function setup_resume_tracking()
  local group = vim.api.nvim_create_augroup("HugoCmsResume", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      local config = require("hugo-cms.config")
      local site = config.get_active()
      if not site then return end
      local name = vim.api.nvim_buf_get_name(ev.buf)
      if not name or name == "" then return end
      if not name:match("%.md$") then return end
      local path = vim.fs.normalize(name)
      local content_root = vim.fs.normalize(site.path .. "/content") .. "/"
      if path:sub(1, #content_root) ~= content_root then return end
      config.set_last_content(site.key, path)
    end,
  })
end

local registered = false

function M.register_commands()
  if registered then return end
  registered = true
  vim.api.nvim_create_user_command("Hugo", function(opts)
    dispatch(opts.fargs)
  end, {
    nargs = "*",
    complete = complete,
    desc = "Hugo CMS commands",
  })
  setup_resume_tracking()
end

function M.setup(opts)
  opts = opts or {}
  if not pcall(require, "snacks") then
    notify("folke/snacks.nvim is required but not installed",
      vim.log.levels.ERROR)
    return
  end
  require("hugo-cms.config").setup()
  M.register_commands()
end

return M
