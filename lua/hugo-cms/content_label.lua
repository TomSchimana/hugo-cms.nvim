-- Shared label / column layout for content-entry pickers.
--
-- Used by `:Hugo open`, `:Hugo delete`, `:Hugo rename`, and
-- `:Hugo media insert page` so the four pickers that list content entries
-- look identical. Format:
--
--   d  en   blog/2026/post-slug          Post Title
--   ^  ^    ^                            ^
--   |  |    path column (padded/truncated)
--   |  |                                  title
--   |  lang (2 chars, padded)
--   draft flag (1 char)
--
-- Path is truncated with an ellipsis past PATH_COL_CAP so a single long
-- slug does not push the title column off-screen. Fuzzy matching can't
-- see the truncated tail — that's a known trade-off; the section prefix
-- is what people actually scan for.

local M = {}

local PATH_COL_MIN = 20
local PATH_COL_CAP = 27

local function truncate(s, max)
  if #s <= max then return s end
  return s:sub(1, max - 1) .. "…"
end

-- Path shown to the user. For bundles it's the directory (`blog/2026/x`);
-- for single-file pages it's the file path minus `.md`. Keeps language
-- suffix on singles (`archives.en`) so two language variants don't
-- collapse onto the same line.
function M.display_path(entry)
  if entry.kind == "bundle" then return entry.bundle_rel end
  return (entry.file_rel:gsub("%.md$", ""))
end

-- In-place: sort by path, then language — language siblings end up
-- adjacent and bundles from the same section cluster together.
function M.sort(entries)
  table.sort(entries, function(a, b)
    local pa, pb = M.display_path(a), M.display_path(b)
    if pa ~= pb then return pa < pb end
    return (a.lang or "") < (b.lang or "")
  end)
end

-- Compute the path column width from the longest path, clamped to
-- [PATH_COL_MIN, PATH_COL_CAP] so narrow sites don't look sparse and
-- wide sites don't eat the whole line.
function M.path_width(entries)
  local longest = 0
  for _, e in ipairs(entries) do
    local n = #M.display_path(e)
    if n > longest then longest = n end
  end
  return math.max(PATH_COL_MIN, math.min(PATH_COL_CAP, longest))
end

-- Build a format_item function bound to a given path width. `d` (draft)
-- + lang + path (padded/truncated) + title.
function M.make_formatter(path_width)
  return function(entry)
    local draft = entry.draft and "d" or " "
    local lang = entry.lang or "--"
    if #lang < 2 then lang = lang .. string.rep(" ", 2 - #lang) end
    local path = M.display_path(entry)
    if #path > path_width then
      -- `…` is 3 bytes but 1 display column: resulting display width is
      -- path_width, so no further padding is needed.
      path = truncate(path, path_width)
    elseif #path < path_width then
      path = path .. string.rep(" ", path_width - #path)
    end
    local title = entry.title or "(untitled)"
    return draft .. "  " .. lang .. "   " .. path .. "   " .. title
  end
end

-- Convenience: sort + compute width + return formatter in one call.
-- Typical usage: `local fmt = content_label.prepare(entries)`.
function M.prepare(entries)
  M.sort(entries)
  return M.make_formatter(M.path_width(entries))
end

return M
