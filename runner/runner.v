module runner

import os
import config

pub fn run_executable(build_config config.BuildConfig) {
    executable := os.join_path(build_config.bin_dir, build_config.project_name)
    
    if !os.is_file(executable) {
        println('Executable not found: ${executable}')
        println('Please run "lana build" first')
        return
    }
    
    println('Running ${executable}...')
    res := os.execute('${executable}')
    if res.exit_code != 0 {
        println('Failed to execute: ${res.output}')
        return
    }
    
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