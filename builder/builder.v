module builder

import os
import config
import deps

pub fn build(mut build_config config.BuildConfig) ! {
    println('Building ${build_config.project_name}...')
    
    // Create directories
    os.mkdir_all(build_config.build_dir) or { return error('Failed to create build directory') }
    os.mkdir_all(build_config.bin_dir) or { return error('Failed to create bin directory') }
    
    // Find all source files
    source_files := find_source_files(build_config.src_dir) or { 
        return error('Failed to find source files in ${build_config.src_dir}')
    }
    
    if source_files.len == 0 {
        return error('No source files found in ${build_config.src_dir}')
    }
    
    mut object_files := []string{}
    
    // Compile each source file
    for src_file in source_files {
        obj_file := src_file.replace(build_config.src_dir, build_config.build_dir).replace('.cpp', '.o')
        
        // Create object directory if needed
        obj_dir := os.dir(obj_file)
        os.mkdir_all(obj_dir) or { return error('Failed to create object directory: ${obj_dir}') }
        
        // Check if we need to recompile
        if needs_recompile(src_file, obj_file) {
            println('Compiling ${src_file}...')
            object_files << compile_file(src_file, obj_file, build_config) or { 
                return error('Failed to compile ${src_file}')
            }
        } else {
            if build_config.verbose {
                println('Using cached ${obj_file}')
            }
            object_files << obj_file
        }
    }
    
    // Link object files
    executable := os.join_path(build_config.bin_dir, build_config.project_name)
    println('Linking ${executable}...')
    link_objects(object_files, executable, build_config) or { return error('Failed to link executable') }
    
    println('Build completed successfully!')
}

pub fn clean(build_config config.BuildConfig) {
    println('Cleaning build files...')
    
    // Remove build directory
    if os.is_dir(build_config.build_dir) {
        os.rmdir_all(build_config.build_dir) or {
            println('Warning: Failed to remove ${build_config.build_dir}: ${err}')
        }
        println('Removed ${build_config.build_dir}')
    }
    
    // Remove executable
    executable := os.join_path(build_config.bin_dir, build_config.project_name)
    if os.is_file(executable) {
        os.rm(executable) or {
            println('Warning: Failed to remove ${executable}: ${err}')
        }
        println('Removed ${executable}')
    }
    
    println('Clean completed!')
}

fn find_source_files(dir string) ![]string {
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

fn needs_recompile(source_file string, object_file string) bool {
    src_mtime := os.file_last_mod_unix(source_file)
    obj_mtime := if os.is_file(object_file) {
        os.file_last_mod_unix(object_file)
    } else {
        0
    }
    
    // Source is newer than object
    if src_mtime > obj_mtime {
        return true
    }
    
    // Check dependencies
    dependencies := deps.extract_dependencies(source_file) or { return true }
    for dep in dependencies {
        if !os.is_file(dep) {
            return true
        }
        dep_mtime := os.file_last_mod_unix(dep)
        if dep_mtime > obj_mtime {
            return true
        }
    }
    
    return false
}

fn compile_file(source_file string, object_file string, build_config config.BuildConfig) !string {
    cmd := config.build_compiler_command(source_file, object_file, build_config)
    
    if build_config.verbose {
        println('Compile command: ${cmd}')
    }
    
    res := os.execute(cmd)
    if res.exit_code != 0 {
        return error('Compilation failed with exit code ${res.exit_code}:\n${res.output}')
    }
    
    // Generate dependency file
    dep_file := object_file.replace('.o', '.d')
    deps.generate_dependency_file(source_file, object_file, dep_file)
    
    return object_file
}

fn link_objects(object_files []string, executable string, build_config config.BuildConfig) ! {
    cmd := config.build_linker_command(object_files, executable, build_config)
    
    if build_config.verbose {
        println('Link command: ${cmd}')
    }
    
    res := os.execute(cmd)
    if res.exit_code != 0 {
        return error('Linking failed with exit code ${res.exit_code}:\n${res.output}')
    }
}