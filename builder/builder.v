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
    // Run build flow and ensure that if any error occurs we print its message
    println('Building ${build_config.project_name}...')

    run_build := fn (mut build_config config.BuildConfig) ! {
        // Create directories
        os.mkdir_all(build_config.build_dir) or { return error('Failed to create build directory') }
        os.mkdir_all(build_config.bin_dir) or { return error('Failed to create bin directory') }
        os.mkdir_all('${build_config.bin_dir}/lib') or { return error('Failed to create lib directory') }
        os.mkdir_all('${build_config.bin_dir}/tools') or { return error('Failed to create tools directory') }

        // Auto-discover sources if not specified
        auto_discover_sources(mut build_config)

        // Build shared libraries first (from config)
        mut shared_libs_built := []string{}
        for mut lib_config in build_config.shared_libs {
            if lib_config.sources.len == 0 {
                if build_config.debug || build_config.verbose || lib_config.debug || lib_config.verbose {
                    println('Skipping empty shared library: ${lib_config.name}')
                }
                continue
            }

            if build_config.debug || build_config.verbose || lib_config.debug || lib_config.verbose {
                println('Building shared library: ${lib_config.name}')
            }
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
                if build_config.debug || build_config.verbose || tool_config.debug || tool_config.verbose {
                    println('Skipping empty tool: ${tool_config.name}')
                }
                continue
            }

            if build_config.debug || build_config.verbose || tool_config.debug || tool_config.verbose {
                println('Building tool: ${tool_config.name}')
            }
            build_tool(mut tool_config, build_config) or {
                return error('Failed to build tool ${tool_config.name}: ${err}')
            }
            if build_config.verbose {
                println('Built tool: ${tool_config.name}')
            }
        }

        println('Build completed successfully!')
        return
    }

    // Execute build and show full error output if something fails
    run_build(mut build_config) or {
        // Print error message to help debugging
        println('Build failed: ${err}')
        return err
    }
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
        
        if build_config.debug || build_config.verbose {
            println('Building unit: ${unit_name}')
        }
        
        // Find source file for this unit
        mut source_file := ''
    // First try the full unit path (e.g., src/lib/file.cpp)
    mut candidate := os.join_path(build_config.src_dir, directive.unit_name + '.cpp')
        if os.is_file(candidate) {
            source_file = candidate
        } else {
            candidate = os.join_path(build_config.src_dir, directive.unit_name + '.cc')
            if os.is_file(candidate) {
                source_file = candidate
            } else {
                candidate = os.join_path(build_config.src_dir, directive.unit_name + '.cxx')
                if os.is_file(candidate) {
                    source_file = candidate
                }
            }
        }

        // Fallback: try only the basename (e.g., src/file.cpp) for legacy layouts
        if source_file == '' {
            parts := directive.unit_name.split('/')
            base := if parts.len > 0 { parts[parts.len - 1] } else { directive.unit_name }
            candidate = os.join_path(build_config.src_dir, base + '.cpp')
            if os.is_file(candidate) {
                source_file = candidate
            } else {
                candidate = os.join_path(build_config.src_dir, base + '.cc')
                if os.is_file(candidate) {
                    source_file = candidate
                } else {
                    candidate = os.join_path(build_config.src_dir, base + '.cxx')
                    if os.is_file(candidate) {
                        source_file = candidate
                    }
                }
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
            if build_config.debug || build_config.verbose {
                println('Compiling ${unit_name}: ${source_file}...')
            }
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
            // place shared libs directly under bin/lib (not nested by unit name)
            lib_output_dir := os.join_path(build_config.bin_dir, 'lib')
            // ensure output directory exists
            os.mkdir_all(lib_output_dir) or { return error('Failed to create shared lib output directory: ${lib_output_dir}') }
            if build_config.debug || build_config.verbose {
                println('Linking shared library: ${lib_output_dir}/${directive.unit_name.split('/').last()}.so')
            }
            if build_config.verbose {
                // show contents of lib dir for debugging
                files := os.ls(lib_output_dir) or { []string{} }
                println('Contents of ${lib_output_dir}: ${files}')
            }
            link_shared_library([obj_file], directive.unit_name, lib_output_dir, build_config, config.SharedLibConfig{
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
            if build_config.debug || build_config.verbose {
                println('Linking executable: ${executable}')
            }
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
        if build_config.debug || build_config.verbose || lib_config.debug || lib_config.verbose {
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
            if build_config.debug || build_config.verbose || lib_config.debug || lib_config.verbose {
                println('Compiling ${lib_config.name}: ${src_file}...')
            }
            lib_target_config := config.TargetConfig(lib_config)
            // show compile command if verbose
            if lib_config.verbose || build_config.verbose {
                cmd_preview := config.build_shared_compiler_command(src_file, obj_file, build_config, lib_target_config)
                println('Compile command (preview): ${cmd_preview}')
            }
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
    // place shared libs directly under the configured output dir
    lib_output_dir := lib_config.output_dir
    // ensure output directory exists
    os.mkdir_all(lib_output_dir) or { return error('Failed to create shared lib output directory: ${lib_output_dir}') }
    if build_config.debug || build_config.verbose || lib_config.debug || lib_config.verbose {
        println('Linking shared library: ${lib_output_dir}/${lib_config.name.split('/').last()}.so')
    }
    link_shared_library(object_files, lib_config.name, lib_output_dir, build_config, lib_config) or { 
        return error('Failed to link shared library ${lib_config.name}')
    }
    
    if build_config.verbose {
        println('Successfully built shared library: ${lib_config.name}')
    }
}

fn build_tool(mut tool_config config.ToolConfig, build_config config.BuildConfig) ! {
    if tool_config.sources.len == 0 {
        if build_config.debug || build_config.verbose || tool_config.debug || tool_config.verbose {
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
            if build_config.debug || build_config.verbose || tool_config.debug || tool_config.verbose {
                println('Compiling ${tool_config.name}: ${src_file}...')
            }
            tool_target_config := config.TargetConfig(tool_config)
            // show compile command if verbose
            if tool_config.verbose || build_config.verbose {
                cmd_preview := config.build_shared_compiler_command(src_file, obj_file, build_config, tool_target_config)
                println('Compile command (preview): ${cmd_preview}')
            }
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
    if build_config.debug || build_config.verbose || tool_config.debug || tool_config.verbose {
        println('Linking tool: ${executable}')
    }
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

    // Execute compile
    res := os.execute(cmd)
    if res.exit_code != 0 {
        // Print compile command and raw output to aid debugging
        println('Compile command: ${cmd}')
        println('Compiler output:\n${res.output}')
        return error('Compilation failed with exit code ${res.exit_code}: ${res.output}')
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
        // Always print the linker command and its raw output to aid debugging
        println('Linker command: ${cmd}')
        // print raw output (may contain stdout and stderr merged by os.execute)
        println('Linker output:\n${res.output}')
        return error('Shared library linking failed with exit code ${res.exit_code}: ${res.output}')
    }
}

fn link_tool(object_files []string, executable string, build_config config.BuildConfig, tool_config config.ToolConfig) ! {
    cmd := config.build_tool_linker_command(object_files, executable, build_config, tool_config)
    
    if tool_config.verbose {
        println('Tool link command: ${cmd}')
    }

    res := os.execute(cmd)
    if res.exit_code != 0 {
        // Always print the linker command and its raw output to aid debugging
        println('Linker command: ${cmd}')
        println('Linker output:\n${res.output}')
        return error('Tool linking failed with exit code ${res.exit_code}: ${res.output}')
    }
}

fn get_object_file(source_file string, object_dir string) string {
    // Compute object file path by preserving the path under src/ and placing it under object_dir
    // e.g., src/lib/file.cpp -> <object_dir>/lib/file.o
    // Detect the 'src' prefix and compute relative path
    rel := if source_file.starts_with('src/') {
        source_file[4..]
    } else if source_file.starts_with('./src/') {
        source_file[6..]
    } else {
        // fallback: use basename
        os.base(source_file)
    }

    // strip extension and add .o using basename to avoid nested paths under object_dir
    rel_no_ext := rel.replace('.cpp', '').replace('.cc', '').replace('.cxx', '')
    base_name := os.base(rel_no_ext)
    obj_file := os.join_path(object_dir, base_name + '.o')
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
    if !os.is_file(source_file) {
        // source missing, signal recompile to allow upstream code to handle error
        return true
    }

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