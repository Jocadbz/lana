module initializer

import os
import docstore

fn render_template(template string, replacements map[string]string) string {
    mut output := template
    for key, value in replacements {
        placeholder := '{{${key}}}'
        output = output.replace(placeholder, value)
    }
    return output
}

pub fn init_project(project_name string) {
    println('Initializing C++ project: ${project_name}')
    
    dirs := [
        'src',
        'src/lib',
        'src/lib/net',
        'src/lib/game',
        'src/tools',
        'include',
        'build',
        'bin',
        'bin/lib',
        'bin/tools',
    ]
    for dir in dirs {
        full_path := os.join_path(project_name, dir)
        os.mkdir_all(full_path) or {
            println('Warning: Failed to create ${full_path}: ${err}')
        }
    }

    replacements := {
        'project_name': project_name
    }

    quickstart := docstore.snippet('quickstart') or { 'See docs/snippets/quickstart.md in the Lana repo.' }
    structure := docstore.snippet('project_structure') or { 'See docs/snippets/project_structure.md in the Lana repo.' }

    write_template(project_name, 'src/main.cpp', 'main.cpp.tpl', replacements)
    write_template(project_name, 'src/lib/cli.cpp', 'cli.cpp.tpl', replacements)
    write_template(project_name, 'src/tools/example_tool.cpp', 'example_tool.cpp.tpl', replacements)
    write_template(project_name, '.gitignore', 'gitignore.tpl', replacements)
    write_template(project_name, 'config.ini', 'config.ini.tpl', replacements)

    mut readme_map := replacements.clone()
    readme_map['quickstart'] = quickstart.trim_space()
    readme_map['project_structure'] = structure.trim_space()
    write_template_with_map(project_name, 'README.md', 'readme.md.tpl', readme_map)

    write_template(project_name, 'include/cli.h', 'cli.h.tpl', replacements)

    println('Project initialized successfully!')
    println('Created directory structure and template files')
    println('\nNext steps:')
    println('  cd ${project_name}')
    println('  lana build')
    println('  lana run')
    println('  ./bin/tools/example_tool')
    println('\nDocs and templates originate from docs/ in the Lana repo. Update them once to affect README/help/init output everywhere.')
}

fn write_template(root string, relative_path string, template_name string, replacements map[string]string) {
    write_template_with_map(root, relative_path, template_name, replacements)
}

fn write_template_with_map(root string, relative_path string, template_name string, replacements map[string]string) {
    content := docstore.template(template_name) or {
        println('Warning: template ${template_name} missing (${err})')
        return
    }
    rendered := render_template(content, replacements)
    os.write_file(os.join_path(root, relative_path), rendered) or {
        println('Warning: failed to write ${relative_path}: ${err}')
    }
}