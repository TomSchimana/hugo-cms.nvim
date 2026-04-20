-- Minimal frontmatter reader/writer.
--
-- Supports the three delimiter styles Hugo accepts: YAML (`---`), TOML
-- (`+++`), and JSON (leading `{` … `}`). We do NOT do a full YAML/TOML
-- parse; we only locate the frontmatter block and provide targeted
-- read/toggle operations on scalar fields (currently `draft`). That is
-- enough for the current phase and avoids pulling in a YAML library.
--
-- Buffer-first I/O: when a target file is loaded as a Neovim buffer,
-- edits go straight into the buffer (via `nvim_buf_set_lines`) instead
-- of being written to disk. This means:
--   * the user sees the change live,
--   * the buffer becomes modified and the user decides when to save,
--   * there is no W12 conflict with unsaved in-buffer changes.
-- Only files that are not loaded as buffers are written to disk.

local M = {}

local DELIMITERS = {
  yaml = { open = "---", close = "---" },
  toml = { open = "+++", close = "+++" },
}

-- Parse a file into { kind, open_idx, close_idx, lines } where kind is
-- "yaml" | "toml" | "json" | nil.
-- Returns nil if the file has no recognisable frontmatter.
local function locate(lines)
  if #lines == 0 then return nil end
  local first = lines[1]

  if first == "---" then
    for i = 2, #lines do
      if lines[i] == "---" then
        return { kind = "yaml", open_idx = 1, close_idx = i, lines = lines }
      end
    end
    return nil
  end

  if first == "+++" then
    for i = 2, #lines do
      if lines[i] == "+++" then
        return { kind = "toml", open_idx = 1, close_idx = i, lines = lines }
      end
    end
    return nil
  end

  if first:match("^%s*{") then
    local depth = 0
    for i = 1, #lines do
      for c in lines[i]:gmatch("[{}]") do
        if c == "{" then depth = depth + 1 else depth = depth - 1 end
      end
      if depth == 0 and i > 1 then
        return { kind = "json", open_idx = 1, close_idx = i, lines = lines }
      end
    end
  end

  return nil
end

-- Look for a loaded buffer whose file name resolves to `path`. Returns
-- the bufnr or nil. Uses normalised paths so tilde/symlink expansion
-- matches across the two sides.
local function find_loaded_buffer(path)
  local target = vim.fs.normalize(path)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" and vim.fs.normalize(name) == target then
        return bufnr
      end
    end
  end
  return nil
end

-- Read lines from a loaded buffer if present, else from disk.
-- Returns (lines, bufnr_or_nil). The second return value is passed back
-- to `write_lines` so the same target is written back.
local function read_lines(path)
  local bufnr = find_loaded_buffer(path)
  if bufnr then
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), bufnr
  end
  if vim.fn.filereadable(path) == 0 then return nil end
  return vim.fn.readfile(path), nil
end

-- Write lines back: to the buffer (making it modified, not saving), or
-- to disk. Callers must thread the `bufnr` received from `read_lines`.
local function write_lines(path, lines, bufnr)
  if bufnr and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return
  end
  vim.fn.writefile(lines, path)
end

-- Find the index of a scalar field line inside the frontmatter block.
-- Returns index, value_string, style ("yaml" | "toml" | nil).
local function find_scalar(block, field)
  if block.kind == "yaml" then
    for i = block.open_idx + 1, block.close_idx - 1 do
      local key, value = block.lines[i]:match("^(%S+)%s*:%s*(.*)$")
      if key == field then
        return i, value, "yaml"
      end
    end
  elseif block.kind == "toml" then
    for i = block.open_idx + 1, block.close_idx - 1 do
      local key, value = block.lines[i]:match("^(%S+)%s*=%s*(.*)$")
      if key == field then
        return i, value, "toml"
      end
    end
  elseif block.kind == "json" then
    local pattern = '"' .. field .. '"%s*:%s*([%w_%.]+)'
    for i = block.open_idx, block.close_idx do
      local value = block.lines[i]:match(pattern)
      if value then
        return i, value, "json"
      end
    end
  end
  return nil
end

local function strip_quotes(s)
  s = s:match("^%s*(.-)%s*$")
  return s:match('^"(.*)"$') or s:match("^'(.*)'$") or s
end

local function to_bool(value)
  if not value then return nil end
  value = value:gsub("[,%s]+$", "")
  if value == "true" then return true end
  if value == "false" then return false end
  return nil
end

-- Read the draft flag from a content file. Returns boolean or nil if the
-- file has no frontmatter / no draft field.
function M.read_draft(path)
  local lines = read_lines(path)
  if not lines then return nil end
  local block = locate(lines)
  if not block then return nil end
  local _, value = find_scalar(block, "draft")
  return to_bool(value)
end

-- Toggle the draft flag. Creates the field if absent. Returns the new
-- boolean value on success, nil on failure.
function M.toggle_draft(path)
  local lines, bufnr = read_lines(path)
  if not lines then return nil, "file not readable: " .. path end
  local block = locate(lines)
  if not block then return nil, "no frontmatter found in " .. path end

  local idx, value, style = find_scalar(block, "draft")
  local current = to_bool(value) or false
  local next_val = not current

  if idx then
    if style == "yaml" then
      lines[idx] = "draft: " .. tostring(next_val)
    elseif style == "toml" then
      lines[idx] = "draft = " .. tostring(next_val)
    elseif style == "json" then
      lines[idx] = lines[idx]:gsub(
        '("draft"%s*:%s*)[%w_%.]+',
        '%1' .. tostring(next_val)
      )
    end
  else
    -- Insert before closing delimiter.
    local new_line
    if block.kind == "yaml" then
      new_line = "draft: " .. tostring(next_val)
    elseif block.kind == "toml" then
      new_line = "draft = " .. tostring(next_val)
    else
      return nil, "cannot insert draft field into JSON frontmatter automatically"
    end
    table.insert(lines, block.close_idx, new_line)
  end

  write_lines(path, lines, bufnr)
  return next_val
end

-- Set the `title` field. Creates the field if absent. Returns true on
-- success, (nil, error) on failure. JSON frontmatter is not supported.
function M.set_title(path, title)
  local lines, bufnr = read_lines(path)
  if not lines then return nil, "file not readable: " .. path end
  local block = locate(lines)
  if not block then return nil, "no frontmatter found in " .. path end

  local escaped = title:gsub("\\", "\\\\"):gsub('"', '\\"')
  local new_line
  if block.kind == "yaml" then
    new_line = 'title: "' .. escaped .. '"'
  elseif block.kind == "toml" then
    new_line = 'title = "' .. escaped .. '"'
  else
    return nil, "JSON frontmatter not supported for title updates"
  end

  local idx = find_scalar(block, "title")
  if idx then
    lines[idx] = new_line
  else
    table.insert(lines, block.close_idx, new_line)
  end
  write_lines(path, lines, bufnr)
  return true
end

-- Locate the `cover` block's child field indices. Returns
-- (cover_idx, image_idx, alt_idx, indent) for YAML, or (section_idx,
-- image_idx, alt_idx) for TOML. Indent is the whitespace used by
-- existing children in YAML so new children match the style.
local function find_cover_yaml(block, lines)
  local cover_idx
  for i = block.open_idx + 1, block.close_idx - 1 do
    if lines[i]:match("^cover%s*:") then
      cover_idx = i
      break
    end
  end
  if not cover_idx then return nil end
  local image_idx, alt_idx, indent
  for i = cover_idx + 1, block.close_idx - 1 do
    if lines[i]:match("^%s") then
      indent = indent or lines[i]:match("^(%s+)")
      if lines[i]:match("^%s+image%s*:") then image_idx = i end
      if lines[i]:match("^%s+alt%s*:")   then alt_idx   = i end
    else
      break
    end
  end
  return cover_idx, image_idx, alt_idx, indent or "  "
end

local function find_cover_toml(block, lines)
  local section_idx
  for i = block.open_idx + 1, block.close_idx - 1 do
    if lines[i]:match("^%[cover%]%s*$") then
      section_idx = i
      break
    end
  end
  if not section_idx then return nil end
  local image_idx, alt_idx
  for i = section_idx + 1, block.close_idx - 1 do
    if lines[i]:match("^%[") then break end
    if lines[i]:match("^image%s*=") then image_idx = i end
    if lines[i]:match("^alt%s*=")   then alt_idx   = i end
  end
  return section_idx, image_idx, alt_idx
end

-- Read the `cover.alt` field. Returns the string value (may be empty)
-- or nil if the field is not present. Used to decide whether to prompt
-- the user for alt text in the first place (archetype-driven UX).
function M.read_cover_alt(path)
  local lines = read_lines(path)
  if not lines then return nil end
  local block = locate(lines)
  if not block then return nil end

  local alt_idx
  if block.kind == "yaml" then
    _, _, alt_idx = find_cover_yaml(block, lines)
  elseif block.kind == "toml" then
    _, _, alt_idx = find_cover_toml(block, lines)
  else
    return nil
  end
  if not alt_idx then return nil end

  local raw
  if block.kind == "yaml" then
    raw = lines[alt_idx]:match("^%s+alt%s*:%s*(.*)$")
  else
    raw = lines[alt_idx]:match("^alt%s*=%s*(.*)$")
  end
  if not raw then return nil end
  return strip_quotes(raw)
end

-- Set the PaperMod `cover.image` field. Creates the `cover` block if
-- absent. Returns true on success, (nil, error) on failure. JSON
-- frontmatter is not supported.
--
-- Optional `alt` parameter updates `cover.alt` — but **only if the
-- field already exists** in the frontmatter (usually placed there by
-- the site archetype). This keeps the plugin archetype-driven: it
-- doesn't invent theme-specific structure, only updates what the
-- author's template established.
--
-- YAML: `cover:\n  image: "..."` (two-space indent).
-- TOML: `[cover]\nimage = "..."`.
function M.set_cover_image(path, image, alt)
  local lines, bufnr = read_lines(path)
  if not lines then return nil, "file not readable: " .. path end
  local block = locate(lines)
  if not block then return nil, "no frontmatter found in " .. path end

  local image_q = image:gsub("\\", "\\\\"):gsub('"', '\\"')
  local alt_q = alt and alt:gsub("\\", "\\\\"):gsub('"', '\\"') or nil

  if block.kind == "yaml" then
    local cover_idx, image_idx, alt_idx, indent = find_cover_yaml(block, lines)
    if cover_idx then
      if image_idx then
        lines[image_idx] = indent .. 'image: "' .. image_q .. '"'
      else
        table.insert(lines, cover_idx + 1, indent .. 'image: "' .. image_q .. '"')
        -- alt index shifts if it was after cover_idx (it always is).
        if alt_idx then alt_idx = alt_idx + 1 end
      end
      if alt_q ~= nil and alt_idx then
        lines[alt_idx] = indent .. 'alt: "' .. alt_q .. '"'
      end
    else
      table.insert(lines, block.close_idx, "cover:")
      table.insert(lines, block.close_idx + 1, '  image: "' .. image_q .. '"')
      -- Archetype-driven: don't fabricate an `alt:` line here.
    end
  elseif block.kind == "toml" then
    local section_idx, image_idx, alt_idx = find_cover_toml(block, lines)
    if section_idx then
      if image_idx then
        lines[image_idx] = 'image = "' .. image_q .. '"'
      else
        table.insert(lines, section_idx + 1, 'image = "' .. image_q .. '"')
        if alt_idx then alt_idx = alt_idx + 1 end
      end
      if alt_q ~= nil and alt_idx then
        lines[alt_idx] = 'alt = "' .. alt_q .. '"'
      end
    else
      table.insert(lines, block.close_idx, "[cover]")
      table.insert(lines, block.close_idx + 1, 'image = "' .. image_q .. '"')
    end
  else
    return nil, "JSON frontmatter not supported for cover updates"
  end

  write_lines(path, lines, bufnr)
  return true
end

-- Frontmatter arrays ------------------------------------------------------
--
-- Supports the shapes Hugo archetypes typically produce:
--   YAML block:   `tags:` followed by `  - foo` lines
--   YAML inline:  `tags: [foo, bar]`
--   TOML inline:  `tags = ["foo", "bar"]`
-- On write, YAML is normalised to block form (better for diffs) and TOML
-- to single-line inline form.

local function parse_inline_list(s)
  local items = {}
  s = s:match("^%s*(.-)%s*$")
  if s == "" then return items end
  for item in s:gmatch("[^,]+") do
    local v = strip_quotes(item)
    if v ~= "" then items[#items + 1] = v end
  end
  return items
end

local function escape_quoted(s)
  return s:gsub("\\", "\\\\"):gsub('"', '\\"')
end

-- Locate a list field. Returns (start_idx, end_idx, items) — inclusive line
-- range spanning the field in `block.lines`. Items are strings with
-- surrounding quotes stripped.
local function find_list(block, field)
  local key = vim.pesc(field)
  if block.kind == "yaml" then
    for i = block.open_idx + 1, block.close_idx - 1 do
      local line = block.lines[i]
      local inline = line:match("^" .. key .. "%s*:%s*%[(.-)%]%s*$")
      if inline then
        return i, i, parse_inline_list(inline)
      end
      if line:match("^" .. key .. "%s*:%s*$") then
        local items = {}
        local end_idx = i
        for j = i + 1, block.close_idx - 1 do
          local item = block.lines[j]:match("^%s+%-%s+(.*)$")
          if item then
            items[#items + 1] = strip_quotes(item)
            end_idx = j
          else
            break
          end
        end
        return i, end_idx, items
      end
    end
  elseif block.kind == "toml" then
    for i = block.open_idx + 1, block.close_idx - 1 do
      local inline = block.lines[i]:match("^" .. key .. "%s*=%s*%[(.-)%]%s*$")
      if inline then
        return i, i, parse_inline_list(inline)
      end
    end
  end
  return nil
end

local function format_yaml_list(field, items)
  if #items == 0 then return { field .. ": []" } end
  local out = { field .. ":" }
  for _, v in ipairs(items) do
    out[#out + 1] = '  - "' .. escape_quoted(v) .. '"'
  end
  return out
end

local function format_toml_list(field, items)
  local parts = {}
  for _, v in ipairs(items) do
    parts[#parts + 1] = '"' .. escape_quoted(v) .. '"'
  end
  return { field .. " = [" .. table.concat(parts, ", ") .. "]" }
end

local function splice(lines, from, to, replacement)
  local out = {}
  for i = 1, from - 1 do out[#out + 1] = lines[i] end
  for _, l in ipairs(replacement) do out[#out + 1] = l end
  for i = to + 1, #lines do out[#out + 1] = lines[i] end
  return out
end

-- Read a list field. Returns the items array (possibly empty) or nil on
-- failure (unreadable file / no frontmatter). A missing field yields {}.
function M.read_list(path, field)
  local lines = read_lines(path)
  if not lines then return nil end
  local block = locate(lines)
  if not block then return nil end
  local _, _, items = find_list(block, field)
  return items or {}
end

-- Replace (or create) a list field. Returns true on success, (nil, error)
-- on failure. JSON frontmatter is not supported.
function M.set_list(path, field, items)
  local lines, bufnr = read_lines(path)
  if not lines then return nil, "file not readable: " .. path end
  local block = locate(lines)
  if not block then return nil, "no frontmatter found in " .. path end

  local new_lines
  if block.kind == "yaml" then
    new_lines = format_yaml_list(field, items)
  elseif block.kind == "toml" then
    new_lines = format_toml_list(field, items)
  else
    return nil, "JSON frontmatter not supported for list updates"
  end

  local start_idx, end_idx = find_list(block, field)
  if start_idx then
    lines = splice(lines, start_idx, end_idx, new_lines)
  else
    lines = splice(lines, block.close_idx, block.close_idx - 1, new_lines)
  end
  write_lines(path, lines, bufnr)
  return true
end

-- Read the `title` field (best-effort, for display purposes only).
function M.read_title(path)
  local lines = read_lines(path)
  if not lines then return nil end
  local block = locate(lines)
  if not block then return nil end
  local _, value = find_scalar(block, "title")
  if not value then return nil end
  value = value:gsub("^['\"]", ""):gsub("['\"]%s*,?%s*$", "")
  return value
end

return M
