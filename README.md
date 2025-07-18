# fold-imports.nvim

![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)
![Neovim](https://img.shields.io/badge/NeoVim-%2357A143.svg?&style=for-the-badge&logo=neovim&logoColor=white)

A Neovim plugin that automatically folds import/export statements in multiple programming languages using Tree-sitter queries. Reduces visual clutter by folding verbose import blocks while maintaining code organization.

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "neogoose/fold-imports.nvim",
  config = function()
    require("fold_imports").setup()
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "neogoose/fold-imports.nvim",
  config = function()
    require("fold_imports").setup()
  end,
}
```

## Quick Start

The plugin works out of the box with zero configuration:

```lua
require("fold_imports").setup()
```

Open any supported file and imports will be automatically folded.

## Configuration

### Default Configuration

```lua
require("fold_imports").setup({
  enabled = true,
  auto_fold = true,
  fold_level = 0,
  -- Re-folds imports after LSP code edits (e.g. code actions)
  auto_fold_after_code_action = true,
  -- Custom fold text for import sections
  custom_fold_text = true,
  fold_text_format = "Folded imports (%d lines)",
  -- Maximum lines for a single import statement to be considered for folding
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
  },
})
```

### Custom Language Configuration

Disable specific languages or add custom Tree-sitter queries:

```lua
require("fold_imports").setup({
  languages = {
    -- Disable TypeScript folding
    typescript = {
      enabled = false,
    },
    -- Add your language with a query
    python = {
      enabled = true,
      queries = {
        -- To see what to put here run `:InspectTree` and put cursor over the import statement
        "(import_statement) @import",
        "(import_from_statement) @import",
      },
    },
  },
})
```

### Disable Auto-folding

For manual control only:

```lua
require("fold_imports").setup({
  auto_fold = false,
})
```

Then use `:FoldImports` command to fold imports manually.

## Commands

| Command              | Description                                      |
| -------------------- | ------------------------------------------------ |
| `:FoldImports`       | Manually fold imports in the current buffer      |
| `:FoldImportsToggle` | Enable/disable the plugin                        |
| `:FoldImportsDebug`  | Debug Tree-sitter matches for the current buffer |

## API

The plugin exposes a Lua API for programmatic control:

```lua
local fold_imports = require("fold_imports")

-- Manually fold imports
fold_imports.fold_imports()

-- Enable the plugin
fold_imports.enable()

-- Disable the plugin
fold_imports.disable()

-- Toggle the plugin
fold_imports.toggle()
```

## How It Works

1. **Tree-sitter Integration**: Uses Tree-sitter parsers to accurately identify import statements in different languages
2. **Smart Grouping**: Groups adjacent import statements, ignoring empty lines between them
3. **Intelligent Folding**: Creates folds for:
   - Multi-line import groups
   - Multiple separate import groups
   - Single-line imports when there are multiple imports total
4. **LSP Integration**: Monitors LSP text edits and re-folds imports when changes occur near existing import folds
5. **Performance**: Uses retries with exponential backoff and optimizes the runtime

## Language Support

### TypeScript/JavaScript

- **Supported**: Import declarations, export statements with export clauses
- **Examples**: `import { foo } from 'bar'`, `export { baz }`

### Rust

- **Supported**: Use declarations, module items
- **Examples**: `use std::collections::HashMap;`, `mod utils;`

### Python

- **Supported**: Import statements, from-import statements, future imports
- **Examples**: `import os`, `from typing import List`, `from __future__ import annotations`

### C/C++

- **Supported**: Preprocessor includes, defines, using declarations (C++), namespace aliases (C++)
- **Examples**: `#include <stdio.h>`, `using namespace std;`

### OCaml

- **Supported**: Open module statements
- **Examples**: `open List`, `open Printf`

### Zig

- **Supported**: Variable declarations with @import builtin
- **Examples**: `const std = @import("std");`

## Troubleshooting

### Imports Not Folding

1. **Check Tree-sitter parser**: Ensure the required Tree-sitter parser is installed:

   ```vim
   :TSInstall typescript javascript rust python c cpp ocaml zig
   ```

2. **Debug Tree-sitter matches**: Use the debug command to see what's being detected:

   ```vim
   :FoldImportsDebug
   ```

3. **Verify filetype**: Check that your file has the correct filetype:
   ```vim
   :set filetype?
   ```

### Custom Queries Not Working

Tree-sitter queries are language-specific. Use `:TSPlayground` to explore the syntax tree and write custom queries. The query format follows Tree-sitter query syntax.

## Requirements

- **Neovim**: >= 0.8.0
- **Tree-sitter**: Built-in Neovim Tree-sitter support
- **Parsers**: Language-specific Tree-sitter parsers (installed via `:TSInstall`)

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Author

Created by [@neogoose_btw](https://x.com/neogoose_btw)

Built with [Tree-sitter](https://tree-sitter.github.io/) for accurate parsing. Template based on [nvim-plugin-template](https://github.com/ellisonleao/nvim-plugin-template).

