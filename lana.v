module main

import os
import config
import builder
import runner
import initializer
import help

fn main() {
    mut config_data := config.parse_args() or { config.default_config }
    
    if os.args.len < 2 {
        help.show_help()
        return
    }
    
    match os.args[1] {
        'build' { builder.build(mut config_data) or { return } }
        'clean' { builder.clean(config_data) }
        'run' { 
            builder.build(mut config_data) or { return }
            runner.run_executable(config_data) 
        }
        'init' { initializer.init_project(os.args[2] or { 'myproject' }) }
        else { help.show_help() }
    }
}