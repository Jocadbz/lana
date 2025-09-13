# Lana Documentation

## Table of Contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [Project Structure](#project-structure)
4. [Commands](#commands)
5. [Configuration](#configuration)
6. [Build Process](#build-process)
7. [Dependency Management](#dependency-management)
8. [Command Line Options](#command-line-options)
9. [Configuration File Format](#configuration-file-format)
10. [Troubleshooting](#troubleshooting)
11. [Development](#development)

## Overview

Lana is a lightweight C++ build system. It provides a simple alternative to complex build systems like CMake, focusing on speed, simplicity, and modern C++ development workflows.

Key features:
- Automatic source file discovery
- Dependency tracking via `#include` analysis
- Incremental builds with timestamp checking
- Support for debug/optimized builds
- Simple configuration via INI files
- Cross-platform (Linux, macOS, Windows)

## Installation

### Prerequisites
- V compiler (version 0.3.0 or later)
- GCC/G++ compiler (version 7+ recommended)
- Standard C++ library

### Building Lana

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/lana.git
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

Lana expects a specific directory layout:

```
project/
├── src/              # Source files (.cpp, .cc, .cxx)
│   ├── main.cpp
│   └── utils/
│       └── helper.cpp
├── include/          # Header files (.h, .hpp)
│   ├── utils.hpp
│   └── config.hpp
├── build/            # Generated: Object files (*.o), dependencies (*.d)
├── bin/              # Generated: Executable
├── config.ini        # Build configuration
├── README.md         # Project documentation
└── .gitignore        # Git configuration
```

### Source Files
- Lana automatically finds `.cpp`, `.cc`, and `.cxx` files
- Supports nested directories (recursive search)
- Header files should be in `include/` or subdirectories

### Build Directories
- `build/` - Contains object files (`.o`) and dependency files (`.d`)
- `bin/` - Contains the final executable

## Commands

### Initialize Project
```bash
lana init <project_name>
```

Creates a new project with:
- Directory structure (`src/`, `include/`, `build/`, `bin/`)
- Template `main.cpp`
- `config.ini` configuration file
- `.gitignore`
- `README.md`

**Example:**
```bash
lana init myapp
cd myapp
```

### Build Project
```bash
lana build [options]
```

Compiles all source files and links the executable. Only rebuilds files that have changed or have newer dependencies.

**Options:**
- `-d, --debug` - Enable debug mode (default)
- `-O, --optimize` - Enable optimization
- `-v, --verbose` - Show detailed build information
- `-o <name>` - Set output executable name
- `-I <dir>` - Add include directory
- `-l <lib>` - Link library
- `--config <file>` - Use custom config file

**Example:**
```bash
lana build -d -v
lana build -O -I external/lib/include -l pthread
```

### Run Project
```bash
lana run [options]
```

Builds the project (if needed) and executes the binary.

**Example:**
```bash
lana run
lana run -O  # Run with optimizations
```

### Clean Project
```bash
lana clean
```

Removes all generated files:
- `build/` directory (object files, dependencies)
- `bin/` executable

**Example:**
```bash
lana clean
```

### Help
```bash
lana --help
# or
lana -h
```

Shows available commands and options.

## Configuration

Lana uses a simple INI-style configuration file (`config.ini`) in the project root.

### Basic Configuration

```ini
# Project identification
project_name = myapp

# Directory paths (relative to project root)
src_dir = src
build_dir = build
bin_dir = bin

# Build modes (mutually exclusive)
debug = true
optimize = false

# Output verbosity
verbose = false

# Compiler settings
include_dirs = include,external/lib/include
libraries = pthread,boost_system
cflags = -Wall -Wextra -std=c++17
ldflags = -static
```

### Configuration Precedence

1. Command line options (highest priority)
2. `config.ini` file
3. Default values (lowest priority)

### Directory Configuration

You can customize directory paths:

```ini
src_dir = sources
include_dirs = headers,third_party/include
build_dir = obj
bin_dir = output
```

Lana will create these directories automatically during the build process.

## Build Process

### Compilation

1. **Source Discovery**: Lana recursively scans `src_dir` for `.cpp`, `.cc`, `.cxx` files
2. **Dependency Analysis**: Extracts `#include` directives from each source file
3. **Incremental Build Check**: Compares timestamps of source files and dependencies against object files
4. **Compilation**: Uses `g++` to compile each source file to an object file (`.o`)
5. **Dependency Generation**: Creates `.d` files for each object file

### Linking

1. **Object Collection**: Gathers all compiled object files
2. **Library Linking**: Includes specified libraries (`-l` flags)
3. **Final Linking**: Links all objects into the executable in `bin_dir`

### Compiler Flags

Lana generates compiler commands with:

**Debug Mode** (default):
```bash
g++ -c -g -O0 -Wall -Wextra -std=c++17 -Iinclude source.cpp -o build/source.o
```

**Optimized Mode**:
```bash
g++ -c -O3 -Wall -Wextra -std=c++17 -Iinclude source.cpp -o build/source.o
```

**Linking**:
```bash
g++ -g build/*.o -lpthread -o bin/myapp
```

## Dependency Management

Lana provides basic dependency tracking through:

### Include Extraction

Lana parses C++ source files to extract `#include` directives:

```cpp
#include "utils.hpp"        // Local header
#include <iostream>         // System header
#include "../external/lib.h" // Relative path
```

### Dependency Rules

For each source file, Lana tracks:
- **Source timestamp**: When the `.cpp` file was last modified
- **Header timestamps**: When included headers were last modified
- **Object timestamp**: When the corresponding `.o` file was created

### Rebuild Triggers

A source file is recompiled if:
1. The source file is newer than its object file
2. Any included header is newer than the object file
3. The object file doesn't exist
4. Dependencies change (detected via `.d` files)

### Generated Dependencies

Lana creates `.d` files for make compatibility:

```
build/main.o: src/main.cpp include/utils.hpp
build/utils/helper.o: src/utils/helper.cpp include/utils.hpp
```

## Command Line Options

### Build Options

| Option | Description | Example |
|--------|-------------|---------|
| `-d, --debug` | Enable debug symbols and no optimization | `lana build -d` |
| `-O, --optimize` | Enable optimization (disables debug) | `lana build -O` |
| `-v, --verbose` | Show detailed build commands | `lana build -v` |
| `-o <name>, --output <name>` | Set executable name | `lana build -o myapp` |

### Include/Library Options

| Option | Description | Example |
|--------|-------------|---------|
| `-I <dir>` | Add include directory | `lana build -I external/include` |
| `-l <lib>` | Link library | `lana build -l pthread` |

### Configuration Options

| Option | Description | Example |
|--------|-------------|---------|
| `--config <file>` | Use custom config file | `lana build --config custom.ini` |

### Examples

```bash
# Debug build with verbose output
lana build -d -v

# Optimized release build
lana build -O

# Build with external dependencies
lana build -I third_party/include -l boost_system -l sqlite3

# Custom output name
lana build -o game.exe

# Use custom config
lana build --config release.ini
```

## Configuration File Format

The `config.ini` file uses a simple key-value format:

### Syntax

```ini
# Comments start with #
key = value

# Arrays use comma or space separation
array_key = value1, value2, value3
```

### Available Keys

#### Project Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `project_name` | string | "project" | Executable name |
| `src_dir` | string | "src" | Source directory |
| `build_dir` | string | "build" | Object files directory |
| `bin_dir` | string | "bin" | Executable directory |

#### Build Options

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `debug` | bool | true | Enable debug mode |
| `optimize` | bool | false | Enable optimization |
| `verbose` | bool | false | Verbose output |

#### Compiler Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `include_dirs` | string[] | [] | Include directories (comma/space separated) |
| `libraries` | string[] | [] | Linker libraries (comma/space separated) |
| `cflags` | string[] | [] | Additional compiler flags (space separated) |
| `ldflags` | string[] | [] | Additional linker flags (space separated) |

### Example Configurations

#### Debug Configuration (`debug.ini`)

```ini
project_name = myapp
src_dir = src
build_dir = build
bin_dir = bin

debug = true
optimize = false
verbose = true

include_dirs = include,external/lib/include
libraries = pthread
cflags = -Wall -Wextra -std=c++17 -fPIC
ldflags = 
```

#### Release Configuration (`release.ini`)

```ini
project_name = myapp
src_dir = src
build_dir = build
bin_dir = bin

debug = false
optimize = true
verbose = false

include_dirs = include
libraries = pthread
cflags = -O3 -DNDEBUG -std=c++17
ldflags = -s
```

## Troubleshooting

### Common Issues

#### "No source files found"
**Cause**: No `.cpp`, `.cc`, or `.cxx` files in the source directory.

**Solution**:
1. Check `src_dir` in `config.ini`
2. Verify source files exist in the specified directory
3. Ensure files have correct extensions

#### "Compilation failed"
**Cause**: Compiler errors in source code.

**Solution**:
1. Use `-v` flag to see full compiler output
2. Check for syntax errors, missing headers, or type issues
3. Verify include paths with `-I` flags

#### "Linking failed"
**Cause**: Missing libraries or undefined symbols.

**Solution**:
1. Install required development libraries (`sudo apt install libxxx-dev`)
2. Add libraries with `-l` flag or `libraries` in config
3. Check library paths with `-L` flag if needed

#### "Permission denied"
**Cause**: Missing execute permissions on generated binary.

**Solution**:
```bash
chmod +x bin/myapp
```

### Build Verbosity

Enable verbose mode to see detailed build information:

```bash
lana build -v
```

This shows:
- Full compiler and linker commands
- Include paths being used
- Dependency analysis results
- File timestamps

### Log Files

Lana doesn't create log files by default, but you can capture output:

```bash
lana build -v > build.log 2>&1
```

### Compiler Detection

Lana uses `g++` by default. To use a different compiler:

1. **Set environment variable**:
   ```bash
   export CXX=clang++
   ```

2. **Modify build scripts** (advanced):
   Edit `config.v` to change the compiler path.

## Development

### Architecture

Lana consists of several modules:

```
lana/
├── config/          # Configuration parsing and defaults
├── builder/         # Core build logic
├── deps/            # Dependency extraction and tracking
├── runner/          # Executable execution
├── initializer/     # Project initialization
├── help/            # Help text and CLI interface
└── main.v           # Entry point
```

### Building from Source

1. **Install V**:
   ```bash
   git clone https://github.com/vlang/v
   cd v
   make
   ```

2. **Build Lana**:
   ```bash
   v . -o lana
   ```

3. **Run tests** (if implemented):
   ```bash
   v test .
   ```

### Adding Features

#### New Build Options

1. Add to `config.BuildConfig` struct
2. Update `parse_args()` in `config.v`
3. Modify compiler/linker command builders
4. Update help text

#### Custom Compilers

To support different compilers:

1. Add compiler detection in `config.v`
2. Create compiler-specific flag mappings
3. Update `build_compiler_command()` and `build_linker_command()`

#### Advanced Dependency Tracking

For more sophisticated dependency management:

1. Enhance `deps.extract_dependencies()` to handle:
   - Preprocessor macros
   - Template instantiations
   - Conditional includes
2. Implement dependency graph analysis
3. Add parallel build support

### Contributing

1. **Fork** the repository
2. **Create feature branch**:
   ```bash
   git checkout -b feature/amazing-feature
   ```
3. **Make changes** and add tests
4. **Commit**:
   ```bash
   git commit -m 'Add amazing feature'
   ```
5. **Push** to branch:
   ```bash
   git push origin feature/amazing-feature
   ```
6. **Create Pull Request**

### Code Style

- Follow V coding conventions
- Use descriptive variable names
- Keep functions small and focused
- Add comments for complex logic
- Write tests for new features

### License

Lana is licensed under the MIT License. See the LICENSE file for details.

---
*Documentation generated for Lana version 1.0.0*
*Last updated: [Current Date]*
*Report issues: [GitHub Issues Link]*
*Contribute: [GitHub Repository Link]*
