module config

import os

// BuildConfig holds the configuration for the project
pub struct BuildConfig {
    pub mut:
        project_name string
        src_dir      string
        build_dir    string
        bin_dir      string
        include_dirs []string
        libraries    []string
        cflags       []string
        ldflags      []string
        debug        bool
        optimize     bool
        verbose      bool
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
}

pub fn parse_args() !BuildConfig {
    mut build_config := default_config
    mut i := 2 // Skip program name and command
    
    for i < os.args.len {
        arg := os.args[i]
        match arg {
            '-d', '--debug' { build_config.debug = true; build_config.optimize = false }
            '-O', '--optimize' { build_config.optimize = true; build_config.debug = false }
            '-v', '--verbose' { build_config.verbose = true }
            '-o', '--output' { 
                if i + 1 < os.args.len { 
                    build_config.project_name = os.args[i + 1]
                    i++
                }
            }
            '-I' {
                if i + 1 < os.args.len { 
                    build_config.include_dirs << os.args[i + 1]
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
            else {
                if !arg.starts_with('-') {
                    build_config.project_name = arg
                }
            }
        }
        i++
    }
    return build_config
}

fn parse_config_file(filename string) !BuildConfig {
    content := os.read_file(filename) or { return error('Cannot read config file: ${filename}') }
    mut build_config := default_config
    lines := content.split_into_lines()
    
    for line in lines {
        if line.starts_with('#') || line.trim_space() == '' { continue }
        
        parts := line.split('=')
        if parts.len == 2 {
            key := parts[0].trim_space()
            value := parts[1].trim_space().trim('"\'')
            
            match key {
                'project_name' { build_config.project_name = value }
                'src_dir' { build_config.src_dir = value }
                'build_dir' { build_config.build_dir = value }
                'bin_dir' { build_config.bin_dir = value }
                'debug' { build_config.debug = value == 'true' }
                'optimize' { build_config.optimize = value == 'true' }
                'verbose' { build_config.verbose = value == 'true' }
                'include_dirs' { 
                    dirs := value.split(',')
                    for dir in dirs { build_config.include_dirs << dir.trim_space() }
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
                else {}
            }
        }
    }
    return build_config
}

// Utility function to build compiler command
pub fn build_compiler_command(source_file string, object_file string, build_config BuildConfig) string {
    mut cmd := 'g++ -c'
    
    // Add include directories
    for include_dir in build_config.include_dirs {
        cmd += ' -I${include_dir}'
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

// Utility function to build linker command
pub fn build_linker_command(object_files []string, executable string, build_config BuildConfig) string {
    mut cmd := 'g++'
    
    // Add debug flags for linking
    if build_config.debug {
        cmd += ' -g'
    }
    
    // Add object files
    for obj_file in object_files {
        cmd += ' ${obj_file}'
    }
    
    // Add libraries
    for library in build_config.libraries {
        cmd += ' -l${library}'
    }
    
    // Add custom LDFLAGS
    for flag in build_config.ldflags {
        cmd += ' ${flag}'
    }
    
    cmd += ' -o ${executable}'
    return cmd
}