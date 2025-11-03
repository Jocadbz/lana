# Lana Documentation

## Table of Contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [Project Structure](#project-structure)
4. [Commands](#commands)
5. [Configuration](#configuration)
6. [Build Directives](#build-directives)
7. [Build Process](#build-process)
8. [Dependency Management](#dependency-management)
9. [Command Line Options](#command-line-options)
10. [Configuration File Format](#configuration-file-format)
11. [Troubleshooting](#troubleshooting)
12. [Development](#development)

## Overview

Lana is a lightweight C++ build system designed for modern C++ development. It provides a simple, fast alternative to complex tools like CMake or Make, emphasizing speed, simplicity, and self-contained project management.

Key features:
- **Automatic source discovery** in `src/` directories
- **Build directives** embedded directly in C++ source files for per-file configuration (dependencies, linking, output, flags)
- **Dependency tracking** via `#include` analysis and timestamp checking
- **Incremental builds** to recompile only changed files
- **Support for shared libraries, tools/executables, and asset hooks (e.g., GLSL shaders via dependencies)**
- **Simple global configuration** via `config.ini`
- **Cross-platform** (Linux, macOS, Windows) with parallel compilation
- **No external scripts needed**—everything is in your source files

Lana parses `// build-directive:` comments in your C++ files to handle project-specific details, while `config.ini` manages globals like compiler flags and paths.

## Installation

### Prerequisites
- V compiler (version 0.3.0 or later)
- GCC/G++ (version 7+ recommended)
- Standard C++ library
- For shader workflows: Vulkan SDK or shaderc (includes `glslc`)

### Building Lana

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/lana.git  # Replace with actual repo
   cd lana
   ```

2. Build the tool:
   ```bash
   v . -o lana
   ```

3. Make executable (Linux/macOS):
   ```bash
   chmod +x lana
   ```

4. Add to PATH (optional):
   ```bash
   sudo mv lana /usr/local/bin/
   ```

## Project Structure

Lana expects this layout (created by `lana init`):

```
project/
├── src/              # Source files (.cpp, .cc, .cxx) with build directives
│   ├── main.cpp      # Example main tool (directives at top)
│   ├── lib/          # Shared library sources
│   │   └── cli.cpp   # Example shared lib (directives at top)
│   ├── tools/        # Tool/executable sources
│   │   └── example_tool.cpp  # Example tool depending on lib/cli
├── include/          # Header files (.h, .hpp)
│   └── cli.h         # Example header
├── build/            # Generated: Object files (*.o), dependencies (*.d)
├── bin/              # Generated: Executables and libs
│   ├── lib/          # Shared libraries (.so/.dll)
│   ├── tools/        # Tool executables
├── config.ini        # Global build configuration
├── README.md         # Project docs (auto-generated with directive examples)
└── .gitignore        # Ignores build artifacts
```

- **Build Directives**: Add `// build-directive:` comments at the top of C++ files for per-file settings (see [Build Directives](#build-directives)).
- **Auto-Discovery**: If no directives, Lana treats files as simple tools using global config.

## Commands

### Initialize Project
```bash
lana init <project_name>
```
Creates the structure above, including template C++ files **with build directives by default** (e.g., in `src/main.cpp`, `src/lib/cli.cpp`). Includes `config.ini`, `README.md` (with directive docs), and examples for shared libs/tools.

**Example:**
```bash
lana init myapp
cd myapp
# Files like src/main.cpp now have directives like:
# // build-directive: unit-name(tools/main)
# // build-directive: out(tools/main)
```

### Build Project
```bash
lana build [options]
```
Compiles sources, processes directives, builds dependency graph, and links outputs. Incremental: only rebuilds changed files.

**Options:** See [Command Line Options](#command-line-options).

**Example:**
```bash
lana build -d -v  # Debug build with verbose output (shows directive parsing)
```

### Run Project
```bash
lana run [options]
```
Builds (if needed) and runs the main executable (first tool or `project_name` from config/directives).

**Example:**
```bash
lana run -O  # Optimized run
```

### Clean Project
```bash
lana clean
```
Removes `build/`, `bin/`, and intermediates.

**Example:**
```bash
lana clean
```

### Help
```bash
lana --help
```
Shows commands, options, and config examples.

### Setup (dependencies)
```bash
lana setup
```
Fetches and extracts external dependencies declared in `config.ini` under `[dependencies]` sections. Each dependency supports the following keys:

- `name` - logical name for the dependency (required)
- `url` - download URL or git repository (optional)
- `archive` - optional filename to save the downloaded archive under `dependencies/tmp`
- `checksum` - optional sha256 checksum to verify the archive
- `extract_to` - directory under `dependencies/` where files should be extracted or cloned
- `build_cmds` - optional semicolon-separated shell commands to build/install the dependency

Notes:
- Only `name` is required. If `url` is omitted Lana will skip any download/clone and extraction steps — this is useful for dependencies that are generated locally or that only require running project-local commands.
- If `url` points to a git repository (ends with `.git`), `lana setup` will perform a shallow clone into `dependencies/<extract_to>`.
- For archive URLs `lana setup` will try `curl` then `wget` to download, will verify checksum if provided, and will extract common archive types (`.tar.gz`, `.tar.xz`, `.zip`).
- When `build_cmds` are present they are executed either inside `dependencies/<extract_to>` (if `extract_to` is set or a clone/extract was performed) or in the project root (if no extract directory is available).
- The current implementation performs a best-effort download/extract and prints warnings/errors; it is intentionally simple and can be extended or replaced by a more robust script if needed.

Example (only `name` + `build_cmds`):

```ini
[dependencies]
name = generate_headers
build_cmds = tools/gen_headers.sh; cp -r generated/include ../../include/
```

In this example `lana setup` will not try to download anything — it will run the `build_cmds` from the project root, allowing you to run arbitrary local build or generation steps.

## Configuration

`config.ini` handles **global** settings (overridden by directives for per-file needs). Edit it in your project root.

### Basic Configuration
```ini
# Project identification
project_name = myapp

# Directory paths (relative to project root)
src_dir = src
build_dir = build
bin_dir = bin

# Build modes (mutually exclusive; CLI overrides)
debug = true
optimize = false

# Output verbosity
verbose = false

# Compiler settings (global defaults; directives can add/override)
include_dirs = include  # Comma/space-separated
libraries = pthread     # Comma/space-separated (global libs)
cflags = -Wall -Wextra -std=c++17
ldflags = 

# Advanced
parallel_compilation = true
dependencies_dir = dependencies
```

### Configuration Precedence
1. Command-line options (highest: e.g., `-d` overrides `debug=true`)
2. `config.ini`
3. Defaults (e.g., `debug=true`, compiler=`g++`)

Directives (in source files) handle per-file overrides (e.g., custom `cflags` for one unit).

## Build Directives

Lana's killer feature: Embed build instructions **directly in C++ source files** using `// build-directive:` comments. No separate scripts—keeps projects self-contained.

### How It Works
- **Parsing**: `lana build` scans sources for lines like `// build-directive: <type>(<value>)`.
- **Processing**: Builds a dependency graph; resolves build order, linking, and flags.
- **Placement**: At file top (before code). Multiple per file (one per line).
- **Fallback**: No directives? Auto-discover as simple tool using global config.
- **Output**: Verbose mode (`-v`) shows parsed units/graph.

### Syntax
```
// build-directive: <type>(<value>)
```
- `<type>`: Directive name (e.g., `unit-name`).
- `<value>`: Arguments (comma/space-separated for lists; `true/false` for bools).

### Supported Directives
- **`unit-name(<name>)`**: Unique unit ID (e.g., `"lib/cli"`, `"tools/mytool"`). Required for custom builds. Defaults to file path if omitted.
- **`depends-units(<unit1>,<unit2>,...)`**: Dependencies (other units, e.g., `"lib/utils,lib/file"`). Builds them first.
- **`link(<lib1>,<lib2>,...)`**: Libraries to link (e.g., `"utils.so,pthread,boost_system"`). Internal (Lana-built) or external.
- **`out(<path>)`**: Output relative to `bin/` (e.g., `"tools/mytool"`, `"lib/mylib"`). Defaults to unit name.
- **`cflags(<flag1> <flag2> ...)`**: Per-file compiler flags (e.g., `"-std=c++20 -fPIC"`). Appends to global `cflags`.
- **`ldflags(<flag1> <flag2> ...)`**: Per-file linker flags (e.g., `"-static -pthread"`). Appends to global `ldflags`.
- **`shared(<true|false>)`**: Build as shared lib (`.so`/`.dll`, true) or executable (false, default).

### Examples

**Simple Executable (`src/main.cpp`)**:
```cpp
// build-directive: unit-name(tools/main)
// build-directive: depends-units()
// build-directive: link()
// build-directive: out(tools/main)

#include <iostream>

int main() {
    std::cout << "Hello, World!" << std::endl;
    return 0;
}
```
- Builds `bin/tools/main` executable. No deps.

**Shared Library (`src/lib/cli.cpp`)**:
```cpp
// build-directive: unit-name(lib/cli)
// build-directive: depends-units()
// build-directive: link()
// build-directive: out(lib/cli)
// build-directive: shared(true)
// build-directive: cflags(-fPIC)

#include <iostream>
#include "cli.h"

namespace lana {
    void print_help() { std::cout << "CLI help" << std::endl; }
}
```
- Builds `bin/lib/cli.so`. PIC for shared lib.

**Tool Depending on Shared Lib (`src/tools/mytool.cpp`)**:
```cpp
// build-directive: unit-name(tools/mytool)
// build-directive: depends-units(lib/cli)
// build-directive: link(cli.so)
// build-directive: out(tools/mytool)
// build-directive: shared(false)
// build-directive: cflags(-std=c++17)
// build-directive: ldflags(-pthread)

#include <iostream>
#include "cli.h"

int main() {
    lana::print_help();
    return 0;
}
```
- Depends on/builds `lib/cli` first; links `cli.so`; outputs `bin/tools/mytool`.

### Tips
- **Order**: Directives before `#include` or code.
- **Empty Values**: Use `()` for none (e.g., `depends-units()`).
- **Global Interaction**: Directives add to `config.ini` settings (e.g., global `-Wall` + per-file `-std=c++20`).
- **Assets**: Use `[dependencies]` hooks for non-C++ steps (e.g., shader compilation).
- **Legacy**: Use `[shared_libs]`/`[tools]` in config for manual lists (overrides auto-parsing).

## Build Process

1. **Parse Directives**: Scans sources for `// build-directive:`; collects into units/graph.
2. **Source Discovery**: Finds `.cpp`/`.cc`/`.cxx` in `src_dir` (recursive).
3. **Dependency Analysis**: Extracts `#include`s; builds graph from directives/timestamps.
4. **Incremental Check**: Recompiles if source/header newer than `.o` or `.d` missing.
5. **Compilation**: `g++ -c` each source to `.o` (uses global + per-file flags).
6. **Linking**: Builds shared libs/tools per directives (e.g., `g++ -shared` for libs).
7. **Dependency Hooks**: Executes `[dependencies]` build commands (use for assets like shaders).

**Example Output** (`lana build -v`):
```
Parsing build directives...
Found directive for unit: lib/cli in src/lib/cli.cpp
Found directive for unit: tools/mytool in src/tools/mytool.cpp
Building dependency graph...
Build order: lib/cli -> tools/mytool
Building unit: lib/cli
Compiling src/lib/cli.cpp -> build/lib/cli.o
Linking shared library: bin/lib/cli.so
Building unit: tools/mytool
Compiling src/tools/mytool.cpp -> build/tools/mytool.o
Linking executable: bin/tools/mytool
Build completed successfully!
```

## Dependency Management

- **Include Extraction**: Parses `#include` for rebuild triggers (local/system headers).
- **Directive-Based Deps**: `depends-units()` defines unit graph; `link()` handles libs.
- **Timestamp Checks**: Rebuild if source/header > `.o` timestamp.
- **Generated `.d` Files**: Make-compatible deps (e.g., `build/main.o: src/main.cpp include/utils.hpp`).
- **Graph Resolution**: Topological sort; warns on cycles.

## Command Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `-d, --debug` | Debug mode (`-g -O0`) | `lana build -d` |
| `-O, --optimize` | Optimized mode (`-O3`) | `lana build -O` |
| `-v, --verbose` | Show commands/graph | `lana build -v` |
| `-p, --parallel` | Parallel jobs | `lana build -p` |
| `-o <name>` | Output name | `lana build -o app` |
| `-I <dir>` | Include dir | `lana build -I external/` |
| `-l <lib>` | Link lib | `lana build -l pthread` |
| `--config <file>` | Custom config | `lana build --config release.ini` |
| `--shared-lib <name> <source>` | Legacy shared lib | `lana build --shared-lib cli src/lib/cli.cpp` |
| `--tool <name> <source>` | Legacy tool | `lana build --tool mytool src/tools/mytool.cpp` |

**Examples:**
```bash
lana build -d -v -p  # Debug, verbose, parallel
lana run -O           # Optimized run
lana build -I lib/include -l boost -l sqlite3
```

## Configuration File Format

INI-style (`config.ini`):

```ini
# Comments with #
key = value
array_key = val1, val2  # Comma/space-separated
```

**Full Example (`config.ini`)**:
```ini
[global]
project_name = myapp
src_dir = src
build_dir = build
bin_dir = bin
debug = true
optimize = false
verbose = false
parallel_compilation = true
include_dirs = include,external/include
libraries = pthread,boost_system
cflags = -Wall -Wextra -std=c++17
ldflags = -static

[shared_libs]  # Legacy/manual (directives preferred)
name = cli
sources = src/lib/cli.cpp
libraries = 

[tools]  # Legacy/manual
name = main
sources = src/main.cpp
libraries = cli
```

## Troubleshooting

### Common Issues

- **"No source files found"**: Check `src_dir` in config; ensure `.cpp` files exist.
- **"Failed to parse directive"**: Verify syntax (e.g., `unit-name(lib/cli)`); use `-v` for details.
- **"Dependency not found"**: Add missing `depends-units()` or build order in directives.
- **Linking errors**: Check `link()` for libs; install dev packages (e.g., `sudo apt install libpthread-dev`).
- **Asset build fails**: Verify commands in `[dependencies]` hook scripts (e.g., shader toolchain).
- **Permission denied**: `chmod +x bin/tools/mytool`.

### Debugging Tips
- **Verbose Build**: `lana build -v` shows directive parsing, graph, and commands.
- **Check Graph**: Look for "Build order:" in verbose output.
- **Dependency Files**: Inspect `build/*.d` for include tracking.
- **Logs**: `lana build -v > build.log 2>&1`.
- **Clean Rebuild**: `lana clean && lana build -v`.

## Development

See the source code structure in the repo. To extend:
- Add directives: Update `config.BuildDirective` and `builder.build_from_directives()`.
- New features: Modify `config.v` for parsing, `builder.v` for logic.

For contributing, see [GitHub](https://github.com/yourusername/lana) (fork, branch, PR).

---
*Documentation for Lana v1.0.0*  
*Last updated: 2025-09-17*  
*Issues: [Issues](https://lostcave.ddnss.de/git/jocadbz/lana)*  
*Contribute: [Repo](https://lostcave.ddnss.de/git/jocadbz/lana)*
