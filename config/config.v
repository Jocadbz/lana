module config

import os

// BuildDirective represents a single build directive found in source files
pub struct BuildDirective {
__global:
    unit_name     string // e.g., "tools/arraydump" or "lib/file"
    depends_units []string // e.g., ["lib/file", "lib/cli"]
    link_libs     []string // e.g., ["file.so", "cli.so"]
    output_path   string   // e.g., "tools/arraydump"
    cflags        []string // file-specific CFLAGS
    ldflags       []string // file-specific LDFLAGS
    is_shared     bool     // whether this is a shared library
}

// TargetConfig is a sum type for build targets (shared lib or tool)
pub type TargetConfig = SharedLibConfig | ToolConfig

// SharedLibConfig holds the configuration for a shared library
pub struct SharedLibConfig {
__global:
    name       string // name of the shared library (e.g., "net")
    output_dir string = 'bin/lib' // where to put .so/.dll files
    sources    []string // source files for this library
    libraries  []string // libraries this shared lib depends on
    include_dirs []string // additional includes for this lib
    cflags     []string // additional CFLAGS for this lib
    ldflags    []string // additional LDFLAGS for this lib
    debug      bool
    optimize   bool
    verbose    bool
}

// ToolConfig holds the configuration for a tool/executable
pub struct ToolConfig {
__global:
    name       string // name of the tool/executable
    output_dir string = 'bin/tools' // where to put executable
    sources    []string // source files for this tool
    libraries  []string // libraries this tool depends on
    include_dirs []string // additional includes for this tool
    cflags     []string // additional CFLAGS for this tool
    ldflags    []string // additional LDFLAGS for this tool
    debug      bool
    optimize   bool
    verbose    bool
}

// Dependency represents an external dependency to download/extract
pub struct Dependency {
__global:
    name       string
    url        string // download URL
    archive    string // relative archive path to save (under dependencies/tmp)
    checksum   string // optional checksum to verify
    extract_to string // destination directory under dependencies/
    build_cmds []string // optional semicolon-separated build commands
}

// BuildConfig holds the configuration for the project
pub struct BuildConfig {
__global:
    project_name string
    src_dir      string
    build_dir    string
    bin_dir      string
    include_dirs []string
    libraries    []string // global libraries
    cflags       []string // global CFLAGS
    ldflags      []string // global LDFLAGS
    debug        bool
    optimize     bool
    verbose      bool
    compiler     string = 'g++' // C++ compiler binary
    lib_search_paths []string // library search paths (-L)
    
    // New fields for shared library support
    shared_libs []SharedLibConfig
    tools       []ToolConfig
    shaders_dir string = 'bin/shaders' // for shader compilation
    dependencies_dir string = 'dependencies' // external dependencies
    parallel_compilation bool = true // enable parallel builds
    dependencies []Dependency
    
    // Build directives from source files
    build_directives []BuildDirective
}

// default config
pub const default_config = BuildConfig{
    project_name: 'project'
    src_dir: 'src'
    build_dir: 'build'
    bin_dir: 'bin'
    include_dirs: []
    libraries: []
    cflags: []
    ldflags: []
    debug: true
    optimize: false
    verbose: false
    shared_libs: []
    tools: []
    dependencies: []
}

// Parse build directives from source files
pub fn (mut build_config BuildConfig) parse_build_directives() ! {
    mut directives := []BuildDirective{}
    
    // Find all source files in src directory
    src_files := find_source_files(build_config.src_dir) or { 
        if build_config.verbose {
            println('No source files found in ${build_config.src_dir}')
        }
        return
    }
    
    for src_file in src_files {
        content := os.read_file(src_file) or { continue }
        lines := content.split_into_lines()
        
        mut unit_name := ''
        mut depends_units := []string{}
        mut link_libs := []string{}
        mut output_path := ''
        mut file_cflags := []string{}
        mut file_ldflags := []string{}
        mut is_shared := false
        
        for line1 in lines {
            line := line1.trim_space()
            if !line.starts_with('// build-directive:') {
                continue
            }
            
            parts := line[17..].trim_space().split('(')
            if parts.len != 2 {
                continue
            }
            
            directive_type := parts[0].trim_space()
            directive_value := parts[1].trim('()').trim_space()
            
            match directive_type {
                'unit-name' {
                    unit_name = directive_value
                }
                'depends-units' {
                    depends_units = directive_value.split(',')
                    for mut d in depends_units {
                        d = d.trim_space()
                    }
                }
                'link' {
                    link_libs = directive_value.split(',')
                    for mut l in link_libs {
                        l = l.trim_space()
                    }
                }
                'out' {
                    output_path = directive_value
                }
                'cflags' {
                    file_cflags = directive_value.split(' ')
                    for mut f in file_cflags {
                        f = f.trim_space()
                    }
                }
                'ldflags' {
                    file_ldflags = directive_value.split(' ')
                    for mut f in file_ldflags {
                        f = f.trim_space()
                    }
                }
                'shared' {
                    is_shared = directive_value == 'true'
                }
                else {
                    if build_config.verbose {
                        println('Warning: Unknown build directive: ${directive_type} in ${src_file}')
                    }
                }
            }
        }
        
        if unit_name != '' {
            directives << BuildDirective{
                unit_name: unit_name
                depends_units: depends_units
                link_libs: link_libs
                output_path: output_path
                cflags: file_cflags
                ldflags: file_ldflags
                is_shared: is_shared
            }
            
            if build_config.verbose {
                println('Found build directive for unit: ${unit_name} in ${src_file}')
            }
        }
    }
    
    build_config.build_directives = directives
}

pub fn parse_args() !BuildConfig {
    mut build_config := default_config
    // Auto-load config.ini if present in current directory
    if os.is_file('config.ini') {
        build_config = parse_config_file('config.ini') or { build_config }
    }

    mut i := 2 // Skip program name and command
    
    for i < os.args.len {
        arg := os.args[i]
        match arg {
            '-d', '--debug' { build_config.debug = true; build_config.optimize = false }
            '-O', '--optimize' { build_config.optimize = true; build_config.debug = false }
            '-v', '--verbose' { build_config.verbose = true }
            '-p', '--parallel' { build_config.parallel_compilation = true }
            '-o', '--output' { 
                if i + 1 < os.args.len { 
                    build_config.project_name = os.args[i + 1]
                    i++
                }
            }
            '-c', '--compiler' {
                if i + 1 < os.args.len {
                    build_config.compiler = os.args[i + 1]
                    i++
                }
            }
            '-I' {
                if i + 1 < os.args.len { 
                    build_config.include_dirs << os.args[i + 1]
                    i++
                }
            }
            '-L' {
                if i + 1 < os.args.len { 
                    build_config.lib_search_paths << os.args[i + 1]
                    i++
                }
            }
            '-l' {
                if i + 1 < os.args.len { 
                    build_config.libraries << os.args[i + 1]
                    i++
                }
            }
            '--config' {
                if i + 1 < os.args.len { 
                    build_config = parse_config_file(os.args[i + 1])!
                    i++
                }
            }
            '--shared-lib' {
                // Parse shared library configuration
                if i + 2 < os.args.len {
                    lib_name := os.args[i + 1]
                    lib_sources := os.args[i + 2]
                    mut lib_config := SharedLibConfig{
                        name: lib_name
                        sources: [lib_sources]
                        debug: build_config.debug
                        optimize: build_config.optimize
                        verbose: build_config.verbose
                    }
                    build_config.shared_libs << lib_config
                    i += 2
                }
            }
            '--tool' {
                // Parse tool configuration
                if i + 2 < os.args.len {
                    tool_name := os.args[i + 1]
                    tool_sources := os.args[i + 2]
                    mut tool_config := ToolConfig{
                        name: tool_name
                        sources: [tool_sources]
                        debug: build_config.debug
                        optimize: build_config.optimize
                        verbose: build_config.verbose
                    }
                    build_config.tools << tool_config
                    i += 2
                }
            }
            else {
                if !arg.starts_with('-') {
                    // Treat as project name or first source file
                    if build_config.project_name == 'project' {
                        build_config.project_name = arg
                    } else {
                        // Add as default tool
                        mut default_tool := ToolConfig{
                            name: build_config.project_name
                            sources: [arg]
                            debug: build_config.debug
                            optimize: build_config.optimize
                            verbose: build_config.verbose
                        }
                        build_config.tools << default_tool
                    }
                }
            }
        }
        i++
    }

    // Parse build directives from source files
    build_config.parse_build_directives()!

    // If no tools specified, create default tool from src_dir
    if build_config.tools.len == 0 {
        mut default_tool := ToolConfig{
            name: build_config.project_name
            sources: []
            debug: build_config.debug
            optimize: build_config.optimize
            verbose: build_config.verbose
        }
        build_config.tools << default_tool
    }

    return build_config
}

pub fn parse_config_file(filename string) !BuildConfig {
    content := os.read_file(filename) or { return error('Cannot read config file: ${filename}') }
    mut build_config := default_config
    lines := content.split_into_lines()
    
    mut current_section := ''
    mut current_lib_index := 0
    mut current_tool_index := 0
    mut current_dep_index := 0
    
    for line in lines {
        if line.starts_with('#') || line.trim_space() == '' { continue }
        
        if line.starts_with('[') && line.ends_with(']') {
            // keep the brackets in current_section to match existing match arms
            current_section = '[' + line[1..line.len - 1] + ']'
            // Point indices to the next entry index for repeated sections
            if current_section == '[shared_libs]' {
                current_lib_index = build_config.shared_libs.len
            } else if current_section == '[tools]' {
                current_tool_index = build_config.tools.len
            } else if current_section == '[dependencies]' {
                current_dep_index = build_config.dependencies.len
            }
            continue
        }
        
        parts := line.split('=')
        if parts.len == 2 {
            key := parts[0].trim_space()
            value := parts[1].trim_space().trim('"\'')
            
            match current_section {
                '' {
                    match key {
                        'project_name' { build_config.project_name = value }
                        'src_dir' { build_config.src_dir = value }
                        'build_dir' { build_config.build_dir = value }
                        'bin_dir' { build_config.bin_dir = value }
                        'compiler' { build_config.compiler = value }
                        'debug' { build_config.debug = value == 'true' }
                        'optimize' { build_config.optimize = value == 'true' }
                        'verbose' { build_config.verbose = value == 'true' }
                        'parallel_compilation' { build_config.parallel_compilation = value == 'true' }
                        'include_dirs' { 
                            dirs := value.split(',')
                            for dir in dirs { build_config.include_dirs << dir.trim_space() }
                        }
                        'lib_search_paths' { 
                            paths := value.split(',')
                            for path in paths { build_config.lib_search_paths << path.trim_space() }
                        }
                        'libraries' { 
                            libs := value.split(',')
                            for lib in libs { build_config.libraries << lib.trim_space() }
                        }
                        'cflags' { 
                            flags := value.split(' ')
                            for flag in flags { build_config.cflags << flag.trim_space() }
                        }
                        'ldflags' { 
                            flags := value.split(' ')
                            for flag in flags { build_config.ldflags << flag.trim_space() }
                        }
                        'shaders_dir' { build_config.shaders_dir = value }
                        'dependencies_dir' { build_config.dependencies_dir = value }
                        else {}
                    }
                }
                '[shared_libs]' {
                    // Ensure we have a lib config to modify
                    if current_lib_index >= build_config.shared_libs.len {
                        build_config.shared_libs << SharedLibConfig{}
                    }
                    mut lib_config := &build_config.shared_libs[current_lib_index]
                    
                    match key {
                        'name' { lib_config.name = value }
                        'sources' {
                            sources := value.split(',')
                            for src in sources {
                                lib_config.sources << src.trim_space()
                            }
                        }
                        'libraries' {
                            libs := value.split(',')
                            for lib in libs {
                                lib_config.libraries << lib.trim_space()
                            }
                        }
                        'include_dirs' {
                            dirs := value.split(',')
                            for dir in dirs {
                                lib_config.include_dirs << dir.trim_space()
                            }
                        }
                        'cflags' {
                            flags := value.split(' ')
                            for flag in flags {
                                lib_config.cflags << flag.trim_space()
                            }
                        }
                        'ldflags' {
                            flags := value.split(' ')
                            for flag in flags {
                                lib_config.ldflags << flag.trim_space()
                            }
                        }
                        'debug' { lib_config.debug = value == 'true' }
                        'optimize' { lib_config.optimize = value == 'true' }
                        'verbose' { lib_config.verbose = value == 'true' }
                        'output_dir' { lib_config.output_dir = value }
                        else {
                            if build_config.verbose {
                                println('Warning: Unknown shared lib config key: ${key}')
                            }
                        }
                    }
                    // keys for this shared_lib section are populated into the same struct
                }
                '[tools]' {
                    // Ensure we have a tool config to modify
                    if current_tool_index >= build_config.tools.len {
                        build_config.tools << ToolConfig{}
                    }
                    mut tool_config := &build_config.tools[current_tool_index]
                    
                    match key {
                        'name' { tool_config.name = value }
                        'sources' {
                            sources := value.split(',')
                            for src in sources {
                                tool_config.sources << src.trim_space()
                            }
                        }
                        'libraries' {
                            libs := value.split(',')
                            for lib in libs {
                                tool_config.libraries << lib.trim_space()
                            }
                        }
                        'include_dirs' {
                            dirs := value.split(',')
                            for dir in dirs {
                                tool_config.include_dirs << dir.trim_space()
                            }
                        }
                        'cflags' {
                            flags := value.split(' ')
                            for flag in flags {
                                tool_config.cflags << flag.trim_space()
                            }
                        }
                        'ldflags' {
                            flags := value.split(' ')
                            for flag in flags {
                                tool_config.ldflags << flag.trim_space()
                            }
                        }
                        'debug' { tool_config.debug = value == 'true' }
                        'optimize' { tool_config.optimize = value == 'true' }
                        'verbose' { tool_config.verbose = value == 'true' }
                        'output_dir' { tool_config.output_dir = value }
                        else {
                            if build_config.verbose {
                                println('Warning: Unknown tool config key: ${key}')
                            }
                        }
                    }
                    // keys for this tool section are populated into the same struct
                }
                '[dependencies]' {
                    // Ensure we have a dependency entry to modify
                    if current_dep_index >= build_config.dependencies.len {
                        build_config.dependencies << Dependency{}
                    }
                    mut dep := &build_config.dependencies[current_dep_index]

                    match key {
                        'name' { dep.name = value }
                        'url' { dep.url = value }
                        'archive' { dep.archive = value }
                        'checksum' { dep.checksum = value }
                        'build_cmds' {
                            cmds := value.split(';')
                            for c in cmds {
                                dep.build_cmds << c.trim_space()
                            }
                        }
                        'extract_to' { dep.extract_to = value }
                        else {
                            if build_config.verbose {
                                println('Warning: Unknown dependency config key: ${key}')
                            }
                        }
                    }
                    // keys for this dependency section are populated into the same struct
                }
                else {
                    if build_config.verbose {
                        println('Warning: Unknown config section: ${current_section}')
                    }
                }
            }
        }
    }
    
    // Set default values for shared libs and tools from global config if not explicitly set
    for mut lib in build_config.shared_libs {
        if lib.name == '' {
            lib.name = 'lib${build_config.shared_libs.index(lib)}'
        }
        if !lib.debug { lib.debug = build_config.debug }
        if !lib.optimize { lib.optimize = build_config.optimize }
        if !lib.verbose { lib.verbose = build_config.verbose }
    }
    for mut tool in build_config.tools {
        if tool.name == '' {
            tool.name = 'tool${build_config.tools.index(tool)}'
        }
        if !tool.debug { tool.debug = build_config.debug }
        if !tool.optimize { tool.optimize = build_config.optimize }
        if !tool.verbose { tool.verbose = build_config.verbose }
    }
    
    return build_config
}

// Utility function to get target-specific configuration values
pub fn get_target_config_values(target_config TargetConfig) (bool, bool, bool, bool, []string, []string) {
    mut is_shared_lib := false
    mut use_debug := false
    mut use_optimize := false
    mut use_verbose := false
    mut target_includes := []string{}
    mut target_cflags := []string{}
    
    match target_config {
        SharedLibConfig {
            is_shared_lib = true
            use_debug = target_config.debug
            use_optimize = target_config.optimize
            use_verbose = target_config.verbose
            target_includes = target_config.include_dirs.clone()
            target_cflags = target_config.cflags.clone()
        }
        ToolConfig {
            is_shared_lib = false
            use_debug = target_config.debug
            use_optimize = target_config.optimize
            use_verbose = target_config.verbose
            target_includes = target_config.include_dirs.clone()
            target_cflags = target_config.cflags.clone()
        }
    }
    
    return is_shared_lib, use_debug, use_optimize, use_verbose, target_includes, target_cflags
}

// Utility function to build compiler command for shared libraries and tools
pub fn build_shared_compiler_command(source_file string, object_file string, build_config BuildConfig, target_config TargetConfig) string {
    mut cmd := '${build_config.compiler} -c'
    
    // Add include directories (project + target specific)
    for include_dir in build_config.include_dirs {
        cmd += ' -I${include_dir}'
    }
    
    // Add library search paths
    for lib_path in build_config.lib_search_paths {
        cmd += ' -L${lib_path}'
    }
    
    // Get target-specific values
    _, _, _, _, target_includes, target_cflags := get_target_config_values(target_config)
    
    // Add target-specific include dirs
    for include_dir in target_includes {
        if include_dir != '' {
            cmd += ' -I${include_dir}'
        }
    }
    
    // Add debug/optimization flags
    _, use_debug, use_optimize, _, _, _ := get_target_config_values(target_config)
    
    if use_debug {
        cmd += ' -g -O0'
    } else if use_optimize {
        cmd += ' -O3'
    } else {
        cmd += ' -O2'
    }
    
    // Add PIC flag for shared libraries
    is_shared_lib, _, _, _, _, _ := get_target_config_values(target_config)
    if is_shared_lib {
        cmd += ' -fPIC'
    }
    
    // Add standard flags
    cmd += ' -Wall -Wextra -std=c++17'
    
    // Add global CFLAGS
    for flag in build_config.cflags {
        cmd += ' ${flag}'
    }
    
    // Add target-specific CFLAGS
    for flag in target_cflags {
        if flag != '' {
            cmd += ' ${flag}'
        }
    }
    
    cmd += ' ${source_file} -o ${object_file}'
    return cmd
}

// Utility function to build shared library linker command
pub fn build_shared_linker_command(object_files []string, library_name string, output_path string, build_config BuildConfig, lib_config SharedLibConfig) string {
    mut cmd := '${build_config.compiler} -shared'
    
    // Add library search paths
    cmd += ' -L${build_config.bin_dir}/lib'
    for lib_path in build_config.lib_search_paths {
        cmd += ' -L${lib_path}'
    }
    
    // Add debug flags for linking
    if lib_config.debug {
        cmd += ' -g'
    }
    
    // Add object files
    for obj_file in object_files {
        cmd += ' ${obj_file}'
    }
    
    // Add project libraries
    for library in build_config.libraries {
        if library != '' {
            cmd += ' -l${library}'
        }
    }
    
    // Add this library's dependencies
    for library in lib_config.libraries {
        if library != '' {
            cmd += ' -l:${library}.so'
        }
    }
    
    // Add custom LDFLAGS
    for flag in build_config.ldflags {
        cmd += ' ${flag}'
    }
    for flag in lib_config.ldflags {
        cmd += ' ${flag}'
    }
    
    // Set output name (with platform-specific extension)
    mut lib_name := library_name
    $if windows {
        lib_name += '.dll'
    } $else {
        lib_name += '.so'
    }
    
    cmd += ' -o ${output_path}/${lib_name}'
    return cmd
}

// Utility function to build linker command for tools/executables
pub fn build_tool_linker_command(object_files []string, executable string, build_config BuildConfig, tool_config ToolConfig) string {
    mut cmd := '${build_config.compiler}'
    
    // Add library search paths
    cmd += ' -L${build_config.bin_dir}/lib'
    for lib_path in build_config.lib_search_paths {
        cmd += ' -L${lib_path}'
    }
    
    // Add debug flags for linking
    if tool_config.debug {
        cmd += ' -g'
    }
    
    // Add object files
    for obj_file in object_files {
        cmd += ' ${obj_file}'
    }
    
    // Add project libraries
    for library in build_config.libraries {
        if library != '' {
            cmd += ' -l${library}'
        }
    }
    
    // Add this tool's dependencies (shared libs)
    for library in tool_config.libraries {
        if library != '' {
            cmd += ' -l:${library}.so'
        }
    }
    
    // Add custom LDFLAGS
    for flag in build_config.ldflags {
        cmd += ' ${flag}'
    }
    for flag in tool_config.ldflags {
        cmd += ' ${flag}'
    }
    
    cmd += ' -o ${executable}'
    return cmd
}

// Utility function to build compiler command (existing - for backward compatibility)
pub fn build_compiler_command(source_file string, object_file string, build_config BuildConfig) string {
    mut cmd := '${build_config.compiler} -c'
    
    // Add include directories
    for include_dir in build_config.include_dirs {
        cmd += ' -I${include_dir}'
    }
    
    // Add library search paths
    for lib_path in build_config.lib_search_paths {
        cmd += ' -L${lib_path}'
    }
    
    // Add debug/optimization flags
    if build_config.debug {
        cmd += ' -g -O0'
    } else if build_config.optimize {
        cmd += ' -O3'
    } else {
        cmd += ' -O2'
    }
    
    // Add standard flags
    cmd += ' -Wall -Wextra -std=c++17'
    
    // Add custom CFLAGS
    for flag in build_config.cflags {
        cmd += ' ${flag}'
    }
    
    cmd += ' ${source_file} -o ${object_file}'
    return cmd
}

// Utility function to find source files
pub fn find_source_files(dir string) ![]string {
    mut files := []string{}
    
    if !os.is_dir(dir) {
        return error('Source directory does not exist: ${dir}')
    }
    
    items := os.ls(dir) or { return error('Failed to list directory: ${dir}') }
    
    for item in items {
        full_path := os.join_path(dir, item)
        if os.is_file(full_path) {
            if item.ends_with('.cpp') || item.ends_with('.cc') || item.ends_with('.cxx') {
                files << full_path
            }
        } else if os.is_dir(full_path) {
            // Recursively search subdirectories
            sub_files := find_source_files(full_path)!
            files << sub_files
        }
    }
    
    return files
}