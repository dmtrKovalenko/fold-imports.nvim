local M = {}

local default_config = {
  enabled = true,
  auto_fold = true,
  fold_level = 0,
  -- refolds imports after lsp code edits (e.g. code actions)
  auto_fold_after_code_action = true,
  -- custom fold text for import sections
  custom_fold_text = true,
  fold_text_format = "Folded imports (%d lines)",
  -- maximum lines for a single import statement to be considered for folding
  max_import_lines = 50,
  languages = {
    typescript = {
      enabled = true,
      parsers = { "typescript", "tsx" },
      queries = {
        "(import_statement) @import",
        "(export_statement (export_clause) @export)",
      },
      filetypes = { "typescript", "typescriptreact" },
      patterns = { "*.ts", "*.tsx" },
    },
    javascript = {
      enabled = true,
      parsers = { "javascript", "jsx" },
      queries = {
        "(import_statement) @import",
        "(export_statement (export_clause) @export)",
      },
      filetypes = { "javascript", "javascriptreact" },
      patterns = { "*.js", "*.jsx", "*.mjs" },
    },
    rust = {
      enabled = true,
      parsers = { "rust" },
      queries = {
        "(use_declaration) @import",
        "(mod_item) @import",
      },
      filetypes = { "rust" },
      patterns = { "*.rs" },
    },
    c = {
      enabled = true,
      parsers = { "c" },
      queries = {
        "(preproc_include) @import",
        "(preproc_def) @import",
      },
      filetypes = { "c" },
      patterns = { "*.c", "*.h" },
    },
    cpp = {
      enabled = true,
      parsers = { "cpp" },
      queries = {
        "(preproc_include) @import",
        "(preproc_def) @import",
        "(using_declaration) @import",
        "(namespace_alias_definition) @import",
        "(linkage_specification) @import",
      },
      filetypes = { "cpp" },
      patterns = { "*.cpp", "*.cxx", "*.cc", "*.hpp", "*.hxx", "*.hh" },
    },
    ocaml = {
      enabled = true,
      parsers = { "ocaml" },
      queries = {
        "(open_module) @import",
      },
      filetypes = { "ocaml" },
      patterns = { "*.ml", "*.mli" },
    },
    zig = {
      enabled = true,
      parsers = { "zig" },
      queries = {
        '(variable_declaration (identifier) (builtin_function (builtin_identifier) @builtin (#eq? @builtin "@import"))) @import',
      },
      filetypes = { "zig" },
      patterns = { "*.zig" },
    },
    python = {
      enabled = true,
      parsers = { "python" },
      queries = {
        "(import_statement) @import",
        "(import_from_statement) @import",
        "(future_import_statement) @import",
      },
      filetypes = { "python" },
      patterns = { "*.py", "*.pyi" },
    },
    go = {
      enabled = true,
      parsers = { "go" },
      queries = {
        "(import_declaration) @import", -- For import blocks
        "(import_spec) @import", -- For individual imports within blocks
      },
      filetypes = { "go" },
      patterns = { "*.go" },
    },
  },
}

local config = vim.deepcopy(default_config)
local fold_imports_group = nil

local function get_language_config(filetype)
  for _, lang_config in pairs(config.languages) do
    if lang_config.enabled and vim.tbl_contains(lang_config.filetypes, filetype) then
      return lang_config
    end
  end
  return nil
end

-- Helper function to try multiple parsers
local function get_parser_for_language(bufnr, lang_config)
  for _, parser_name in ipairs(lang_config.parsers) do
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, parser_name)
    if ok and parser then
      return parser, parser_name
    end
  end
  return nil, nil
end

local function is_empty_line(bufnr, line_nr)
  local line = vim.api.nvim_buf_get_lines(bufnr, line_nr - 1, line_nr, false)[1]
  if not line then
    return true
  end
  return line:match("^%s*$") ~= nil
end

local function only_empty_lines_between(bufnr, start_line, end_line)
  if start_line >= end_line then
    return true
  end

  for line_nr = start_line + 1, end_line - 1 do
    if not is_empty_line(bufnr, line_nr) then
      return false
    end
  end
  return true
end

local function get_existing_folds(bufnr)
  local folds = {}
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  for line = 1, line_count do
    local fold_start = vim.fn.foldclosed(line)
    if fold_start ~= -1 then
      local fold_end = vim.fn.foldclosedend(line)
      if fold_end ~= -1 then
        table.insert(folds, { fold_start, fold_end })
        -- Skip to end of this fold to avoid duplicates
        line = fold_end
      end
    end
  end

  return folds
end

-- Checks if text edits are within existing import section +- 3 lines
local function edits_within_existing_imports(text_edits, bufnr)
  if not text_edits or #text_edits == 0 then
    return false
  end

  local existing_folds = get_existing_folds(bufnr)
  if #existing_folds == 0 then
    return false
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local buffer_lines_to_check = 3

  -- Check each text edit to see if it's within any existing fold (with buffer)
  for _, edit in ipairs(text_edits) do
    if edit.range then
      -- LSP uses 0-based, Vim uses 1-based
      local edit_start_line = edit.range.start.line + 1
      local edit_end_line = edit.range["end"].line + 1

      -- Check if this edit overlaps with any existing fold (with ±3 line buffer)
      for _, fold in ipairs(existing_folds) do
        local fold_start_with_buffer = math.max(1, fold[1] - buffer_lines_to_check)
        local fold_end_with_buffer = math.min(line_count, fold[2] + buffer_lines_to_check)

        if not (edit_end_line < fold_start_with_buffer or edit_start_line > fold_end_with_buffer) then
          return true
        end
      end
    end
  end

  return false
end

local function group_imports_ignore_empty_lines(bufnr, import_ranges)
  if #import_ranges == 0 then
    return {}
  end

  -- Single pass: filter, sort, and deduplicate in one optimized loop
  local processed_ranges = {}

  for _, range in ipairs(import_ranges) do
    local line_count = range[2] - range[1] + 1
    if line_count <= config.max_import_lines then
      table.insert(processed_ranges, range)
    end
  end

  if #processed_ranges == 0 then
    return {}
  end

  -- Sort by start line
  table.sort(processed_ranges, function(a, b)
    return a[1] < b[1]
  end)

  local final_ranges = { processed_ranges[1] }
  for i = 2, #processed_ranges do
    local current = processed_ranges[i]
    local previous = final_ranges[#final_ranges]

    -- Skip if current is contained in previous (its sorted, we only need to check the last one)
    if not (current[1] >= previous[1] and current[2] <= previous[2]) then
      table.insert(final_ranges, current)
    end
  end

  if #final_ranges == 0 then
    return {}
  end

  local fold_groups = {}
  local current_group = { final_ranges[1][1], final_ranges[1][2] }

  for i = 2, #final_ranges do
    local current_start, current_end = final_ranges[i][1], final_ranges[i][2]

    if only_empty_lines_between(bufnr, current_group[2], current_start) then
      current_group[2] = current_end
    else
      table.insert(fold_groups, current_group)
      current_group = { current_start, current_end }
    end
  end

  table.insert(fold_groups, current_group)
  return fold_groups
end

local function debug_treesitter_matches(bufnr, lang_config, parser_name)
  local parser, _ = get_parser_for_language(bufnr, lang_config)
  if not parser then
    print("No parser found for language")
    return
  end

  local ok_parse, trees = pcall(parser.parse, parser)
  if not ok_parse or not trees or #trees == 0 then
    print("Failed to parse buffer")
    return
  end

  local tree = trees[1]
  local root = tree:root()

  print("Debugging treesitter matches for " .. parser_name .. ":")

  for i, query_string in ipairs(lang_config.queries) do
    print("Query " .. i .. ": " .. query_string)
    local ok_query, query = pcall(vim.treesitter.query.parse, parser_name, query_string)
    if ok_query and query then
      local count = 0
      for _, node, _ in query:iter_captures(root, bufnr) do
        if node and node.range then
          local ok_range, start_row, start_col, end_row, end_col = pcall(node.range, node)
          if ok_range then
            count = count + 1
            local line = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1]
            local line_count = end_row - start_row + 1
            print(
              string.format(
                "  Match %d: [%d:%d-%d:%d] (%d lines) %s",
                count,
                start_row + 1,
                start_col,
                end_row + 1,
                end_col,
                line_count,
                line or ""
              )
            )
          end
        end
      end
      print("  Total matches: " .. count)
    else
      print("  Query failed to parse")
    end
  end
end

-- Check if Tree-sitter parser is ready for the buffer
local function is_parser_ready(bufnr, lang_config)
  local parser, parser_name = get_parser_for_language(bufnr, lang_config)
  if not parser then
    return false
  end

  local ok_parse, trees = pcall(parser.parse, parser)
  if not ok_parse or not trees or #trees == 0 then
    return false
  end

  local tree = trees[1]
  local root = tree:root()
  if not root then
    return false
  end

  return true, parser, parser_name
end

local function fold_imports_for_buffer(attempts)
  attempts = attempts or 5 -- Default to 5 attempts
  local bufnr = vim.api.nvim_get_current_buf()

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local lang_config = get_language_config(vim.bo[bufnr].filetype)
  if not lang_config then
    return
  end

  local ready, parser, parser_name = is_parser_ready(bufnr, lang_config)
  if not ready then
    if attempts > 0 then
      -- Retry with exponential backoff: 50ms, 100ms, 200ms, 400ms, 800ms
      local delay = 50 * (6 - attempts)
      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          fold_imports_for_buffer(attempts - 1)
        end
      end, delay)
    end
    return
  end

  if parser == nil or parser_name == nil then
    return
  end

  local ok_parse, trees = pcall(parser.parse, parser)
  if not ok_parse or not trees or #trees == 0 then
    return
  end

  local tree = trees[1]
  local root = tree:root()

  local import_ranges = {}

  -- Execute all queries for this language
  for _, query_string in ipairs(lang_config.queries) do
    local ok_query, query = pcall(vim.treesitter.query.parse, parser_name, query_string)
    if ok_query and query then
      for _, node, _ in query:iter_captures(root, bufnr) do
        if node and node.range then
          local ok_range, start_row, _, end_row, _ = pcall(node.range, node)
          if ok_range and start_row and end_row then
            table.insert(import_ranges, { start_row + 1, end_row + 1 })
          end
        end
      end
    end
  end

  local fold_groups = group_imports_ignore_empty_lines(bufnr, import_ranges)

  local import_fold_ranges = {}
  for _, group in ipairs(fold_groups) do
    -- Create fold if:
    -- 1. Group spans multiple lines, OR
    -- 2. There are multiple groups (even if single line), OR
    -- 3. There are multiple imports total (even if in one group)
    if group[2] > group[1] or #fold_groups > 1 or #import_ranges > 1 then
      vim.cmd(string.format("%d,%dfold", group[1], group[2]))
      -- Store this fold range as an import fold
      table.insert(import_fold_ranges, { group[1], group[2] })
    end
  end

  vim.b[bufnr].import_fold_ranges = import_fold_ranges
end

local function setup_and_fold()
  if not config.enabled then
    return
  end

  vim.wo.foldmethod = "manual"
  vim.wo.foldenable = true
  vim.wo.foldlevel = config.fold_level

  if config.custom_fold_text then
    vim.wo.foldtext = 'luaeval("require(\\"fold_imports\\")._get_fold_text()")'
  end

  fold_imports_for_buffer()
end

local function get_all_patterns()
  local patterns = {}
  for _, lang_config in pairs(config.languages) do
    if lang_config.enabled then
      vim.list_extend(patterns, lang_config.patterns)
    end
  end
  return patterns
end

local function get_all_filetypes()
  local filetypes = {}
  for _, lang_config in pairs(config.languages) do
    if lang_config.enabled then
      vim.list_extend(filetypes, lang_config.filetypes)
    end
  end
  return filetypes
end

local function setup_autocommands()
  if fold_imports_group then
    vim.api.nvim_del_augroup_by_id(fold_imports_group)
  end

  fold_imports_group = vim.api.nvim_create_augroup("FoldImports", { clear = true })

  if not config.enabled or not config.auto_fold then
    return
  end

  local patterns = get_all_patterns()
  local filetypes = get_all_filetypes()

  if #patterns > 0 then
    vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile", "BufWinEnter" }, {
      group = fold_imports_group,
      pattern = patterns,
      callback = setup_and_fold,
    })
  end

  if #filetypes > 0 then
    vim.api.nvim_create_autocmd("FileType", {
      group = fold_imports_group,
      pattern = filetypes,
      callback = setup_and_fold,
    })

    if config.auto_fold_after_code_action then
      local original_apply_text_edits = vim.lsp.util.apply_text_edits
      vim.lsp.util.apply_text_edits = function(text_edits, bufnr, offset_encoding)
        local result = original_apply_text_edits(text_edits, bufnr, offset_encoding)

        if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
          local filetype = vim.bo[bufnr].filetype
          if vim.tbl_contains(filetypes, filetype) and edits_within_existing_imports(text_edits, bufnr) then
            setup_and_fold()
          end
        end

        return result
      end
    end
  end
end

function M.setup(user_config)
  config = vim.tbl_deep_extend("force", default_config, user_config or {})
  setup_autocommands()

  vim.api.nvim_create_user_command("FoldImports", function()
    fold_imports_for_buffer()
  end, { desc = "Fold imports in current buffer" })

  vim.api.nvim_create_user_command("FoldImportsToggle", function()
    config.enabled = not config.enabled
    setup_autocommands()
    -- Reload current buffer
    vim.cmd("edit")
    print("FoldImports " .. (config.enabled and "enabled" or "disabled"))
  end, { desc = "Toggle fold imports plugin" })

  vim.api.nvim_create_user_command("FoldImportsDebug", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local filetype = vim.bo[bufnr].filetype
    local lang_config = get_language_config(filetype)

    if not lang_config then
      vim.notify("No language config found for filetype: " .. filetype, vim.log.levels.ERROR)
      return
    end

    local parser, parser_name = get_parser_for_language(bufnr, lang_config)
    if not parser then
      vim.notify("No parser found for language " .. filetype, vim.log.levels.ERROR)
      return
    end

    debug_treesitter_matches(bufnr, lang_config, parser_name)
  end, { desc = "Debug treesitter matches for current buffer" })
end

function M.fold_imports()
  fold_imports_for_buffer()
end

function M.enable()
  config.enabled = true
  setup_autocommands()
end

function M.disable()
  config.enabled = false
  setup_autocommands()
end

function M.toggle()
  config.enabled = not config.enabled
  setup_autocommands()
end

function M._get_fold_text()
  local line_start = vim.v.foldstart
  local line_end = vim.v.foldend
  local line_count = line_end - line_start + 1

  local bufnr = vim.api.nvim_get_current_buf()
  local import_fold_ranges = vim.b[bufnr].import_fold_ranges or {}
  local is_import_fold = false

  for _, range in ipairs(import_fold_ranges) do
    if range[1] == line_start and range[2] == line_end then
      is_import_fold = true
      break
    end
  end

  if is_import_fold then
    local fold_text = string.format(config.fold_text_format, line_count)
    local win_width = vim.fn.winwidth(0)
    local text_width = #fold_text
    local fill_count = win_width - text_width - 4 -- 4 for fold marker + padding
    local fill_char = vim.opt.fillchars:get().fold or "-"

    return string.format("+%s %s ", string.rep(fill_char, 2), fold_text)
      .. string.rep(fill_char, math.max(0, fill_count))
  else
    return vim.fn.foldtext()
  end
end

return M
