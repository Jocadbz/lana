module runner

import os
import config
import util

pub fn run_executable(build_config config.BuildConfig) {
    tools := build_config.tools.map(util.ToolInfo{
        name: it.name
        output_dir: it.output_dir
    })
    main_executable := util.get_main_executable(build_config.project_name, build_config.bin_dir, tools)

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