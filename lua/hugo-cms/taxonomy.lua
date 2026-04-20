-- Taxonomy picker: toggle list-valued frontmatter fields (tags, categories).
--
-- Collects all values used anywhere in the site, marks the ones already
-- set on the current buffer, lets the user toggle them via a looped
-- picker (works with snacks and with vim.ui.select alike). New values
-- can be created via a `+ Create new…` entry. On exit (Esc / close),
-- the final set is written to the frontmatter of every language
-- sibling so bundle variants stay in sync.

local M = {}

local config = require("hugo-cms.config")
local content = require("hugo-cms.content")
local frontmatter = require("hugo-cms.frontmatter")
local picker = require("hugo-cms.picker")

local function notify(msg, level)
  vim.notify("hugo-cms: " .. msg, level or vim.log.levels.INFO)
end

-- Collect the union of values for `field` across all content files in
-- the site. Returns a sorted list of unique non-empty strings.
local function collect(site, field)
  local entries = content.scan_content(site.path)
  local seen = {}
  local out = {}
  for _, e in ipairs(entries) do
    local list = frontmatter.read_list(e.file, field) or {}
    for _, v in ipairs(list) do
      if v ~= "" and not seen[v] then
        seen[v] = true
        out[#out + 1] = v
      end
    end
  end
  table.sort(out)
  return out
end

-- Find the content entry corresponding to the current buffer.
local function current_entry(site)
  local buf = vim.api.nvim_buf_get_name(0)
  if not buf or buf == "" then return nil end
  local path = vim.fs.normalize(buf)
  local entries = content.scan_content(site.path)
  for _, e in ipairs(entries) do
    if e.file == path then return e end
  end
  return nil
end

local function sorted_keys(set)
  local out = {}
  for k in pairs(set) do out[#out + 1] = k end
  table.sort(out)
  return out
end

-- Run the toggle-loop picker for `field`. `label` is shown in the picker
-- prompt (e.g. "Tags", "Categories").
function M.run(field, label)
  local site = config.get_active()
  if not site then
    notify("no active site.", vim.log.levels.ERROR)
    return
  end

  local entry = current_entry(site)
  if not entry then
    notify("current buffer is not a content file in the active site",
      vim.log.levels.ERROR)
    return
  end

  local all = collect(site, field)
  local current = {}
  for _, v in ipairs(frontmatter.read_list(entry.file, field) or {}) do
    current[v] = true
  end

  local dirty = false

  local function build_items()
    local in_current, rest = {}, {}
    local seen_in_all = {}
    for _, t in ipairs(all) do
      seen_in_all[t] = true
      if current[t] then
        in_current[#in_current + 1] = t
      else
        rest[#rest + 1] = t
      end
    end
    -- Newly created entries that aren't in `all` yet still belong on top.
    for _, t in ipairs(sorted_keys(current)) do
      if not seen_in_all[t] then
        in_current[#in_current + 1] = t
      end
    end
    table.sort(in_current)
    table.sort(rest)

    local items = {}
    for _, t in ipairs(in_current) do
      items[#items + 1] = { kind = "value", name = t, selected = true }
    end
    for _, t in ipairs(rest) do
      items[#items + 1] = { kind = "value", name = t, selected = false }
    end
    items[#items + 1] = { kind = "new" }
    return items
  end

  local function format_item(it)
    if it.kind == "new" then
      return "+ Create new " .. field:sub(1, -2) .. "…"
    end
    return (it.selected and "[x] " or "[ ] ") .. it.name
  end

  local function commit()
    if not dirty then return end
    local final = sorted_keys(current)
    local siblings = content.language_siblings(entry)
    for _, s in ipairs(siblings) do
      local ok, err = frontmatter.set_list(s.file, field, final)
      if not ok then
        notify("failed on " .. s.file .. ": " .. (err or "?"),
          vim.log.levels.ERROR)
        return
      end
    end
    vim.cmd("checktime")
    notify(field .. " updated (" .. #final .. " total, "
      .. #siblings .. " lang variants)")
  end

  local function loop()
    picker.select(build_items(), {
      prompt = label,
      format_item = format_item,
    }, function(choice)
      if not choice then
        commit()
        return
      end
      if choice.kind == "new" then
        -- Schedule so the picker fully closes before snacks.input opens;
        -- otherwise the input buffer starts in normal mode and typing
        -- `?` etc. triggers Vim's search instead of inserting text.
        vim.schedule(function()
          vim.ui.input({ prompt = "New " .. field:sub(1, -2) .. ": " },
            function(input)
              if input and input ~= "" and not current[input] then
                current[input] = true
                dirty = true
              end
              loop()
            end)
        end)
        return
      end
      if current[choice.name] then
        current[choice.name] = nil
      else
        current[choice.name] = true
      end
      dirty = true
      loop()
    end)
  end

  loop()
end

return M
