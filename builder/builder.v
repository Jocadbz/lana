module builder

import os
import config
import deps
import runtime
import time
import util

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

struct BuildNode {
    id string
    name string
    target BuildTarget
    raw_dependencies []string
mut:
    dependencies []string
    shared_lib_idx int = -1
    tool_idx int = -1
    is_directive bool
    directive config.BuildDirective
    output_path string
}

struct BuildGraph {
    nodes []BuildNode
    node_index map[string]int
    order []int
    unresolved map[string][]string
}

pub struct GraphNodeSummary {
pub:
    id string
    name string
    target BuildTarget
    dependencies []string
    raw_dependencies []string
    is_directive bool
    output_path string
}

pub struct GraphPlanSummary {
pub:
    nodes []GraphNodeSummary
    order []string
    unresolved map[string][]string
}

pub fn preview_build_graph(build_config &config.BuildConfig) !GraphPlanSummary {
    graph := plan_build_graph(build_config)!

    mut nodes := []GraphNodeSummary{}
    for node in graph.nodes {
        nodes << GraphNodeSummary{
            id: node.id
            name: node.name
            target: node.target
            dependencies: node.dependencies.clone()
            raw_dependencies: node.raw_dependencies.clone()
            is_directive: node.is_directive
            output_path: node.output_path
        }
    }

    mut order := []string{}
    for idx in graph.order {
        order << graph.nodes[idx].id
    }

    mut unresolved := map[string][]string{}
    for id, deps in graph.unresolved {
        unresolved[id] = deps.clone()
    }

    return GraphPlanSummary{
        nodes: nodes
        order: order
        unresolved: unresolved
    }
}

struct DirectiveBuildContext {
    source string
    object string
    target_config config.TargetConfig
}

const ansi_reset = '\x1b[0m'
const ansi_red = '\x1b[31m'
const ansi_green = '\x1b[32m'
const ansi_yellow = '\x1b[33m'
const ansi_cyan = '\x1b[36m'
const skip_directive_err = 'skip_directive'

fn should_use_color() bool {
    return os.getenv('NO_COLOR') == '' && os.is_atty(1) != 0
}

fn colorize(text string, color string) string {
    if color == '' || !should_use_color() {
        return text
    }
    return '${color}${text}${ansi_reset}'
}

fn register_alias(mut alias_map map[string]string, alias string, id string) {
    trimmed := alias.trim_space()
    if trimmed == '' {
        return
    }
    if trimmed in alias_map {
        return
    }
    alias_map[trimmed] = id
}

fn resolve_dependency(alias_map map[string]string, dep string) string {
    trimmed := dep.trim_space()
    if trimmed == '' {
        return ''
    }
    mut candidates := []string{}
    candidates << trimmed
    if trimmed.ends_with('.so') && trimmed.len > 3 {
        base := trimmed[..trimmed.len - 3]
        candidates << base
        if base.starts_with('lib/') && base.len > 4 {
            candidates << base[4..]
        }
    }
    if trimmed.starts_with('lib/') && trimmed.len > 4 {
        candidates << trimmed[4..]
    }
    if trimmed.contains('/') {
        parts := trimmed.split('/')
        if parts.len > 0 {
            candidates << parts[parts.len - 1]
        }
    }
    for candidate in candidates {
        if candidate in alias_map {
            return alias_map[candidate]
        }
    }
    return ''
}

fn topo_sort_nodes(nodes []BuildNode, node_index map[string]int) ![]int {
    mut indegree := []int{len: nodes.len, init: 0}
    mut adjacency := [][]int{len: nodes.len}
    for idx, node in nodes {
        for dep_id in node.dependencies {
            dep_idx := node_index[dep_id] or {
                return error('Unknown dependency ${dep_id} referenced by node ${node.id}')
            }
            adjacency[dep_idx] << idx
            indegree[idx] += 1
        }
    }

    mut queue := []int{}
    for idx, deg in indegree {
        if deg == 0 {
            queue << idx
        }
    }

    mut order := []int{}
    mut head := 0
    for head < queue.len {
        current := queue[head]
        head += 1
        order << current
        for neighbor in adjacency[current] {
            indegree[neighbor] -= 1
            if indegree[neighbor] == 0 {
                queue << neighbor
            }
        }
    }

    if order.len != nodes.len {
        return error('Build graph contains a cycle or unresolved dependency')
    }

    return order
}

fn run_compile_tasks(tasks []CompileTask, build_config config.BuildConfig, toolchain config.Toolchain) ![]string {
    mut object_files := []string{}
    if tasks.len == 0 {
        return object_files
    }

    // If parallel compilation disabled, compile sequentially
    if !build_config.parallel_compilation {
        for task in tasks {
            object := compile_file(task.source, task.obj, build_config, toolchain, task.target_config) or { 
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
        go fn (ch chan CompileTask, res chan CompileResult, bc config.BuildConfig, tc config.Toolchain) {
            for {
                t := <-ch
                // sentinel task: empty source signals worker to exit
                if t.source == '' {
                    break
                }
                object := compile_file(t.source, t.obj, bc, tc, t.target_config) or {
                    res <- CompileResult{obj: '', err: err.msg()}
                    continue
                }
                res <- CompileResult{obj: object, err: ''}
            }
        }(tasks_ch, res_ch, build_config, toolchain)
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

fn plan_build_graph(build_config &config.BuildConfig) !BuildGraph {
    mut nodes := []BuildNode{}
    mut alias_map := map[string]string{}

    for idx, lib_config in build_config.shared_libs {
        if lib_config.sources.len == 0 {
            if build_config.debug || build_config.verbose || lib_config.debug || lib_config.verbose {
                println('Skipping empty shared library: ${lib_config.name}')
            }
            continue
        }
        node_id := 'shared:${lib_config.name}'
        node := BuildNode{
            id: node_id
            name: lib_config.name
            target: BuildTarget.shared_lib
            raw_dependencies: lib_config.libraries.clone()
            shared_lib_idx: idx
        }
        nodes << node
        register_alias(mut alias_map, lib_config.name, node_id)
        register_alias(mut alias_map, 'lib/${lib_config.name}', node_id)
        register_alias(mut alias_map, '${lib_config.name}.so', node_id)
        register_alias(mut alias_map, 'lib/${lib_config.name}.so', node_id)
    }

    for directive in build_config.build_directives {
        node_id := 'directive:${directive.unit_name}'
        node := BuildNode{
            id: node_id
            name: directive.unit_name
            target: if directive.is_shared { BuildTarget.shared_lib } else { BuildTarget.tool }
            raw_dependencies: directive.depends_units.clone()
            is_directive: true
            directive: directive
            output_path: directive.output_path
        }
        nodes << node
        register_alias(mut alias_map, directive.unit_name, node_id)
        parts := directive.unit_name.split('/')
        if parts.len > 0 {
            base := parts[parts.len - 1]
            register_alias(mut alias_map, base, node_id)
            if directive.is_shared {
                register_alias(mut alias_map, '${base}.so', node_id)
            }
        }
        if directive.output_path != '' {
            register_alias(mut alias_map, directive.output_path, node_id)
        }
    }

    for idx, tool_config in build_config.tools {
        if tool_config.sources.len == 0 {
            if build_config.debug || build_config.verbose || tool_config.debug || tool_config.verbose {
                println('Skipping empty tool: ${tool_config.name}')
            }
            continue
        }
        node_id := 'tool:${tool_config.name}'
        node := BuildNode{
            id: node_id
            name: tool_config.name
            target: BuildTarget.tool
            raw_dependencies: tool_config.libraries.clone()
            tool_idx: idx
        }
        nodes << node
        register_alias(mut alias_map, tool_config.name, node_id)
        register_alias(mut alias_map, 'tools/${tool_config.name}', node_id)
    }

    mut node_index := map[string]int{}
    for idx, node in nodes {
        if node.id in node_index {
            return error('Duplicate node id detected in build graph: ${node.id}')
        }
        node_index[node.id] = idx
    }

    mut unresolved := map[string][]string{}
    for idx in 0 .. nodes.len {
        mut resolved := []string{}
        mut missing := []string{}
        for dep in nodes[idx].raw_dependencies {
            dep_id := resolve_dependency(alias_map, dep)
            if dep_id == '' {
                missing << dep
                continue
            }
            if dep_id !in resolved {
                resolved << dep_id
            }
        }
        nodes[idx].dependencies = resolved
        if missing.len > 0 {
            unresolved[nodes[idx].id] = missing
        }
    }

    order := if nodes.len > 0 { topo_sort_nodes(nodes, node_index)! } else { []int{} }

    return BuildGraph{
        nodes: nodes
        node_index: node_index
        order: order
        unresolved: unresolved
    }
}

fn execute_build_graph(mut build_config config.BuildConfig, graph BuildGraph, toolchain config.Toolchain) ! {
    for node_idx in graph.order {
        node := graph.nodes[node_idx]
        if node.id in graph.unresolved && build_config.verbose {
            missing := graph.unresolved[node.id]
            println(colorize('Warning: Unresolved dependencies for ${node.name}: ${missing.join(", ")}', ansi_yellow))
        }

        if node.is_directive && (build_config.debug || build_config.verbose) {
            println('Building unit: ${node.name}')
        }

        match node.target {
            .shared_lib {
                if node.is_directive {
                    build_directive_shared(node.directive, build_config, toolchain) or {
                        return error('Failed to build shared directive ${node.name}: ${err}')
                    }
                } else if node.shared_lib_idx >= 0 {
                    mut lib_config := &build_config.shared_libs[node.shared_lib_idx]
                    if build_config.debug || build_config.verbose || lib_config.debug || lib_config.verbose {
                        println('Building shared library: ${lib_config.name}')
                    }
                    build_shared_library(mut lib_config, build_config, toolchain) or {
                        return error('Failed to build shared library ${lib_config.name}: ${err}')
                    }
                    if build_config.verbose {
                        println('Built shared library: ${lib_config.name}')
                    }
                }
            }
            .tool {
                if node.is_directive {
                    build_directive_tool(node.directive, build_config, toolchain) or {
                        return error('Failed to build tool directive ${node.name}: ${err}')
                    }
                } else if node.tool_idx >= 0 {
                    mut tool_config := &build_config.tools[node.tool_idx]
                    if build_config.debug || build_config.verbose || tool_config.debug || tool_config.verbose {
                        println('Building tool: ${tool_config.name}')
                    }
                    build_tool(mut tool_config, build_config, toolchain) or {
                        return error('Failed to build tool ${tool_config.name}: ${err}')
                    }
                    if build_config.verbose {
                        println('Built tool: ${tool_config.name}')
                    }
                }
            }
        }
    }
}

fn resolve_directive_source(directive config.BuildDirective, build_config config.BuildConfig) string {
    extensions := ['.cpp', '.cc', '.cxx']
    for ext in extensions {
        candidate := os.join_path(build_config.src_dir, directive.unit_name + ext)
        if os.is_file(candidate) {
            return candidate
        }
    }

    parts := directive.unit_name.split('/')
    base := if parts.len > 0 { parts[parts.len - 1] } else { directive.unit_name }
    for ext in extensions {
        candidate := os.join_path(build_config.src_dir, base + ext)
        if os.is_file(candidate) {
            return candidate
        }
    }

    return ''
}

fn prepare_directive_build(directive config.BuildDirective, build_config config.BuildConfig) !DirectiveBuildContext {
    source_file := resolve_directive_source(directive, build_config)
    if source_file == '' {
        if build_config.verbose {
            println(colorize('Warning: Source file not found for unit ${directive.unit_name}', ansi_yellow))
        }
        return error(skip_directive_err)
    }

    object_dir := os.join_path(build_config.build_dir, directive.unit_name)
    os.mkdir_all(object_dir) or {
        return error('Failed to create object directory: ${object_dir}')
    }

    obj_file := get_object_file(source_file, object_dir)
    obj_path := os.dir(obj_file)
    os.mkdir_all(obj_path) or {
        return error('Failed to create object directory: ${obj_path}')
    }

    target_config := if directive.is_shared {
        config.TargetConfig(config.SharedLibConfig{
            name: directive.unit_name
            sources: [source_file]
            libraries: directive.link_libs
            cflags: directive.cflags
            ldflags: directive.ldflags
            debug: build_config.debug
            optimize: build_config.optimize
            verbose: build_config.verbose
        })
    } else {
        config.TargetConfig(config.ToolConfig{
            name: directive.unit_name
            sources: [source_file]
            libraries: directive.link_libs
            cflags: directive.cflags
            ldflags: directive.ldflags
            debug: build_config.debug
            optimize: build_config.optimize
            verbose: build_config.verbose
        })
    }

    return DirectiveBuildContext{
        source: source_file
        object: obj_file
        target_config: target_config
    }
}

fn build_directive_shared(directive config.BuildDirective, build_config config.BuildConfig, toolchain config.Toolchain) ! {
    ctx := prepare_directive_build(directive, build_config) or {
        if err.msg() == skip_directive_err {
            return
        }
        return error(err.msg())
    }

    if needs_recompile(ctx.source, ctx.object) {
        if build_config.debug || build_config.verbose {
            println('Compiling ${directive.unit_name}: ${ctx.source}...')
        }
        compile_file(ctx.source, ctx.object, build_config, toolchain, ctx.target_config) or {
            return error('Failed to compile ${ctx.source} for ${directive.unit_name}')
        }
    } else if build_config.verbose {
        println('Using cached ${ctx.object} for ${directive.unit_name}')
    }

    lib_output_dir := os.join_path(build_config.bin_dir, 'lib')
    os.mkdir_all(lib_output_dir) or {
        return error('Failed to create shared lib output directory: ${lib_output_dir}')
    }

    if build_config.debug || build_config.verbose {
        parts := directive.unit_name.split('/')
        base := if parts.len > 0 { parts[parts.len - 1] } else { directive.unit_name }
        println('Linking shared library: ${lib_output_dir}/${base}.so')
    }

    link_shared_library([ctx.object], directive.unit_name, lib_output_dir, build_config, toolchain, config.SharedLibConfig{
        name: directive.unit_name
        libraries: directive.link_libs
        debug: build_config.debug
        optimize: build_config.optimize
        verbose: build_config.verbose
        ldflags: directive.ldflags
    }) or {
        return error('Failed to link shared library ${directive.unit_name}')
    }

    if build_config.verbose {
        println('Successfully built unit: ${directive.unit_name}')
    }
}

fn build_directive_tool(directive config.BuildDirective, build_config config.BuildConfig, toolchain config.Toolchain) ! {
    ctx := prepare_directive_build(directive, build_config) or {
        if err.msg() == skip_directive_err {
            return
        }
        return error(err.msg())
    }

    if needs_recompile(ctx.source, ctx.object) {
        if build_config.debug || build_config.verbose {
            println('Compiling ${directive.unit_name}: ${ctx.source}...')
        }
        compile_file(ctx.source, ctx.object, build_config, toolchain, ctx.target_config) or {
            return error('Failed to compile ${ctx.source} for ${directive.unit_name}')
        }
    } else if build_config.verbose {
        println('Using cached ${ctx.object} for ${directive.unit_name}')
    }

    executable := os.join_path(build_config.bin_dir, directive.output_path)
    if build_config.debug || build_config.verbose {
        println('Linking executable: ${executable}')
    }

    // Directive static(true/false) overrides global config, otherwise inherit global setting
    use_static := directive.static_link or { build_config.static_link }

    link_tool([ctx.object], executable, build_config, toolchain, config.ToolConfig{
        name: directive.unit_name
        libraries: directive.link_libs
        debug: build_config.debug
        optimize: build_config.optimize
        verbose: build_config.verbose
        ldflags: directive.ldflags
        static_link: use_static
    }) or {
        return error('Failed to link executable ${directive.unit_name}')
    }

    if build_config.verbose {
        println('Successfully built unit: ${directive.unit_name}')
    }
}

pub fn build(mut build_config config.BuildConfig) ! {
    // Run build flow and ensure that if any error occurs we print its message
    start_time := time.now()
    println('Building ${build_config.project_name}...')

    run_build := fn (mut build_config config.BuildConfig) ! {
        // Create directories
        os.mkdir_all(build_config.build_dir) or { return error('Failed to create build directory') }
        os.mkdir_all(build_config.bin_dir) or { return error('Failed to create bin directory') }
        os.mkdir_all('${build_config.bin_dir}/lib') or { return error('Failed to create lib directory') }
        os.mkdir_all('${build_config.bin_dir}/tools') or { return error('Failed to create tools directory') }

        // Auto-discover sources if not specified
        auto_discover_sources(mut build_config)
        toolchain := config.get_toolchain(build_config)
        graph := plan_build_graph(&build_config)!
        if build_config.verbose {
            println('Using toolchain: ${toolchain.description()} (${build_config.compiler})')
        }
        execute_build_graph(mut build_config, graph, toolchain)!

        return
    }

    // Execute build and show full error output if something fails
    run_build(mut build_config) or {
        // Print error message to help debugging
        elapsed := time.since(start_time)
        println(colorize('Build failed: ${err}', ansi_red))
        println('Build time: ${elapsed.seconds():.2f}s')
        return err
    }
    
    elapsed := time.since(start_time)
    println(colorize('Build completed successfully!', ansi_green))
    println('Build time: ${elapsed.seconds():.2f}s')
}


fn auto_discover_sources(mut build_config config.BuildConfig) {
    // Auto-discover shared library sources
    for mut lib_config in build_config.shared_libs {
        if lib_config.sources.len == 0 {
            // Look for sources in src/lib/<lib_name>/
            lib_src_dir := os.join_path('src', 'lib', lib_config.name)
            if os.is_dir(lib_src_dir) {
            lib_sources := util.find_source_files(lib_src_dir) or { []string{} }
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
                tool_sources := util.find_source_files(tool_src_dir) or { []string{} }
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
            all_sources := util.find_source_files(build_config.src_dir) or { []string{} }
            if all_sources.len > 0 {
                default_tool.sources = all_sources
                if build_config.verbose {
                    println('Auto-discovered ${all_sources.len} source files for main project')
                }
            }
        }
    }

    // Ensure the main project tool exists if it wasn't explicitly defined
    // This handles the case where config.ini defines other tools but not the main project tool
    mut main_tool_exists := false
    for tool in build_config.tools {
        if tool.name == build_config.project_name {
            main_tool_exists = true
            break
        }
    }

    // Also check if the main project exists as a build directive
    if !main_tool_exists {
        for directive in build_config.build_directives {
            // Check if directive unit_name matches project_name or ends with project_name
            if directive.unit_name == build_config.project_name {
                main_tool_exists = true
                break
            }
            // Also match "fossvg" to directive "fossvg" or "tools/fossvg"
            parts := directive.unit_name.split('/')
            if parts.len > 0 && parts[parts.len - 1] == build_config.project_name {
                main_tool_exists = true
                break
            }
        }
    }

    if !main_tool_exists {
        // Look for src/<project_name>.cpp
        main_src := os.join_path(build_config.src_dir, '${build_config.project_name}.cpp')
        if os.is_file(main_src) {
            if build_config.verbose {
                println('Auto-discovered main project tool: ${build_config.project_name} from ${main_src}')
            }
            
            new_tool := config.ToolConfig{
                name: build_config.project_name
                sources: [main_src]
                debug: build_config.debug
                optimize: build_config.optimize
                verbose: build_config.verbose
                libraries: [] // Will inherit global libs during link
            }
            build_config.tools << new_tool
        }
    }
}

pub fn clean(build_config config.BuildConfig) {
    println('Cleaning build files...')
    
    // Remove build directory
    if os.is_dir(build_config.build_dir) {
        os.rmdir_all(build_config.build_dir) or {
            println(colorize('Warning: Failed to remove ${build_config.build_dir}: ${err}', ansi_yellow))
        }
        println('Removed ${build_config.build_dir}')
    }
    
    // Remove bin directories
    dirs_to_clean := ['lib', 'tools']
    for dir in dirs_to_clean {
        full_dir := os.join_path(build_config.bin_dir, dir)
        if os.is_dir(full_dir) {
            os.rmdir_all(full_dir) or {
                println(colorize('Warning: Failed to remove ${full_dir}: ${err}', ansi_yellow))
            }
            println('Removed ${full_dir}')
        }
    }
    
    // Remove main executable if it exists (backward compatibility)
    main_exe := os.join_path(build_config.bin_dir, build_config.project_name)
    if os.is_file(main_exe) {
        os.rm(main_exe) or {
            println(colorize('Warning: Failed to remove ${main_exe}: ${err}', ansi_yellow))
        }
        println('Removed ${main_exe}')
    }
    
    println('Clean completed!')
}

fn build_shared_library(mut lib_config config.SharedLibConfig, build_config config.BuildConfig, toolchain config.Toolchain) ! {
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
                println(colorize('Warning: Source file not found: ${src_file}', ansi_yellow))
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
                cmd_preview := toolchain.compile_command(src_file, obj_file, &build_config, lib_target_config)
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
        compiled := run_compile_tasks(compile_tasks, build_config, toolchain) or { return err }
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
    link_shared_library(object_files, lib_config.name, lib_output_dir, build_config, toolchain, lib_config) or { 
        return error('Failed to link shared library ${lib_config.name}')
    }
    
    if build_config.verbose {
        println('Successfully built shared library: ${lib_config.name}')
    }
}

fn build_tool(mut tool_config config.ToolConfig, build_config config.BuildConfig, toolchain config.Toolchain) ! {
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
                println(colorize('Warning: Source file not found: ${src_file}', ansi_yellow))
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
                cmd_preview := toolchain.compile_command(src_file, obj_file, &build_config, tool_target_config)
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
        compiled := run_compile_tasks(compile_tasks, build_config, toolchain) or { return err }
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
    link_tool(object_files, executable, build_config, toolchain, tool_config) or { 
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

fn compile_file(source_file string, object_file string, build_config config.BuildConfig, toolchain config.Toolchain, target_config config.TargetConfig) !string {
    cmd := toolchain.compile_command(source_file, object_file, &build_config, target_config)

    target_verbose := get_target_verbose(target_config)

    if target_verbose {
        println('Compile command: ${cmd}')
    }

    // Execute compile
    res := os.execute(cmd)
    if res.exit_code != 0 {
        // Print compile command and raw output to aid debugging
        println(colorize('Compile command: ${cmd}', ansi_cyan))
        println(colorize('Compiler output:\n${res.output}', ansi_red))
        return error('Compilation failed with exit code ${res.exit_code}: ${res.output}')
    }
    
    // Generate dependency file
    dep_file := object_file.replace('.o', '.d')
    deps.generate_dependency_file(source_file, object_file, dep_file)
    
    return object_file
}

fn link_shared_library(object_files []string, library_name string, output_path string, build_config config.BuildConfig, toolchain config.Toolchain, lib_config config.SharedLibConfig) ! {
    cmd := toolchain.shared_link_command(object_files, library_name, output_path, &build_config, lib_config)
    
    if lib_config.verbose {
        println('Shared lib link command: ${cmd}')
    }

    res := os.execute(cmd)
    if res.exit_code != 0 {
        // Always print the linker command and its raw output to aid debugging
        println(colorize('Linker command: ${cmd}', ansi_cyan))
        // print raw output (may contain stdout and stderr merged by os.execute)
        println(colorize('Linker output:\n${res.output}', ansi_red))
        return error('Shared library linking failed with exit code ${res.exit_code}: ${res.output}')
    }

    // Check if static archive is needed: either global static_link or any tool has static_link
    needs_static_archive := build_config.static_link || any_tool_needs_static_link(build_config)
    if needs_static_archive {
        create_static_archive(object_files, library_name, output_path, build_config, lib_config)!
    }
}

// any_tool_needs_static_link returns true if any tool in the config has static_link enabled
pub fn any_tool_needs_static_link(build_config config.BuildConfig) bool {
    for tool in build_config.tools {
        if tool.static_link {
            return true
        }
    }
    return false
}

// create_static_archive creates a static library (.a) from object files using ar
fn create_static_archive(object_files []string, library_name string, output_path string, build_config config.BuildConfig, lib_config config.SharedLibConfig) ! {
    // Extract base name from library_name (e.g., "lib/cli" -> "cli")
    parts := library_name.split('/')
    base_name := if parts.len > 0 { parts[parts.len - 1] } else { library_name }
    
    archive_path := os.join_path(output_path, '${base_name}.a')
    
    // Build ar command: ar rcs <archive> <objects...>
    mut cmd := 'ar rcs ${archive_path}'
    for obj_file in object_files {
        cmd += ' ${obj_file}'
    }
    
    if lib_config.verbose || build_config.verbose {
        println('Creating static archive: ${archive_path}')
        println('Archive command: ${cmd}')
    }
    
    ar_res := os.execute(cmd)
    if ar_res.exit_code != 0 {
        println(colorize('Archive command: ${cmd}', ansi_cyan))
        println(colorize('Archive output:\n${ar_res.output}', ansi_red))
        return error('Static archive creation failed with exit code ${ar_res.exit_code}: ${ar_res.output}')
    }
}

fn link_tool(object_files []string, executable string, build_config config.BuildConfig, toolchain config.Toolchain, tool_config config.ToolConfig) ! {
    cmd := toolchain.tool_link_command(object_files, executable, &build_config, tool_config)
    
    if tool_config.verbose {
        println('Tool link command: ${cmd}')
    }

    res := os.execute(cmd)
    if res.exit_code != 0 {
        // Always print the linker command and its raw output to aid debugging
        println(colorize('Linker command: ${cmd}', ansi_cyan))
        println(colorize('Linker output:\n${res.output}', ansi_red))
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