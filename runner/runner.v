module runner

import os
import config

pub fn run_executable(build_config config.BuildConfig) {
    main_executable := get_main_executable(build_config)
    
    if !os.is_file(main_executable) {
        println('Main executable not found: ${main_executable}')
        println('Please run "lana build" first')
        return
    }
    
    println('Running ${main_executable}...')
    res := os.execute('${main_executable}')
    
    if res.exit_code == 0 {
        println('Execution completed successfully!')
        if res.output.len > 0 {
            println(res.output)
        }
    } else {
        println('Execution failed with exit code ${res.exit_code}')
        if res.output.len > 0 {
            println('Output:\n${res.output}')
        }
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