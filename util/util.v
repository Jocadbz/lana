module util

import os

// shitty thing I need to pass around or else the compiler shits itself
pub struct ToolInfo {
pub:
    name       string
    output_dir string
}

// get_main_executable finds the main executable path given project info and tools list.
// It first looks for a tool matching the project name, then falls back to the
// first tool, and finally the legacy bin/<project_name> location.
pub fn get_main_executable(project_name string, bin_dir string, tools []ToolInfo) string {
    // First try to find a tool with the project name
    for tool in tools {
        if tool.name == project_name {
            return os.join_path(tool.output_dir, tool.name)
        }
    }

    // Then try the first tool
    if tools.len > 0 {
        return os.join_path(tools[0].output_dir, tools[0].name)
    }

    // Fallback to old behavior
    return os.join_path(bin_dir, project_name)
}

// find_source_files recursively finds all C++ source files (.cpp, .cc, .cxx) in a directory.
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
