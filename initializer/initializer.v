module initializer

import os

pub fn init_project(project_name string) {
    println('Initializing C++ project: ${project_name}')
    
    // Create directory structure
    dirs := [
        'src',
        'src/lib',
        'src/lib/net',
        'src/lib/game',
        'src/tools',
        'src/shaders',
        'include',
        'build',
        'bin',
        'bin/lib',
        'bin/tools',
        'bin/shaders'
    ]
    for dir in dirs {
        full_path := os.join_path(project_name, dir)
        os.mkdir_all(full_path) or {
            println('Warning: Failed to create ${full_path}: ${err}')
        }
    }
    
    // Create basic main.cpp with build directives
    main_content := r'
#include <iostream>

// build-directive: unit-name(tools/main)
// build-directive: depends-units()
// build-directive: link()
// build-directive: out(tools/main)

int main() {
    std::cout << "Hello, ${project_name}!" << std::endl;
    return 0;
}
'
    os.write_file(os.join_path(project_name, 'src', 'main.cpp'), main_content) or { }
    
    // Create example shared library with build directives
    cli_content := r'
// build-directive: unit-name(lib/cli)
// build-directive: depends-units()
// build-directive: link()
// build-directive: out(lib/cli)
// build-directive: shared(true)

#include <iostream>

namespace lana {
    void print_help() {
        std::cout << "Lana CLI help" << std::endl;
    }
}
'
    os.write_file(os.join_path(project_name, 'src/lib', 'cli.cpp'), cli_content) or { }
    
    // Create example tool with build directives
    tool_content := r'
#include <iostream>
// build-directive: unit-name(tools/example_tool)
// build-directive: depends-units(lib/cli)
// build-directive: link(cli.so)
// build-directive: out(tools/example_tool)

int main() {
    std::cout << "Tool example" << std::endl;
    lana::print_help();
    return 0;
}
'
    os.write_file(os.join_path(project_name, 'src/tools', 'example_tool.cpp'), tool_content) or { }
    
    // Create example shader
    vertex_shader := r'
#version 450
layout(location = 0) in vec3 position;
void main() {
    gl_Position = vec4(position, 1.0);
}
'
    os.write_file(os.join_path(project_name, 'src/shaders', 'basic.vsh'), vertex_shader) or { }
    
    // Create .gitignore
    gitignore_content := r'
# Build files
build/
bin/
*.o
*.exe
*.dSYM
*.d
*.so
*.dll
*.dylib

# IDE files
.vscode/
.idea/
*.swp
*.swo

# OS files
.DS_Store
Thumbs.db

# Dependencies
dependencies/
'
    os.write_file(os.join_path(project_name, '.gitignore'), gitignore_content) or { }
    
    // Create config.ini with build directive support
    config_content := r'
# ${project_name} lana build configuration

[global]
project_name = ${project_name}
src_dir = src
build_dir = build
bin_dir = bin
compiler = g++
debug = true
optimize = false
verbose = false
parallel_compilation = true
include_dirs = include
lib_search_paths = 
cflags = -Wall -Wextra
ldflags = 

# Build directives will be automatically parsed from source files
# using // build-directive: comments

[shared_libs]
# These are for legacy support or manual configuration
# Most shared libraries should use build directives in source files

[tools]
# These are for legacy support or manual configuration
# Most tools should use build directives in source files

# Uncomment for shader support
# shaders_dir = bin/shaders
'
    os.write_file(os.join_path(project_name, 'config.ini'), config_content) or { }
    
    // Create README.md with build directive documentation
    readme_content := r'
# ${project_name}

A C++ project built with lana (Vlang C++ Build System)

## Getting Started

### Build the project
```bash
lana build
```

### Run the main executable
```bash
lana run
```

### Run a specific tool
```bash
./bin/tools/example_tool
```

### Clean build files
```bash
lana clean
```

## Project Structure
- `src/` - Source files (.cpp, .cc, .cxx)
  - `lib/` - Shared library sources
  - `tools/` - Tool/executable sources
  - `shaders/` - GLSL shader files (.vsh, .fsh)
- `include/` - Header files (.h, .hpp)  
- `build/` - Object files and intermediate build files
- `bin/` - Executable output
  - `lib/` - Shared libraries (.so/.dll)
  - `tools/` - Tool executables
  - `shaders/` - Compiled shaders (.spv)
- `config.ini` - Build configuration

## Build Directives

Lana reads build instructions directly from source files using special comments:

```
// build-directive: unit-name(tools/arraydump)
// build-directive: depends-units(lib/file,lib/cli)
// build-directive: link(file.so,cli.so)
// build-directive: out(tools/arraydump)
// build-directive: cflags(-Wall -Wextra)
// build-directive: ldflags()
// build-directive: shared(true)
```

### Directive Types

- **unit-name**: Name of the build unit (e.g., "tools/arraydump", "lib/file")
- **depends-units**: Dependencies for this unit (other units or libraries)
- **link**: Libraries to link against (e.g., "file.so", "cli.so")
- **out**: Output path for the binary (relative to bin/)
- **cflags**: Additional CFLAGS for this file
- **ldflags**: Additional LDFLAGS for this file  
- **shared**: Whether this is a shared library (true/false)

### Example Source File

```cpp
// build-directive: unit-name(tools/dumpnbt)
// build-directive: depends-units(lib/nbt,lib/cli)
// build-directive: link(nbt.so,cli.so)
// build-directive: out(tools/dumpnbt)
// build-directive: cflags()
// build-directive: ldflags()
// build-directive: shared(false)

#include <iostream>
#include "nbt.h"
#include "cli.h"

int main() {
    // Your code here
    return 0;
}
```

## Configuration
Edit `config.ini` to customize global build settings:

### Global Settings
```ini
[global]
project_name = myproject
compiler = g++
debug = true
optimize = false
verbose = false
parallel_compilation = true
include_dirs = include,external/lib/include
lib_search_paths = /usr/local/lib,external/lib
cflags = -Wall -Wextra -std=c++17
ldflags = -pthread
```

### Shared Libraries (Legacy)
```ini
[shared_libs]
name = cli
sources = src/lib/cli.cpp
libraries = 
include_dirs = include
cflags = 
ldflags = 
```

### Tools (Legacy)
```ini
[tools]
name = main
sources = src/main.cpp
libraries = cli

name = example_tool
sources = src/tools/example_tool.cpp  
libraries = cli
```

### Shader Support
```ini
# Uncomment to enable shader compilation
shaders_dir = bin/shaders
```

## Command Line Options
```bash
lana build [options]
  -d, --debug            Enable debug mode
  -O, --optimize         Enable optimization
  -v, --verbose          Verbose output
  -p, --parallel         Parallel compilation
  -c, --compiler <name>  Set C++ compiler (default: g++)
  -o <name>              Set project name
  -I <dir>               Add include directory
  -L <dir>               Add library search path
  -l <lib>               Add global library
  --config <file>        Use custom config file
  --shared-lib <name> <source>  Add shared library (legacy)
  --tool <name> <source>        Add tool (legacy)
```

## Build Process

1. **Parse build directives** from source files
2. **Build dependency graph** based on unit dependencies
3. **Compile source files** to object files
4. **Link libraries and executables** according to directives
5. **Compile shaders** if configured

The build system automatically handles:
- Dependency resolution and build ordering
- Incremental builds (only rebuild changed files)
- Shared library vs executable detection
- Custom flags per file
- Parallel compilation

## Examples

### Simple Tool
```cpp
// build-directive: unit-name(tools/calculator)
// build-directive: depends-units()
// build-directive: link()
// build-directive: out(tools/calculator)

#include <iostream>

int main() {
    int a, b;
    std::cin >> a >> b;
    std::cout << "Sum: " << a + b << std::endl;
    return 0;
}
```

### Shared Library with Dependencies
```cpp
// build-directive: unit-name(lib/math)
// build-directive: depends-units(lib/utils)
// build-directive: link(utils.so)
// build-directive: out(lib/math)
// build-directive: shared(true)
// build-directive: cflags(-fPIC)

#include "utils.h"

namespace math {
    double add(double a, double b) {
        return a + b;
    }
}
```

### Complex Tool with Multiple Dependencies
```cpp
// build-directive: unit-name(tools/game)
// build-directive: depends-units(lib/graphics,lib/audio,lib/input)
// build-directive: link(graphics.so,audio.so,input.so,glfw,SDL2)
// build-directive: out(tools/game)
// build-directive: cflags(-DDEBUG)
// build-directive: ldflags(-pthread)

#include "graphics.h"
#include "audio.h"
#include "input.h"

int main() {
    // Game loop
    return 0;
}
```

## License

MIT License - see LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request
'
    os.write_file(os.join_path(project_name, 'README.md'), readme_content) or { }
    
    // Create example header
    header_content := r'
#ifndef LANA_CLI_H
#define LANA_CLI_H

namespace lana {
    void print_help();
}

#endif
'
    os.write_file(os.join_path(project_name, 'include', 'cli.h'), header_content) or { }
    
    println('Project initialized successfully!')
    println('Created directory structure and template files')
    println('')
    println('Usage:')
    println('  cd ${project_name}')
    println('  lana build')
    println('  lana run')
    println('  ./bin/tools/example_tool')
    println('')
    println('Build Directives:')
    println('  Add // build-directive: comments to your source files')
    println('  See README.md for examples and documentation')
    println('Configuration:')
    println('  Edit config.ini for global build settings')
    println('  Add your C++ source files to src/lib/ and src/tools/')
    println('  Add GLSL shaders to src/shaders/ (.vsh, .fsh)')
}