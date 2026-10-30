-- Pandoc Lua filter for the md-to-pdf skill.
-- Renders Mermaid blocks to PDF via mermaid-cli, rewrites cross-document
-- links, sizes table columns from their content, and makes inline code
-- breakable at word separators.

local utils = pandoc.utils
local system = pandoc.system

local build_dir = os.getenv("MDPDF_BUILD") or system.get_working_directory()
local filter_dir = os.getenv("MDPDF_SCRIPTS") or "."
local single_mode = os.getenv("MDPDF_SINGLE") == "1"
local mmdc_version = os.getenv("MDPDF_MMDC_VERSION") or "10.9.1"

local input_basenames = {}
for _, path in ipairs(PANDOC_STATE.input_files) do
  local base = path:match("([^/]+)%.md$")
  if base then input_basenames[#input_basenames + 1] = base end
end
local input_set = {}
for _, b in ipairs(input_basenames) do input_set[b] = true end

-- Part dividers: MDPDF_PARTS holds "basename=Part title" lines; a \part page
-- is emitted before the chapter that starts with that file.
local parts = {}
for line in (os.getenv("MDPDF_PARTS") or ""):gmatch("[^\n]+") do
  local base, title = line:match("^%s*([^=]+)=(.+)$")
  if base then parts[base:gsub("%s+$", "")] = title:gsub("^%s+", "") end
end

local highlightable = {}
for _, l in ipairs({ "sql", "bash", "sh", "zsh", "csharp", "python", "json",
  "yaml", "java", "go", "kotlin", "javascript", "typescript", "xml", "html",
  "css", "dockerfile", "makefile", "diff", "ini", "toml", "powershell",
  "protobuf", "ruby", "rust", "c", "cpp", "scala", "groovy", "lua", "r",
  "latex", "tex", "markdown" }) do
  highlightable[l] = true
end

local function tex_escape_code(s)
  local map = {
    ["\\"] = "\\textbackslash{}", ["{"] = "\\{", ["}"] = "\\}",
    ["$"] = "\\$", ["&"] = "\\&", ["#"] = "\\#", ["%"] = "\\%",
    ["_"] = "\\_\\allowbreak{}", ["^"] = "\\^{}", ["~"] = "\\textasciitilde{}",
    ["."] = ".\\allowbreak{}", ["/"] = "/\\allowbreak{}",
    ["-"] = "-\\allowbreak{}", [":"] = ":\\allowbreak{}",
    [" "] = "\\ ",
  }
  local out = s:gsub("[\\{}$&#%%_^~./%-: ]", map)
  out = out:gsub("(%l)(%u)", "%1\\allowbreak{}%2")
  out = out:gsub("([%(|,=])", "\\allowbreak{}%1")
  out = out:gsub("%w+", function(run)
    if #run <= 20 then return nil end
    return (run:gsub("(%w%w%w%w%w%w%w%w%w%w)", "%1\\allowbreak{}"))
  end)
  return out
end

local function pdf_dims(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local data = fh:read("a")
  fh:close()
  local x0, y0, x1, y1 = data:match("/MediaBox%s*%[%s*([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)")
  if not x0 then return nil end
  return math.abs(tonumber(x1) - tonumber(x0)), math.abs(tonumber(y1) - tonumber(y0))
end

local text_width_pt = 150 / 25.4 * 72
local max_height_pt = (240 - 19 - 17) / 25.4 * 72 * 0.92

local function fit_scale(path)
  local w, h = pdf_dims(path)
  if not w or w == 0 or h == 0 then return nil end
  return math.min(text_width_pt / w, max_height_pt / h)
end

local function run_mmdc(src)
  local hash = pandoc.sha1(src)
  local mmd = build_dir .. "/mermaid-" .. hash .. ".mmd"
  local pdf = build_dir .. "/mermaid-" .. hash .. ".pdf"
  local existing = io.open(pdf, "rb")
  if existing then existing:close(); return pdf end
  local fh = assert(io.open(mmd, "wb"))
  fh:write(src, "\n")
  fh:close()
  local ok, err = pcall(pandoc.pipe, "npx", {
    "-y", "@mermaid-js/mermaid-cli@" .. mmdc_version,
    "-i", mmd, "-o", pdf,
    "-p", filter_dir .. "/puppeteer.json",
    "-c", filter_dir .. "/mermaid-config.json",
    "-w", "4000", "-H", "4000",
    "--pdfFit", "-b", "transparent",
  }, "")
  if not ok then
    io.stderr:write("[filter.lua] mermaid render failed: " .. tostring(err) .. "\n")
    return nil
  end
  return pdf
end

-- Wide left-to-right flowcharts shrink to unreadable text on a portrait page.
-- Render the author's layout first; if it is wider than 1.5:1, also render a
-- top-down variant and keep whichever fits the page at the larger scale.
-- Diagrams never scale above their natural size (15px labels = 11pt).
local function render_mermaid(src)
  local pdf = run_mmdc(src)
  if not pdf then return nil end
  local scale = fit_scale(pdf)
  local w, h = pdf_dims(pdf)
  if not (scale and w and h and w / h > 1.5) then return pdf end
  scale = math.min(scale, 1)
  local td_src, n = src:gsub("^(%s*[%w]+)%s+[LR][RL]", "%1 TD", 1)
  if n == 0 then return pdf end
  local td_pdf = run_mmdc(td_src)
  if not td_pdf then return pdf end
  local td_scale = fit_scale(td_pdf)
  if td_scale then td_scale = math.min(td_scale, 1) end
  if td_scale and td_scale > scale * 1.05 then
    io.stderr:write(string.format("[filter.lua] mermaid: using top-down layout (scale %.2f vs %.2f)\n", td_scale, scale))
    return td_pdf
  end
  return pdf
end

local h1_seen = 0

-- A block that longtable, tcolorbox, or an image starts: these force their own
-- page break when they do not fit, which would strand the heading above them.
local function starts_unbreakable(b)
  if b.t == "Table" or b.t == "CodeBlock" then return true end
  return b.t == "RawBlock" and b.format == "latex" and b.text:match("^\\nopagebreak") ~= nil
end

-- Pass 1 (top-down): headers, links, inline code, text cleanup.
local pass1 = {
  traverse = "topdown",

  -- Reserve room before a heading so it stays with what follows it: ten lines
  -- when a table, code block, or diagram comes next, five lines otherwise.
  -- Chapters start a new page and need nothing.
  Blocks = function(blocks)
    local out = pandoc.List()
    for i, b in ipairs(blocks) do
      if b.t == "Header" and not (b.level == 1 and not single_mode) then
        local nxt = blocks[i + 1]
        local lines = (nxt and starts_unbreakable(nxt)) and 10 or 5
        out:insert(pandoc.RawBlock("latex", string.format("\\Needspace*{%d\\baselineskip}", lines)))
      end
      out:insert(b)
    end
    return out
  end,

  Header = function(h)
    if h.level == 1 then
      h1_seen = h1_seen + 1
      if single_mode then
        return {}, false
      end
      local base = input_basenames[h1_seen]
      local out = {}
      if base then
        h.identifier = "doc-" .. base
        if parts[base] then
          out[#out + 1] = pandoc.RawBlock("latex", "\\part{" .. parts[base] .. "}")
        end
      end
      out[#out + 1] = h
      return out, false
    end
    if single_mode then h.level = h.level - 1 end
    return h, false
  end,

  Link = function(l)
    local base, anchor = l.target:match("^([%w%-]+)%.md#?(.*)$")
    if base and input_set[base] then
      if anchor ~= "" then
        l.target = "#" .. anchor
      else
        l.target = "#doc-" .. base
      end
    end
    return l
  end,

  Code = function(c)
    return pandoc.RawInline("latex", "\\texttt{" .. tex_escape_code(c.text) .. "}")
  end,

  Str = function(s)
    local t = s.text:gsub("\239\184\143", "")
    if t ~= s.text then return pandoc.Str(t) end
    return nil
  end,
}

-- Pass 2 (bottom-up): code blocks and tables.
local pass2 = {
  CodeBlock = function(cb)
    local lang = cb.classes[1]
    if lang == "mermaid" then
      local pdf = render_mermaid(cb.text)
      if pdf then
        local img = pandoc.Image({}, pdf)
        return {
          pandoc.RawBlock("latex", "\\nopagebreak\\begin{center}"),
          pandoc.Plain({ img }),
          pandoc.RawBlock("latex", "\\end{center}"),
        }
      end
      cb.classes = { "text" }
      lang = "text"
    end
    if lang and highlightable[lang] then return nil end
    return pandoc.RawBlock("latex",
      "\\nopagebreak\\begin{Shaded}\n\\begin{Verbatim}\n" .. cb.text .. "\n\\end{Verbatim}\n\\end{Shaded}")
  end,

  Table = function(tbl)
    local ncols = #tbl.colspecs
    if ncols < 2 then return nil end
    local chars_per_line = ncols >= 6 and 96 or 84
    local need, minneed = {}, {}
    for i = 1, ncols do need[i] = 0; minneed[i] = 0 end
    local function longest_piece(text)
      local best = 0
      for word in text:gmatch("%S+") do
        for piece in word:gmatch("[^_%./:%-]+") do
          local n = utf8.len(piece) or #piece
          if n > best then best = n end
        end
      end
      return best
    end
    local function scan(rows)
      for _, row in ipairs(rows) do
        for i, cell in ipairs(row.cells) do
          if i <= ncols then
            local text = utils.stringify(cell.contents)
            local n = utf8.len(text) or #text
            need[i] = math.max(need[i], math.min(n, 80))
            minneed[i] = math.max(minneed[i], math.min(longest_piece(text), 22))
          end
        end
      end
    end
    scan(tbl.head.rows)
    for _, body in ipairs(tbl.bodies) do scan(body.head); scan(body.body) end
    local frac, minfrac, sum = {}, {}, 0
    for i = 1, ncols do
      need[i] = math.max(need[i], minneed[i], 4)
      sum = sum + need[i]
    end
    for i = 1, ncols do
      frac[i] = need[i] / sum
      minfrac[i] = math.min((minneed[i] + 2) / chars_per_line, 0.45)
    end
    for _ = 1, 6 do
      local deficit, slack = 0, 0
      for i = 1, ncols do
        if frac[i] < minfrac[i] then
          deficit = deficit + (minfrac[i] - frac[i]); frac[i] = minfrac[i]
        else
          slack = slack + (frac[i] - minfrac[i])
        end
      end
      if deficit <= 1e-6 or slack <= 1e-6 then break end
      for i = 1, ncols do
        if frac[i] > minfrac[i] then
          frac[i] = frac[i] - deficit * (frac[i] - minfrac[i]) / slack
        end
      end
    end
    local total = 0
    for i = 1, ncols do total = total + frac[i] end
    for i = 1, ncols do
      tbl.colspecs[i] = { tbl.colspecs[i][1], frac[i] / total }
    end
    local size = ncols >= 6 and "\\footnotesize" or "\\small"
    return {
      pandoc.RawBlock("latex", "\\nopagebreak\\begingroup" .. size),
      tbl,
      pandoc.RawBlock("latex", "\\endgroup"),
    }
  end,
}

local title_grabber = {
  Pandoc = function(doc)
    if not single_mode or doc.meta.title then return nil end
    for _, blk in ipairs(doc.blocks) do
      if blk.t == "Header" and blk.level == 1 then
        doc.meta.title = pandoc.MetaInlines(blk.content)
        return doc
      end
    end
    return nil
  end,
}

return { title_grabber, pass2, pass1 }
