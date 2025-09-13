module initializer

import os

pub fn init_project(project_name string) {
    println('Initializing C++ project: ${project_name}')
    
    // Create directory structure
    dirs := ['src', 'include', 'build', 'bin']
    for dir in dirs {
        full_path := os.join_path(project_name, dir)
        os.mkdir_all(full_path) or {
            println('Warning: Failed to create ${full_path}: ${err}')
        }
    }
    
    // Create basic CMakeLists.txt
    cmake_content := r'
# CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(${project_name})

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Add executable
add_executable(${project_name} src/main.cpp)

# Add include directories
target_include_directories(${project_name} PRIVATE include)
'
    os.write_file(os.join_path(project_name, 'CMakeLists.txt'), cmake_content) or { }
    
    // Create main.cpp
    main_content := r'
#include <iostream>

int main() {
    std::cout << "Hello, ${project_name}!" << std::endl;
    return 0;
}
'
    os.write_file(os.join_path(project_name, 'src', 'main.cpp'), main_content) or { }
    
    // Create .gitignore
    gitignore_content := r'
# Build files
build/
bin/
*.o
*.exe
*.dSYM
*.d

# IDE files
.vscode/
.idea/
*.swp
*.swo

# OS files
.DS_Store
Thumbs.db
'
    os.write_file(os.join_path(project_name, '.gitignore'), gitignore_content) or { }
    
    // Create config.ini
    config_content := r'
# ${project_name} lana build configuration
project_name = ${project_name}
src_dir = src
build_dir = build
bin_dir = bin
debug = true
optimize = false
verbose = false
include_dirs = include
'
    os.write_file(os.join_path(project_name, 'config.ini'), config_content) or { }
    
    // Create README.md
    readme_content := r'
# ${project_name}

A C++ project built with lana (Vlang C++ Build System)

## Getting Started

### Build the project
```bash
lana build
```

### Run the project
```bash
lana run
```

### Clean build files
```bash
lana clean
```

## Project Structure
- `src/` - Source files
- `include/` - Header files  
- `build/` - Object files and intermediate build files
- `bin/` - Executable output

## Configuration
Edit `config.ini` to customize build settings:
- `debug` - Enable/disable debug mode
- `optimize` - Enable/disable optimization
- `include_dirs` - Additional include directories
- `libraries` - Linker libraries to include

## Command Line Options
```bash
lana build [options]
  -d, --debug      Enable debug mode
  -O, --optimize   Enable optimization
  -v, --verbose    Verbose output
  -I <dir>         Add include directory
  -l <lib>         Add library
  -o <name>        Set output name
  --config <file>  Use custom config file
```
'
    os.write_file(os.join_path(project_name, 'README.md'), readme_content) or { }
    
    println('Project initialized successfully!')
    println('Created directory structure and template files')
    println('')
    println('Usage:')
    println('  cd ${project_name}')
    println('  lana build')
    println('  lana run')
}