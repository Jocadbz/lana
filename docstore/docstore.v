module docstore

const snippet_project_structure_embedded = $embed_file('../docs/snippets/project_structure.md')
const snippet_quickstart_embedded = $embed_file('../docs/snippets/quickstart.md')
const template_main_embedded = $embed_file('../docs/templates/main.cpp.tpl')
const template_cli_embedded = $embed_file('../docs/templates/cli.cpp.tpl')
const template_example_tool_embedded = $embed_file('../docs/templates/example_tool.cpp.tpl')
const template_cli_header_embedded = $embed_file('../docs/templates/cli.h.tpl')
const template_gitignore_embedded = $embed_file('../docs/templates/gitignore.tpl')
const template_config_embedded = $embed_file('../docs/templates/config.ini.tpl')
const template_readme_embedded = $embed_file('../docs/templates/readme.md.tpl')
const guide_embedded = $embed_file('../docs/guide.md')
const help_text_embedded = $embed_file('../docs/help.txt')

pub fn snippet(name string) !string {
    return match name {
        'project_structure' { snippet_project_structure_embedded.to_string() }
        'quickstart' { snippet_quickstart_embedded.to_string() }
        else { error('snippet ${name} not found') }
    }
}

pub fn template(name string) !string {
    return match name {
        'main.cpp.tpl' { template_main_embedded.to_string() }
        'cli.cpp.tpl' { template_cli_embedded.to_string() }
        'example_tool.cpp.tpl' { template_example_tool_embedded.to_string() }
        'cli.h.tpl' { template_cli_header_embedded.to_string() }
        'gitignore.tpl' { template_gitignore_embedded.to_string() }
        '.gitignore.tpl' { template_gitignore_embedded.to_string() }
        'config.ini.tpl' { template_config_embedded.to_string() }
        'readme.md.tpl' { template_readme_embedded.to_string() }
        else { error('template ${name} not found') }
    }
}

pub fn guide() string {
    return guide_embedded.to_string()
}

pub fn help_text() string {
    return help_text_embedded.to_string()
}
