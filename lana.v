module main

import os
import config
import builder
import runner
import initializer
import deps
import help
import util

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
		'clean' {
			builder.clean(config_data)
		}
		'run' {
			// For run, try to build first, then run the main tool
			builder.build(mut config_data) or {
				eprintln('Build failed: ${err}')
				exit(1)
			}

			// Find and run the main executable (first tool or project_name)
			tools := config_data.tools.map(util.ToolInfo{
				name: it.name
				output_dir: it.output_dir
			})
			main_executable := util.get_main_executable(config_data.project_name, config_data.bin_dir, tools)
			if main_executable != '' && os.is_file(main_executable) {
				runner.run_executable(config_data)
			} else {
				println('No main executable found to run')
			}
		}
		'init' {
			initializer.init_project(os.args[2] or { 'myproject' })
		}
		'setup' {
			deps.fetch_dependencies(config_data) or {
				eprintln('Failed to fetch dependencies: ${err}')
				exit(1)
			}
		}
		else {
			help.show_help()
		}
	}
}
