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
    toolchain    string = 'gcc'
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
    dependencies_dir string = 'dependencies' // external dependencies
    parallel_compilation bool = true // enable parallel builds
    dependencies []Dependency
    
    // Build directives from source files
    build_directives []BuildDirective
}

struct RawGlobalConfig {
mut:
    project_name string
    src_dir string
    build_dir string
    bin_dir string
    compiler string
    toolchain string
    debug_str string
    optimize_str string
    verbose_str string
    parallel_str string
    include_dirs []string
    lib_search_paths []string
    libraries []string
    cflags []string
    ldflags []string
    dependencies_dir string
}

struct RawSharedLibConfig {
mut:
    name string
    output_dir string
    sources []string
    libraries []string
    include_dirs []string
    cflags []string
    ldflags []string
    debug_str string
    optimize_str string
    verbose_str string
}

struct RawToolConfig {
mut:
    name string
    output_dir string
    sources []string
    libraries []string
    include_dirs []string
    cflags []string
    ldflags []string
    debug_str string
    optimize_str string
    verbose_str string
}

struct RawDependencyConfig {
mut:
    name string
    url string
    archive string
    checksum string
    extract_to string
    build_cmds []string
}

struct RawBuildConfig {
mut:
    global RawGlobalConfig
    shared_libs []RawSharedLibConfig
    tools []RawToolConfig
    dependencies []RawDependencyConfig
}

fn parse_bool_str(value string) !bool {
    lower := value.trim_space().to_lower()
    return match lower {
        'true', '1', 'yes', 'on' { true }
        'false', '0', 'no', 'off' { false }
        else { error('invalid boolean value: ${value}') }
    }
}

fn parse_comma_list(value string) []string {
    mut result := []string{}
    if value.trim_space() == '' {
        return result
    }
    for item in value.split(',') {
        trimmed := item.trim_space()
        if trimmed != '' {
            result << trimmed
        }
    }
    return result
}

fn parse_space_list(value string) []string {
    mut result := []string{}
    mut fields := value.split_any(' \t')
    if fields.len == 0 && value.trim_space() != '' {
        fields = [value.trim_space()]
    }
    for item in fields {
        trimmed := item.trim_space()
        if trimmed != '' {
            result << trimmed
        }
    }
    return result
}

fn merge_unique(mut target []string, additions []string) {
    for item in additions {
        trimmed := item.trim_space()
        if trimmed == '' {
            continue
        }
        if trimmed !in target {
            target << trimmed
        }
    }
}

fn normalize_raw_config(raw RawBuildConfig, mut warnings []string) BuildConfig {
    mut cfg := default_config
    default_shared := SharedLibConfig{}
    default_tool := ToolConfig{}

    if raw.global.project_name != '' {
        cfg.project_name = raw.global.project_name
    }
    if raw.global.src_dir != '' {
        cfg.src_dir = raw.global.src_dir
    }
    if raw.global.build_dir != '' {
        cfg.build_dir = raw.global.build_dir
    }
    if raw.global.bin_dir != '' {
        cfg.bin_dir = raw.global.bin_dir
    }
    if raw.global.compiler != '' {
        cfg.compiler = raw.global.compiler
    }
    if raw.global.toolchain != '' {
        cfg.toolchain = raw.global.toolchain
    }
    if raw.global.dependencies_dir != '' {
        cfg.dependencies_dir = raw.global.dependencies_dir
    }

    if raw.global.debug_str != '' {
        cfg.debug = parse_bool_str(raw.global.debug_str) or {
            warnings << 'Invalid boolean value for global.debug: ${raw.global.debug_str}'
            cfg.debug
        }
    }
    if raw.global.optimize_str != '' {
        cfg.optimize = parse_bool_str(raw.global.optimize_str) or {
            warnings << 'Invalid boolean value for global.optimize: ${raw.global.optimize_str}'
            cfg.optimize
        }
    }
    if raw.global.verbose_str != '' {
        cfg.verbose = parse_bool_str(raw.global.verbose_str) or {
            warnings << 'Invalid boolean value for global.verbose: ${raw.global.verbose_str}'
            cfg.verbose
        }
    }
    if raw.global.parallel_str != '' {
        cfg.parallel_compilation = parse_bool_str(raw.global.parallel_str) or {
            warnings << 'Invalid boolean value for global.parallel_compilation: ${raw.global.parallel_str}'
            cfg.parallel_compilation
        }
    }

    cfg.include_dirs << raw.global.include_dirs
    cfg.lib_search_paths << raw.global.lib_search_paths
    cfg.libraries << raw.global.libraries
    cfg.cflags << raw.global.cflags
    cfg.ldflags << raw.global.ldflags

    for raw_lib in raw.shared_libs {
        mut lib := SharedLibConfig{
            name: raw_lib.name
            output_dir: if raw_lib.output_dir != '' { raw_lib.output_dir } else { default_shared.output_dir }
            sources: raw_lib.sources.clone()
            libraries: raw_lib.libraries.clone()
            debug: cfg.debug
            optimize: cfg.optimize
            verbose: cfg.verbose
        }
        lib.include_dirs = raw_lib.include_dirs.clone()
        lib.cflags = raw_lib.cflags.clone()
        lib.ldflags = raw_lib.ldflags.clone()

        if raw_lib.debug_str != '' {
            lib.debug = parse_bool_str(raw_lib.debug_str) or {
                warnings << 'Invalid boolean value for shared_lib ${raw_lib.name} debug: ${raw_lib.debug_str}'
                lib.debug
            }
        }
        if raw_lib.optimize_str != '' {
            lib.optimize = parse_bool_str(raw_lib.optimize_str) or {
                warnings << 'Invalid boolean value for shared_lib ${raw_lib.name} optimize: ${raw_lib.optimize_str}'
                lib.optimize
            }
        }
        if raw_lib.verbose_str != '' {
            lib.verbose = parse_bool_str(raw_lib.verbose_str) or {
                warnings << 'Invalid boolean value for shared_lib ${raw_lib.name} verbose: ${raw_lib.verbose_str}'
                lib.verbose
            }
        }

        merge_unique(mut lib.include_dirs, cfg.include_dirs)
        merge_unique(mut lib.cflags, cfg.cflags)
        merge_unique(mut lib.ldflags, cfg.ldflags)

        cfg.shared_libs << lib
    }

    for raw_tool in raw.tools {
        mut tool := ToolConfig{
            name: raw_tool.name
            output_dir: if raw_tool.output_dir != '' { raw_tool.output_dir } else { default_tool.output_dir }
            sources: raw_tool.sources.clone()
            libraries: raw_tool.libraries.clone()
            debug: cfg.debug
            optimize: cfg.optimize
            verbose: cfg.verbose
        }
        tool.include_dirs = raw_tool.include_dirs.clone()
        tool.cflags = raw_tool.cflags.clone()
        tool.ldflags = raw_tool.ldflags.clone()

        if raw_tool.debug_str != '' {
            tool.debug = parse_bool_str(raw_tool.debug_str) or {
                warnings << 'Invalid boolean value for tool ${raw_tool.name} debug: ${raw_tool.debug_str}'
                tool.debug
            }
        }
        if raw_tool.optimize_str != '' {
            tool.optimize = parse_bool_str(raw_tool.optimize_str) or {
                warnings << 'Invalid boolean value for tool ${raw_tool.name} optimize: ${raw_tool.optimize_str}'
                tool.optimize
            }
        }
        if raw_tool.verbose_str != '' {
            tool.verbose = parse_bool_str(raw_tool.verbose_str) or {
                warnings << 'Invalid boolean value for tool ${raw_tool.name} verbose: ${raw_tool.verbose_str}'
                tool.verbose
            }
        }

        merge_unique(mut tool.include_dirs, cfg.include_dirs)
        merge_unique(mut tool.cflags, cfg.cflags)
        merge_unique(mut tool.ldflags, cfg.ldflags)

        cfg.tools << tool
    }

    for raw_dep in raw.dependencies {
        cfg.dependencies << Dependency{
            name: raw_dep.name
            url: raw_dep.url
            archive: raw_dep.archive
            checksum: raw_dep.checksum
            extract_to: raw_dep.extract_to
            build_cmds: raw_dep.build_cmds.clone()
        }
    }

    for i in 0 .. cfg.shared_libs.len {
        if cfg.shared_libs[i].name == '' {
            cfg.shared_libs[i].name = 'lib${i}'
        }
    }

    for i in 0 .. cfg.tools.len {
        if cfg.tools[i].name == '' {
            cfg.tools[i].name = 'tool${i}'
        }
    }

    return cfg
}

// default config
pub const default_config = BuildConfig{
    project_name: ''
    src_dir: 'src'
    build_dir: 'build'
    bin_dir: 'bin'
    toolchain: 'gcc'
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
            
            // slice after the prefix '// build-directive:' (19 characters)
            parts := line[19..].trim_space().split('(')
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
            '--toolchain' {
                if i + 1 < os.args.len {
                    build_config.toolchain = os.args[i + 1]
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
                    if build_config.project_name == '' {
                        build_config.project_name = arg
                    } else {
                        // Add as default tool using the project name
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
    mut raw := RawBuildConfig{}
    mut warnings := []string{}

    mut current_section := 'global'
    mut current_shared_idx := -1
    mut current_tool_idx := -1
    mut current_dep_idx := -1

    for line in content.split_into_lines() {
        trimmed := line.trim_space()
        if trimmed == '' || trimmed.starts_with('#') {
            continue
        }

        if trimmed.starts_with('[') && trimmed.ends_with(']') {
            section := trimmed[1..trimmed.len - 1].trim_space().to_lower()
            match section {
                'global' {
                    current_section = 'global'
                    current_shared_idx = -1
                    current_tool_idx = -1
                    current_dep_idx = -1
                }
                'shared_libs' {
                    raw.shared_libs << RawSharedLibConfig{}
                    current_shared_idx = raw.shared_libs.len - 1
                    current_section = 'shared_libs'
                }
                'tools' {
                    raw.tools << RawToolConfig{}
                    current_tool_idx = raw.tools.len - 1
                    current_section = 'tools'
                }
                'dependencies' {
                    raw.dependencies << RawDependencyConfig{}
                    current_dep_idx = raw.dependencies.len - 1
                    current_section = 'dependencies'
                }
                else {
                    warnings << 'Unknown config section: ${section}'
                    current_section = 'global'
                    current_shared_idx = -1
                    current_tool_idx = -1
                    current_dep_idx = -1
                }
            }
            continue
        }

        eq_index := trimmed.index('=') or {
            warnings << 'Invalid config line (missing =): ${trimmed}'
            continue
        }

        key := trimmed[..eq_index].trim_space()
        mut value := trimmed[eq_index + 1..].trim_space()
        value = value.trim('"\'')

        match current_section {
            'global' {
                match key {
                    'project_name' { raw.global.project_name = value }
                    'src_dir' { raw.global.src_dir = value }
                    'build_dir' { raw.global.build_dir = value }
                    'bin_dir' { raw.global.bin_dir = value }
                    'compiler' { raw.global.compiler = value }
                    'toolchain' { raw.global.toolchain = value }
                    'debug' { raw.global.debug_str = value }
                    'optimize' { raw.global.optimize_str = value }
                    'verbose' { raw.global.verbose_str = value }
                    'parallel_compilation' { raw.global.parallel_str = value }
                    'include_dirs' { raw.global.include_dirs << parse_comma_list(value) }
                    'lib_search_paths' { raw.global.lib_search_paths << parse_comma_list(value) }
                    'libraries' { raw.global.libraries << parse_comma_list(value) }
                    'cflags' { raw.global.cflags << parse_space_list(value) }
                    'ldflags' { raw.global.ldflags << parse_space_list(value) }
                    'dependencies_dir' { raw.global.dependencies_dir = value }
                    else { warnings << 'Unknown global config key: ${key}' }
                }
            }
            'shared_libs' {
                if current_shared_idx < 0 {
                    raw.shared_libs << RawSharedLibConfig{}
                    current_shared_idx = raw.shared_libs.len - 1
                }
                mut lib := &raw.shared_libs[current_shared_idx]
                match key {
                    'name' { lib.name = value }
                    'sources' { lib.sources << parse_comma_list(value) }
                    'libraries' { lib.libraries << parse_comma_list(value) }
                    'include_dirs' { lib.include_dirs << parse_comma_list(value) }
                    'cflags' { lib.cflags << parse_space_list(value) }
                    'ldflags' { lib.ldflags << parse_space_list(value) }
                    'debug' { lib.debug_str = value }
                    'optimize' { lib.optimize_str = value }
                    'verbose' { lib.verbose_str = value }
                    'output_dir' { lib.output_dir = value }
                    else { warnings << 'Unknown shared_libs key: ${key}' }
                }
            }
            'tools' {
                if current_tool_idx < 0 {
                    raw.tools << RawToolConfig{}
                    current_tool_idx = raw.tools.len - 1
                }
                mut tool := &raw.tools[current_tool_idx]
                match key {
                    'name' { tool.name = value }
                    'sources' { tool.sources << parse_comma_list(value) }
                    'libraries' { tool.libraries << parse_comma_list(value) }
                    'include_dirs' { tool.include_dirs << parse_comma_list(value) }
                    'cflags' { tool.cflags << parse_space_list(value) }
                    'ldflags' { tool.ldflags << parse_space_list(value) }
                    'debug' { tool.debug_str = value }
                    'optimize' { tool.optimize_str = value }
                    'verbose' { tool.verbose_str = value }
                    'output_dir' { tool.output_dir = value }
                    else { warnings << 'Unknown tools key: ${key}' }
                }
            }
            'dependencies' {
                if current_dep_idx < 0 {
                    raw.dependencies << RawDependencyConfig{}
                    current_dep_idx = raw.dependencies.len - 1
                }
                mut dep := &raw.dependencies[current_dep_idx]
                match key {
                    'name' { dep.name = value }
                    'url' { dep.url = value }
                    'archive' { dep.archive = value }
                    'checksum' { dep.checksum = value }
                    'extract_to' { dep.extract_to = value }
                    'build_cmds' {
                        for cmd in value.split(';') {
                            trimmed_cmd := cmd.trim_space()
                            if trimmed_cmd != '' {
                                dep.build_cmds << trimmed_cmd
                            }
                        }
                    }
                    else { warnings << 'Unknown dependencies key: ${key}' }
                }
            }
            else {
                warnings << 'Key outside known section: ${key}'
            }
        }
    }

    mut build_config := normalize_raw_config(raw, mut warnings)
    if build_config.verbose {
        for warning in warnings {
            println('Warning: ${warning}')
        }
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
// Toolchain defines how compiler and linker commands are assembled for a target.
pub interface Toolchain {
    compile_command(source_file string, object_file string, build_config &BuildConfig, target_config TargetConfig) string
    shared_link_command(object_files []string, library_name string, output_path string, build_config &BuildConfig, lib_config SharedLibConfig) string
    tool_link_command(object_files []string, executable string, build_config &BuildConfig, tool_config ToolConfig) string
    description() string
}

struct GCCToolchain {
    compiler string
}

struct ClangToolchain {
    compiler string
}

fn (tc GCCToolchain) description() string {
    return 'gcc'
}

fn (tc ClangToolchain) description() string {
    return 'clang'
}

fn (tc GCCToolchain) compile_command(source_file string, object_file string, build_config &BuildConfig, target_config TargetConfig) string {
    return common_compile_command(tc.compiler, source_file, object_file, build_config, target_config)
}

fn (tc ClangToolchain) compile_command(source_file string, object_file string, build_config &BuildConfig, target_config TargetConfig) string {
    return common_compile_command(tc.compiler, source_file, object_file, build_config, target_config)
}

fn (tc GCCToolchain) shared_link_command(object_files []string, library_name string, output_path string, build_config &BuildConfig, lib_config SharedLibConfig) string {
    return common_shared_link_command(tc.compiler, object_files, library_name, output_path, build_config, lib_config)
}

fn (tc ClangToolchain) shared_link_command(object_files []string, library_name string, output_path string, build_config &BuildConfig, lib_config SharedLibConfig) string {
    return common_shared_link_command(tc.compiler, object_files, library_name, output_path, build_config, lib_config)
}

fn (tc GCCToolchain) tool_link_command(object_files []string, executable string, build_config &BuildConfig, tool_config ToolConfig) string {
    return common_tool_link_command(tc.compiler, object_files, executable, build_config, tool_config)
}

fn (tc ClangToolchain) tool_link_command(object_files []string, executable string, build_config &BuildConfig, tool_config ToolConfig) string {
    return common_tool_link_command(tc.compiler, object_files, executable, build_config, tool_config)
}

fn common_compile_command(compiler string, source_file string, object_file string, build_config &BuildConfig, target_config TargetConfig) string {
    mut binary := compiler
    if binary.trim_space() == '' {
        binary = 'g++'
    }
    mut cmd := '${binary} -c'

    for include_dir in build_config.include_dirs {
        cmd += ' -I${include_dir}'
    }

    for lib_path in build_config.lib_search_paths {
        cmd += ' -L${lib_path}'
    }

    _, use_debug, use_optimize, _, target_includes, target_cflags := get_target_config_values(target_config)

    for include_dir in target_includes {
        if include_dir != '' {
            cmd += ' -I${include_dir}'
        }
    }

    if use_debug {
        cmd += ' -g -O0'
    } else if use_optimize {
        cmd += ' -O3'
    } else {
        cmd += ' -O2'
    }

    is_shared_lib, _, _, _, _, _ := get_target_config_values(target_config)
    if is_shared_lib {
        cmd += ' -fPIC'
    }

    cmd += ' -Wall -Wextra'

    for flag in build_config.cflags {
        cmd += ' ${flag}'
    }

    for flag in target_cflags {
        if flag != '' {
            cmd += ' ${flag}'
        }
    }

    cmd += ' ${source_file} -o ${object_file}'
    return cmd
}

fn common_shared_link_command(compiler string, object_files []string, library_name string, output_path string, build_config &BuildConfig, lib_config SharedLibConfig) string {
    mut binary := compiler
    if binary.trim_space() == '' {
        binary = 'g++'
    }
    mut cmd := '${binary} -shared'

    cmd += ' -L${build_config.bin_dir}/lib'
    for lib_path in build_config.lib_search_paths {
        cmd += ' -L${lib_path}'
    }

    if lib_config.debug {
        cmd += ' -g'
    }

    for obj_file in object_files {
        cmd += ' ${obj_file}'
    }

    for library in build_config.libraries {
        if library != '' {
            cmd += ' -l${library}'
        }
    }

    for library in lib_config.libraries {
        if library != '' {
            mut libfile := library
            if libfile.starts_with('lib/') {
                parts := libfile.split('/')
                libfile = parts[parts.len - 1]
            }
            if libfile.ends_with('.so') {
                libfile = libfile.replace('.so', '')
            }
            cmd += ' -l:${libfile}.so'
        }
    }

    for flag in build_config.ldflags {
        cmd += ' ${flag}'
    }
    for flag in lib_config.ldflags {
        cmd += ' ${flag}'
    }

    parts := library_name.split('/')
    base_name := if parts.len > 0 { parts[parts.len - 1] } else { library_name }
    mut lib_name := base_name
    $if windows {
        lib_name += '.dll'
    } $else {
        lib_name += '.so'
    }

    cmd += ' -o ${output_path}/${lib_name}'
    return cmd
}

fn common_tool_link_command(compiler string, object_files []string, executable string, build_config &BuildConfig, tool_config ToolConfig) string {
    mut binary := compiler
    if binary.trim_space() == '' {
        binary = 'g++'
    }
    mut cmd := '${binary}'

    cmd += ' -L${build_config.bin_dir}/lib'
    for lib_path in build_config.lib_search_paths {
        cmd += ' -L${lib_path}'
    }

    if tool_config.debug {
        cmd += ' -g'
    }

    for obj_file in object_files {
        cmd += ' ${obj_file}'
    }

    for library in build_config.libraries {
        if library != '' {
            cmd += ' -l${library}'
        }
    }

    for library in tool_config.libraries {
        if library != '' {
            mut libfile := library
            if libfile.starts_with('lib/') {
                parts := libfile.split('/')
                libfile = parts[parts.len - 1]
            }
            if libfile.ends_with('.so') {
                libfile = libfile.replace('.so', '')
            }
            cmd += ' -l:${libfile}.so'
        }
    }

    for flag in build_config.ldflags {
        cmd += ' ${flag}'
    }
    for flag in tool_config.ldflags {
        cmd += ' ${flag}'
    }

    cmd += ' -o ${executable}'
    return cmd
}

pub fn get_toolchain(build_config BuildConfig) Toolchain {
    mut normalized := build_config.toolchain.to_lower()
    if normalized == '' {
        normalized = 'gcc'
    }
    mut compiler := build_config.compiler
    if compiler.trim_space() == '' {
        compiler = if normalized == 'clang' { 'clang++' } else { 'g++' }
    }

    return match normalized {
        'clang' { Toolchain(ClangToolchain{ compiler: compiler }) }
        else { Toolchain(GCCToolchain{ compiler: compiler }) }
    }
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
    cmd += ' -Wall -Wextra'
    
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
    
    // Add this library's dependencies (hardcode to filename form: -l:<name>.so)
    for library in lib_config.libraries {
        if library != '' {
            // strip any existing .so or lib/ prefix and ensure we request the explicit filename
            mut libfile := library
            if libfile.starts_with('lib/') {
                parts := libfile.split('/')
                libfile = parts[parts.len - 1]
            }
            if libfile.ends_with('.so') {
                libfile = libfile.replace('.so', '')
            }
            cmd += ' -l:${libfile}.so'
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
    // Use only the basename of the library to avoid duplicating path segments
    parts := library_name.split('/')
    base_name := if parts.len > 0 { parts[parts.len - 1] } else { library_name }
    mut lib_name := base_name
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
    
    // Add this tool's dependencies (shared libs) — hardcode to explicit .so filenames
    for library in tool_config.libraries {
        if library != '' {
            mut libfile := library
            if libfile.starts_with('lib/') {
                parts := libfile.split('/')
                libfile = parts[parts.len - 1]
            }
            if libfile.ends_with('.so') {
                libfile = libfile.replace('.so', '')
            }
            cmd += ' -l:${libfile}.so'
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
    cmd += ' -Wall -Wextra'
    
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