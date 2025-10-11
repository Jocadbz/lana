module builder

import os
import config
import deps
import runtime

// BuildTarget represents a build target (shared lib or tool)
pub enum BuildTarget {
    shared_lib
    tool
}

// BuildTargetInfo holds common information for all build targets
pub struct BuildTargetInfo {
    name       string
    sources    []string
    object_dir string
    output_dir string
    debug      bool
    optimize   bool
    verbose    bool
    include_dirs []string
    cflags     []string
    ldflags    []string
    libraries  []string
}

struct CompileTask {
    source string
    obj string
    target_config config.TargetConfig
}

struct CompileResult {
    obj string
    err string
}

fn run_compile_tasks(tasks []CompileTask, build_config config.BuildConfig) ![]string {
    mut object_files := []string{}
    if tasks.len == 0 {
        return object_files
    }

    // If parallel compilation disabled, compile sequentially
    if !build_config.parallel_compilation {
        for task in tasks {
            object := compile_file(task.source, task.obj, build_config, task.target_config) or { 
                return error('Failed to compile ${task.source}: ${err}')
            }
            object_files << object
        }
        return object_files
    }

    // Bounded worker pool: spawn up to N workers where N = min(task_count, nr_cpus())
    mut workers := runtime.nr_cpus()
    if workers < 1 {
        workers = 1
    }
    if workers > tasks.len {
        workers = tasks.len
    }

    tasks_ch := chan CompileTask{cap: tasks.len}
    res_ch := chan CompileResult{cap: tasks.len}

    // Worker goroutines
    for _ in 0 .. workers {
        go fn (ch chan CompileTask, res chan CompileResult, bc config.BuildConfig) {
            for {
                t := <-ch
                // sentinel task: empty source signals worker to exit
                if t.source == '' {
                    break
                }
                object := compile_file(t.source, t.obj, bc, t.target_config) or {
                    res <- CompileResult{obj: '', err: err.msg()}
                    continue
                }
                res <- CompileResult{obj: object, err: ''}
            }
        }(tasks_ch, res_ch, build_config)
    }

    // Send tasks
    for t in tasks {
        tasks_ch <- t
    }

    // Send sentinel tasks to tell workers to exit
    for _ in 0 .. workers {
        tasks_ch <- CompileTask{}
    }

    // Collect results
    for _ in 0 .. tasks.len {
        r := <-res_ch
        if r.err != '' {
            return error('Compilation failed: ${r.err}')
        }
        object_files << r.obj
    }

    return object_files
}

pub fn build(mut build_config config.BuildConfig) ! {
    println('Building ${build_config.project_name}...')
    
    // Create directories
    os.mkdir_all(build_config.build_dir) or { return error('Failed to create build directory') }
    os.mkdir_all(build_config.bin_dir) or { return error('Failed to create bin directory') }
    os.mkdir_all('${build_config.bin_dir}/lib') or { return error('Failed to create lib directory') }
    os.mkdir_all('${build_config.bin_dir}/tools') or { return error('Failed to create tools directory') }
    if build_config.shaders_dir != '' && build_config.shaders_dir != 'bin/shaders' {
        os.mkdir_all(build_config.shaders_dir) or { return error('Failed to create shaders directory') }
    }
    
    // Auto-discover sources if not specified
    auto_discover_sources(mut build_config)
    
    // Build shared libraries first (from config)
    mut shared_libs_built := []string{}
    for mut lib_config in build_config.shared_libs {
        if lib_config.sources.len == 0 {
            if build_config.verbose {
                println('Skipping empty shared library: ${lib_config.name}')
            }
            continue
        }
        
        println('Building shared library: ${lib_config.name}')
        build_shared_library(mut lib_config, build_config) or {
            return error('Failed to build shared library ${lib_config.name}: ${err}')
        }
        shared_libs_built << lib_config.name
        if build_config.verbose {
            println('Built shared library: ${lib_config.name}')
        }
    }
    
    // Build targets from build directives
    build_from_directives(mut build_config, mut shared_libs_built)!
    
    // Build tools/executables from config
    for mut tool_config in build_config.tools {
        if tool_config.sources.len == 0 {
            if build_config.verbose {
                println('Skipping empty tool: ${tool_config.name}')
            }
            continue
        }
        
        println('Building tool: ${tool_config.name}')
        build_tool(mut tool_config, build_config) or {
            return error('Failed to build tool ${tool_config.name}: ${err}')
        }
        if build_config.verbose {
            println('Built tool: ${tool_config.name}')
        }
    }
    
    // Build shaders if configured and directory exists
    if build_config.shaders_dir != '' {
        compile_shaders(build_config) or { 
            if !build_config.verbose {
                println('Warning: Failed to compile shaders: ${err}')
            }
        }
    }
    
    println('Build completed successfully!')
}

// Build targets based on build directives from source files
fn build_from_directives(mut build_config config.BuildConfig, mut shared_libs_built []string) ! {
    // Build a dependency graph from directives
    mut dep_graph := map[string]config.BuildDirective{}
    mut build_order := []string{}
    mut built_units := []string{}
    
    // Initialize graph with all directives
    for directive in build_config.build_directives {
        dep_graph[directive.unit_name] = directive
    }
    
    // Topological sort to determine build order
    for unit_name, directive in dep_graph {
        if unit_name in built_units {
            continue
        }
        build_unit_recursive(unit_name, dep_graph, mut build_order, mut built_units, mut build_config, shared_libs_built)!
    }
    
    // Build units in determined order
    for unit_name in build_order {
        directive := dep_graph[unit_name]
        
        println('Building unit: ${unit_name}')
        
        // Find source file for this unit
        mut source_file := ''
        for src_path in directive.unit_name.split('/') {
            source_file = os.join_path(build_config.src_dir, src_path + '.cpp')
            if os.is_file(source_file) {
                break
            }
            source_file = os.join_path(build_config.src_dir, src_path + '.cc')
            if os.is_file(source_file) {
                break
            }
            source_file = os.join_path(build_config.src_dir, src_path + '.cxx')
            if os.is_file(source_file) {
                break
            }
        }
        
        if source_file == '' {
            if build_config.verbose {
                println('Warning: Source file not found for unit ${unit_name}')
            }
            continue
        }
        
        // Create object directory
        object_dir := os.join_path(build_config.build_dir, directive.unit_name)
        os.mkdir_all(object_dir) or { return error('Failed to create object directory: ${object_dir}') }
        
        obj_file := get_object_file(source_file, object_dir)
        
        // Compile source file
        if needs_recompile(source_file, obj_file) {
            println('Compiling ${unit_name}: ${source_file}...')
            target_config := config.TargetConfig(config.ToolConfig{
                name: unit_name
                sources: [source_file]
                debug: build_config.debug
                optimize: build_config.optimize
                verbose: build_config.verbose
                cflags: directive.cflags
                ldflags: directive.ldflags
            })
            compile_file(source_file, obj_file, build_config, target_config) or { 
                return error('Failed to compile ${source_file} for ${unit_name}')
            }
        } else {
            if build_config.verbose {
                println('Using cached ${obj_file} for ${unit_name}')
            }
        }
        
        // Link executable or shared library
        if directive.is_shared {
            // Link shared library
            lib_output := os.join_path(build_config.bin_dir, 'lib', directive.unit_name)
            println('Linking shared library: ${lib_output}')
            link_shared_library([obj_file], directive.unit_name, lib_output, build_config, config.SharedLibConfig{
                name: directive.unit_name
                libraries: directive.link_libs
                debug: build_config.debug
                optimize: build_config.optimize
                verbose: build_config.verbose
                ldflags: directive.ldflags
            }) or { 
                return error('Failed to link shared library ${unit_name}')
            }
            shared_libs_built << directive.unit_name
        } else {
            // Link executable
            executable := os.join_path(build_config.bin_dir, directive.output_path)
            println('Linking executable: ${executable}')
            link_tool([obj_file], executable, build_config, config.ToolConfig{
                name: directive.unit_name
                libraries: directive.link_libs
                debug: build_config.debug
                optimize: build_config.optimize
                verbose: build_config.verbose
                ldflags: directive.ldflags
            }) or { 
                return error('Failed to link executable ${unit_name}')
            }
        }
        
        if build_config.verbose {
            println('Successfully built unit: ${unit_name}')
        }
    }
}

// Recursively build unit and its dependencies
fn build_unit_recursive(unit_name string, dep_graph map[string]config.BuildDirective, mut build_order []string, mut built_units []string, mut build_config config.BuildConfig, shared_libs_built []string) ! {
    if unit_name in built_units {
        return
    }
    
    // Build dependencies first
    directive := dep_graph[unit_name]
    for dep_unit in directive.depends_units {
        if dep_unit in dep_graph {
            build_unit_recursive(dep_unit, dep_graph, mut build_order, mut built_units, mut build_config, shared_libs_built)!
        } else if !dep_unit.ends_with('.so') && !dep_unit.contains('.') {
            // Look for library in shared_libs_built
            lib_name := 'lib/${dep_unit}'
            if lib_name !in shared_libs_built {
                if build_config.verbose {
                    println('Warning: Dependency ${dep_unit} not found for ${unit_name}')
                }
            }
        }
    }
    
    build_order << unit_name
    built_units << unit_name
}

fn auto_discover_sources(mut build_config config.BuildConfig) {
    // Auto-discover shared library sources
    for mut lib_config in build_config.shared_libs {
        if lib_config.sources.len == 0 {
            // Look for sources in src/lib/<lib_name>/
            lib_src_dir := os.join_path('src', 'lib', lib_config.name)
            if os.is_dir(lib_src_dir) {
                lib_sources := find_source_files(lib_src_dir) or { []string{} }
                lib_config.sources = lib_sources
                if build_config.verbose && lib_sources.len > 0 {
                    println('Auto-discovered ${lib_sources.len} source files for shared lib ${lib_config.name}')
                }
            }
        }
    }
    
    // Auto-discover tool sources
    for mut tool_config in build_config.tools {
        if tool_config.sources.len == 0 {
            // Look for sources in src/tools/<tool_name>/
            tool_src_dir := os.join_path('src', 'tools', tool_config.name)
            if os.is_dir(tool_src_dir) {
                tool_sources := find_source_files(tool_src_dir) or { []string{} }
                if tool_sources.len > 0 {
                    tool_config.sources = tool_sources
                } else {
                    // Fallback: look for main.cpp or tool_name.cpp in src/
                    fallback_sources := [
                        os.join_path('src', '${tool_config.name}.cpp'),
                        os.join_path('src', 'main.cpp')
                    ]
                    for fallback in fallback_sources {
                        if os.is_file(fallback) {
                            tool_config.sources << fallback
                            break
                        }
                    }
                }
                if build_config.verbose && tool_config.sources.len > 0 {
                    println('Auto-discovered ${tool_config.sources.len} source files for tool ${tool_config.name}')
                }
            }
        }
    }
    
    // If still no sources for default tool, use all files in src/
    if build_config.tools.len > 0 && build_config.tools[0].sources.len == 0 {
        mut default_tool := &build_config.tools[0]
        if default_tool.name == build_config.project_name {
            all_sources := find_source_files(build_config.src_dir) or { []string{} }
            if all_sources.len > 0 {
                default_tool.sources = all_sources
                if build_config.verbose {
                    println('Auto-discovered ${all_sources.len} source files for main project')
                }
            }
        }
    }
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
    
    // Remove bin directories
    dirs_to_clean := ['lib', 'tools']
    for dir in dirs_to_clean {
        full_dir := os.join_path(build_config.bin_dir, dir)
        if os.is_dir(full_dir) {
            os.rmdir_all(full_dir) or {
                println('Warning: Failed to remove ${full_dir}: ${err}')
            }
            println('Removed ${full_dir}')
        }
    }
    
    // Remove shaders directory if it exists
    shaders_dir := if build_config.shaders_dir.starts_with('bin/') {
        os.join_path(build_config.bin_dir, build_config.shaders_dir[4..])
    } else {
        build_config.shaders_dir
    }
    if os.is_dir(shaders_dir) {
        os.rmdir_all(shaders_dir) or {
            println('Warning: Failed to remove ${shaders_dir}: ${err}')
        }
        println('Removed ${shaders_dir}')
    }
    
    // Remove main executable if it exists (backward compatibility)
    main_exe := os.join_path(build_config.bin_dir, build_config.project_name)
    if os.is_file(main_exe) {
        os.rm(main_exe) or {
            println('Warning: Failed to remove ${main_exe}: ${err}')
        }
        println('Removed ${main_exe}')
    }
    
    println('Clean completed!')
}

fn build_shared_library(mut lib_config config.SharedLibConfig, build_config config.BuildConfig) ! {
    if lib_config.sources.len == 0 {
        if build_config.verbose {
            println('No sources specified for shared library ${lib_config.name}, skipping')
        }
        return
    }
    
    // Create output directory
    os.mkdir_all(lib_config.output_dir) or { return error('Failed to create shared lib directory: ${lib_config.output_dir}') }
    
    mut object_files := []string{}
    mut object_dir := os.join_path(build_config.build_dir, lib_config.name)
    os.mkdir_all(object_dir) or { return error('Failed to create object directory: ${object_dir}') }
    
    // Compile each source file (possibly in parallel)
    mut compile_tasks := []CompileTask{}
    for src_file in lib_config.sources {
        if !os.is_file(src_file) {
            if build_config.verbose {
                println('Warning: Source file not found: ${src_file}')
            }
            continue
        }

        obj_file := get_object_file(src_file, object_dir)

        // Create object directory if needed
        obj_path := os.dir(obj_file)
        os.mkdir_all(obj_path) or { return error('Failed to create object directory: ${obj_path}') }

        if needs_recompile(src_file, obj_file) {
            println('Compiling ${lib_config.name}: ${src_file}...')
            lib_target_config := config.TargetConfig(lib_config)
            compile_tasks << CompileTask{source: src_file, obj: obj_file, target_config: lib_target_config}
        } else {
            if lib_config.verbose {
                println('Using cached ${obj_file} for ${lib_config.name}')
            }
            object_files << obj_file
        }
    }

    // Run compile tasks (parallel if enabled)
    if compile_tasks.len > 0 {
        compiled := run_compile_tasks(compile_tasks, build_config) or { return err }
        object_files << compiled
    }
    
    if object_files.len == 0 {
        return error('No object files generated for shared library ${lib_config.name}')
    }
    
    // Link shared library
    lib_output := os.join_path(lib_config.output_dir, lib_config.name)
    println('Linking shared library: ${lib_output}')
    link_shared_library(object_files, lib_config.name, lib_output, build_config, lib_config) or { 
        return error('Failed to link shared library ${lib_config.name}')
    }
    
    if build_config.verbose {
        println('Successfully built shared library: ${lib_config.name}')
    }
}

fn build_tool(mut tool_config config.ToolConfig, build_config config.BuildConfig) ! {
    if tool_config.sources.len == 0 {
        if build_config.verbose {
            println('No sources specified for tool ${tool_config.name}, skipping')
        }
        return
    }
    
    // Create output directory
    os.mkdir_all(tool_config.output_dir) or { return error('Failed to create tool directory: ${tool_config.output_dir}') }
    
    mut object_files := []string{}
    mut object_dir := os.join_path(build_config.build_dir, tool_config.name)
    os.mkdir_all(object_dir) or { return error('Failed to create object directory: ${object_dir}') }
    
    // Compile each source file (possibly in parallel)
    mut compile_tasks := []CompileTask{}
    for src_file in tool_config.sources {
        if !os.is_file(src_file) {
            if build_config.verbose {
                println('Warning: Source file not found: ${src_file}')
            }
            continue
        }

        obj_file := get_object_file(src_file, object_dir)

        // Create object directory if needed
        obj_path := os.dir(obj_file)
        os.mkdir_all(obj_path) or { return error('Failed to create object directory: ${obj_path}') }

        if needs_recompile(src_file, obj_file) {
            println('Compiling ${tool_config.name}: ${src_file}...')
            tool_target_config := config.TargetConfig(tool_config)
            compile_tasks << CompileTask{source: src_file, obj: obj_file, target_config: tool_target_config}
        } else {
            if tool_config.verbose {
                println('Using cached ${obj_file} for ${tool_config.name}')
            }
            object_files << obj_file
        }
    }

    // Run compile tasks (parallel if enabled)
    if compile_tasks.len > 0 {
        compiled := run_compile_tasks(compile_tasks, build_config) or { return err }
        object_files << compiled
    }
    
    if object_files.len == 0 {
        return error('No object files generated for tool ${tool_config.name}')
    }
    
    // Link executable
    executable := os.join_path(tool_config.output_dir, tool_config.name)
    println('Linking tool: ${executable}')
    link_tool(object_files, executable, build_config, tool_config) or { 
        return error('Failed to link tool ${tool_config.name}')
    }
    
    if build_config.verbose {
        println('Successfully built tool: ${tool_config.name}')
    }
}

// Helper function to get target verbose setting
fn get_target_verbose(target_config config.TargetConfig) bool {
    mut verbose := false
    match target_config {
        config.SharedLibConfig {
            verbose = target_config.verbose
        }
        config.ToolConfig {
            verbose = target_config.verbose
        }
    }
    return verbose
}

fn compile_file(source_file string, object_file string, build_config config.BuildConfig, target_config config.TargetConfig) !string {
    cmd := config.build_shared_compiler_command(source_file, object_file, build_config, target_config)
    
    target_verbose := get_target_verbose(target_config)
    
    if target_verbose {
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

fn link_shared_library(object_files []string, library_name string, output_path string, build_config config.BuildConfig, lib_config config.SharedLibConfig) ! {
    cmd := config.build_shared_linker_command(object_files, library_name, output_path, build_config, lib_config)
    
    if lib_config.verbose {
        println('Shared lib link command: ${cmd}')
    }
    
    res := os.execute(cmd)
    if res.exit_code != 0 {
        return error('Shared library linking failed with exit code ${res.exit_code}:\n${res.output}')
    }
}

fn link_tool(object_files []string, executable string, build_config config.BuildConfig, tool_config config.ToolConfig) ! {
    cmd := config.build_tool_linker_command(object_files, executable, build_config, tool_config)
    
    if tool_config.verbose {
        println('Tool link command: ${cmd}')
    }
    
    res := os.execute(cmd)
    if res.exit_code != 0 {
        return error('Tool linking failed with exit code ${res.exit_code}:\n${res.output}')
    }
}

fn compile_shaders(build_config config.BuildConfig) ! {
    shaders_src_dir := 'src/shaders'
    if !os.is_dir(shaders_src_dir) {
        if build_config.verbose {
            println('No shaders directory found, skipping shader compilation')
        }
        return
    }
    
    println('Compiling shaders...')
    
    // Find glslc compiler
    glslc_path := find_glslc() or { 
        println('Warning: glslc compiler not found, skipping shader compilation')
        return 
    }
    
    // Get shaders directory
    shaders_out_dir := if build_config.shaders_dir.starts_with('bin/') {
        os.join_path(build_config.bin_dir, build_config.shaders_dir[4..])
    } else {
        build_config.shaders_dir
    }
    
    os.mkdir_all(shaders_out_dir) or { return error('Failed to create shaders output directory') }
    
    // List all shader files
    shader_files := os.ls(shaders_src_dir) or { return error('Failed to list shaders directory') }
    mut shader_count := 0
    mut success_count := 0
    
    // Compile vertex shaders (.vsh)
    for shader in shader_files {
        if !shader.ends_with('.vsh') {
            continue
        }
        
        shader_count++
        src_path := os.join_path(shaders_src_dir, shader)
        output_name := shader.replace('.vsh', '.vsh.spv')
        output_path := os.join_path(shaders_out_dir, output_name)
        
        cmd := '${glslc_path} -o ${output_path} -fshader-stage=vertex ${src_path}'
        println('Compiling vertex shader: ${shader}')
        
        if build_config.verbose {
            println('Shader compile command: ${cmd}')
        }
        
        res := os.execute(cmd)
        if res.exit_code != 0 {
            println('Error compiling ${shader}: ${res.output}')
        } else {
            success_count++
            if build_config.verbose {
                println('Compiled: ${shader} -> ${output_path}')
            }
        }
    }
    
    // Compile fragment shaders (.fsh)
    for shader in shader_files {
        if !shader.ends_with('.fsh') {
            continue
        }
        
        shader_count++
        src_path := os.join_path(shaders_src_dir, shader)
        output_name := shader.replace('.fsh', '.fsh.spv')
        output_path := os.join_path(shaders_out_dir, output_name)
        
        cmd := '${glslc_path} -o ${output_path} -fshader-stage=fragment ${src_path}'
        println('Compiling fragment shader: ${shader}')
        
        if build_config.verbose {
            println('Shader compile command: ${cmd}')
        }
        
        res := os.execute(cmd)
        if res.exit_code != 0 {
            println('Error compiling ${shader}: ${res.output}')
        } else {
            success_count++
            if build_config.verbose {
                println('Compiled: ${shader} -> ${output_path}')
            }
        }
    }
    
    if shader_count == 0 {
        println('No shaders found to compile')
    } else {
        println('Shader compilation complete: ${success_count}/${shader_count} successful')
    }
}

fn find_glslc() !string {
    // Check common locations
    paths := [
        '/usr/bin/glslc',
        '/usr/local/bin/glslc',
        '/opt/homebrew/bin/glslc' // macOS
    ]
    
    for path in paths {
        if os.is_file(path) {
            return path
        }
    }
    
    // Try PATH using os.which
    glslc_path := os.find_abs_path_of_executable('glslc') or { panic(err) }
    if glslc_path != '' {
        return glslc_path
    }
    
    return error('glslc not found. Install Vulkan SDK or shaderc')
}

fn get_object_file(source_file string, object_dir string) string {
    // Replace src_dir with object_dir and change extension to .o
    mut obj_file := source_file.replace('src', object_dir)
    obj_file = obj_file.replace('.cpp', '.o').replace('.cc', '.o').replace('.cxx', '.o')
    return obj_file
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