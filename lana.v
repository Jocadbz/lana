module main

import os
import config
import builder
import runner
import initializer
import help

const (
    // For runner compatibility
    bin_dir = 'bin'
    tools_dir = 'bin/tools'
)

fn main() {
    mut config_data := config.parse_args() or { config.default_config }
    
    if os.args.len < 2 {
        help.show_help()
        return
    }
    
    match os.args[1] {
        'build' { 
            builder.build(mut config_data) or { 
                eprintln('Build failed: ${err}')
                exit(1)
            }
        }
        'clean' { builder.clean(config_data) }
        'run' { 
            // For run, try to build first, then run the main tool
            builder.build(mut config_data) or { 
                eprintln('Build failed: ${err}')
                exit(1)
            }
            
            // Find and run the main executable (first tool or project_name)
            main_executable := get_main_executable(config_data)
            if main_executable != '' && os.is_file(main_executable) {
                runner.run_executable(config_data)
            } else {
                println('No main executable found to run')
            }
        }
        'init' { initializer.init_project(os.args[2] or { 'myproject' }) }
        else { help.show_help() }
    }
}

fn get_main_executable(build_config config.BuildConfig) string {
    // First try to find a tool with the project name
    for tool_config in build_config.tools {
        if tool_config.name == build_config.project_name {
            return os.join_path(tool_config.output_dir, tool_config.name)
        }
    }
    
    // Then try the first tool
    if build_config.tools.len > 0 {
        tool_config := build_config.tools[0]
        return os.join_path(tool_config.output_dir, tool_config.name)
    }
    
    // Fallback to old behavior
    return os.join_path(build_config.bin_dir, build_config.project_name)
}