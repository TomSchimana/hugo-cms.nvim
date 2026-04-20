-- Site registry with JSON persistence.
--
-- Stores the list of registered Hugo sites and which one is active.
-- Persisted to `$XDG_DATA_HOME/nvim/hugo-cms/sites.json` (via stdpath("data")).

local M = {}

local data_dir = vim.fn.stdpath("data") .. "/hugo-cms"
local config_file = data_dir .. "/sites.json"

local state = {
  active = nil,
  sites = {},
}

local loaded = false

local function ensure_dir()
  if vim.fn.isdirectory(data_dir) == 0 then
    vim.fn.mkdir(data_dir, "p")
  end
end

local function load()
  if vim.fn.filereadable(config_file) == 0 then
    return
  end
  local lines = vim.fn.readfile(config_file)
  if #lines == 0 then
    return
  end
  local content = table.concat(lines, "\n")
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    vim.notify("hugo-cms: failed to parse " .. config_file, vim.log.levels.ERROR)
    return
  end
  state.active = decoded.active
  state.sites = decoded.sites or {}
end

local function save()
  ensure_dir()
  local encoded = vim.json.encode({ active = state.active, sites = state.sites })
  vim.fn.writefile({ encoded }, config_file)
end

local function ensure_loaded()
  if not loaded then
    load()
    loaded = true
  end
end

function M.setup()
  ensure_loaded()
end

function M.reload()
  loaded = false
  ensure_loaded()
end

function M.list_sites()
  ensure_loaded()
  local list = {}
  for key, site in pairs(state.sites) do
    list[#list + 1] = {
      key = key,
      name = site.name,
      path = site.path,
      active = state.active == key,
    }
  end
  table.sort(list, function(a, b) return a.key < b.key end)
  return list
end

function M.get_active()
  ensure_loaded()
  if not state.active then
    return nil
  end
  local site = state.sites[state.active]
  if not site then
    return nil
  end
  return {
    key = state.active,
    name = site.name,
    path = site.path,
  }
end

function M.has_site(key)
  ensure_loaded()
  return state.sites[key] ~= nil
end

local function slugify(name)
  local slug = name:lower()
  slug = slug:gsub("[^%w]+", "-")
  slug = slug:gsub("^%-+", ""):gsub("%-+$", "")
  if slug == "" then slug = "site" end
  return slug
end

local function unique_key(base)
  ensure_loaded()
  if not state.sites[base] then
    return base
  end
  local i = 2
  while state.sites[base .. "-" .. i] do
    i = i + 1
  end
  return base .. "-" .. i
end

-- Register an existing Hugo site with the plugin. This stores an entry
-- in the registry; it does NOT create anything on disk (use
-- `hugo new site` in a shell for that).
function M.register_site(path, name)
  ensure_loaded()
  local key = unique_key(slugify(name))
  state.sites[key] = { name = name, path = path, archetypes = {} }
  if not state.active then
    state.active = key
  end
  save()
  return key
end

-- Drop a site from the registry. Files on disk are untouched.
function M.unregister_site(key)
  ensure_loaded()
  if not state.sites[key] then
    return false
  end
  state.sites[key] = nil
  if state.active == key then
    state.active = next(state.sites)
  end
  save()
  return true
end

function M.set_active(key)
  ensure_loaded()
  if not state.sites[key] then
    return false
  end
  state.active = key
  save()
  return true
end

-- Archetype-pattern accessors. Patterns are stored per site under
-- `sites[key].archetypes[archetype_name] = "<pattern>"`.

function M.get_archetype_pattern(site_key, archetype_name)
  ensure_loaded()
  local site = state.sites[site_key]
  if not site or not site.archetypes then return nil end
  return site.archetypes[archetype_name]
end

function M.set_archetype_pattern(site_key, archetype_name, pattern)
  ensure_loaded()
  local site = state.sites[site_key]
  if not site then return false end
  site.archetypes = site.archetypes or {}
  if pattern == nil or pattern == "" then
    site.archetypes[archetype_name] = nil
  else
    site.archetypes[archetype_name] = pattern
  end
  save()
  return true
end

-- Last-opened content file per site. Used by `:Hugo resume` so the user
-- can jump back to where they left off across Neovim sessions. Stored as
-- an absolute path under `sites[key].last_content`.

function M.get_last_content(site_key)
  ensure_loaded()
  local site = state.sites[site_key]
  if not site then return nil end
  return site.last_content
end

function M.set_last_content(site_key, path)
  ensure_loaded()
  local site = state.sites[site_key]
  if not site then return false end
  if site.last_content == path then return true end
  site.last_content = path
  save()
  return true
end

function M.config_file_path()
  return config_file
end

return M
