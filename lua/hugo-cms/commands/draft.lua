-- `:Hugo draft` — toggle the draft flag on the current content file.
--
-- Bundle-aware: when invoked inside a leaf bundle (`index(.lang)?.md`),
-- the flag is toggled across *all* language versions of that bundle so
-- the draft state stays consistent. For non-bundle content the flag is
-- toggled on the current file only.

local M = {}

local config = require("hugo-cms.config")
local content = require("hugo-cms.content")
local frontmatter = require("hugo-cms.frontmatter")

local function notify(msg, level)
  vim.notify("hugo-cms: " .. msg, level or vim.log.levels.INFO)
end

local function current_file_path()
  local name = vim.api.nvim_buf_get_name(0)
  if not name or name == "" then return nil end
  return vim.fs.normalize(name)
end

local function starts_with(s, prefix)
  return s:sub(1, #prefix) == prefix
end

local function is_index_file(basename)
  -- matches "index.md" or "index.<lang>.md"
  return basename:match("^index%.md$") ~= nil
    or basename:match("^index%.[%w%-]+%.md$") ~= nil
end

function M.run()
  local site = config.get_active()
  if not site then
    notify("no active site.", vim.log.levels.ERROR)
    return
  end

  local path = current_file_path()
  if not path then
    notify("no file in current buffer.", vim.log.levels.ERROR)
    return
  end

  local content_root = vim.fs.normalize(site.path .. "/content") .. "/"
  if not starts_with(path, content_root) then
    notify("current buffer is not inside the active site's content/ tree.", vim.log.levels.ERROR)
    return
  end

  local basename = vim.fs.basename(path)
  local dirname = vim.fs.dirname(path)

  local targets
  if is_index_file(basename) then
    -- Bundle: gather all `index(.lang)?.md` siblings.
    local fake_entry = {
      kind = "bundle",
      bundle_dir = dirname,
    }
    local siblings = content.language_siblings(fake_entry)
    targets = {}
    for _, s in ipairs(siblings) do
      targets[#targets + 1] = s.file
    end
  else
    targets = { path }
  end

  -- Use the first target's current state to decide the new value so all
  -- siblings end up consistent (even if they were out of sync before).
  local current = frontmatter.read_draft(targets[1]) or false
  local next_val = not current

  local changed = 0
  for _, file in ipairs(targets) do
    local existing = frontmatter.read_draft(file)
    if existing ~= next_val then
      local new_val, err = frontmatter.toggle_draft(file)
      if new_val == nil then
        notify("failed on " .. file .. ": " .. (err or "?"), vim.log.levels.ERROR)
        return
      end
      changed = changed + 1
    end
  end

  -- Reload current buffer so the user sees the change.
  vim.cmd("checktime")

  local suffix = #targets > 1
    and (" (" .. changed .. "/" .. #targets .. " language versions)")
    or ""
  notify("draft = " .. tostring(next_val) .. suffix)
end

return M
