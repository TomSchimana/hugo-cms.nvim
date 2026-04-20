-- URL-friendly slug generation from a human title.
--
-- - German umlauts expand (ä→ae, ö→oe, ü→ue, ß→ss).
-- - Common Latin diacritics are stripped (é→e, ñ→n, etc.).
-- - Everything else non-alphanumeric becomes a dash.
-- - Multiple dashes collapse; leading/trailing dashes are trimmed.

local M = {}

-- Multi-byte keys use their UTF-8 byte sequences; Lua's gsub matches
-- bytes, so this works without a Unicode library.
local REPLACEMENTS = {
  ["ä"] = "ae", ["ö"] = "oe", ["ü"] = "ue", ["ß"] = "ss",
  ["Ä"] = "ae", ["Ö"] = "oe", ["Ü"] = "ue",
  ["à"] = "a", ["á"] = "a", ["â"] = "a", ["ã"] = "a", ["å"] = "a",
  ["À"] = "a", ["Á"] = "a", ["Â"] = "a", ["Ã"] = "a", ["Å"] = "a",
  ["è"] = "e", ["é"] = "e", ["ê"] = "e", ["ë"] = "e",
  ["È"] = "e", ["É"] = "e", ["Ê"] = "e", ["Ë"] = "e",
  ["ì"] = "i", ["í"] = "i", ["î"] = "i", ["ï"] = "i",
  ["Ì"] = "i", ["Í"] = "i", ["Î"] = "i", ["Ï"] = "i",
  ["ò"] = "o", ["ó"] = "o", ["ô"] = "o", ["õ"] = "o",
  ["Ò"] = "o", ["Ó"] = "o", ["Ô"] = "o", ["Õ"] = "o",
  ["ù"] = "u", ["ú"] = "u", ["û"] = "u",
  ["Ù"] = "u", ["Ú"] = "u", ["Û"] = "u",
  ["ñ"] = "n", ["Ñ"] = "n",
  ["ç"] = "c", ["Ç"] = "c",
  ["ý"] = "y", ["ÿ"] = "y", ["Ý"] = "y",
}

function M.slugify(s)
  if not s or s == "" then return "" end
  local out = s
  for k, v in pairs(REPLACEMENTS) do
    out = out:gsub(k, v)
  end
  out = out:lower()
  -- Replace any run of non-(letter/digit) with a single dash.
  out = out:gsub("[^%a%d]+", "-")
  out = out:gsub("^%-+", ""):gsub("%-+$", "")
  return out
end

return M
