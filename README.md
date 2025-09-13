# Lana - V C++ Build System

A simple, fast C++ build tool  designed for modern C++ projects.

## Features

- **Automatic dependency tracking** for efficient rebuilds
- **Simple configuration** with `config.ini` files
- **Cross-platform** support
- **Clean, minimal interface**

## Installation

1. Install V: https://vlang.io/
2. Build Lana:
   ```bash
   v . -o lana
   ```
3. Add to PATH or use from current directory

## Quick Start

### Initialize a new project
```bash
lana init myproject
cd myproject
```

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

```
myproject/
├── src/          # Source files (.cpp, .cc, .cxx)
├── include/      # Header files (.h, .hpp)
├── build/        # Object files and intermediates
├── bin/          # Executable output
├── config.ini    # Build configuration
├── README.md     # Project documentation
└── .gitignore    # Git ignore file
```

## Commands

- `lana build` - Compile the project
- `lana run` - Build and execute
- `lana clean` - Remove build files
- `lana init <name>` - Create new project

## Configuration

Edit `config.ini` to customize your build:

```ini
# Project settings
project_name = myproject
src_dir = src
build_dir = build
bin_dir = bin
debug = true
optimize = false
verbose = false
include_dirs = include
libraries = 
cflags = 
ldflags = 
```

## License

MIT License - see LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request
