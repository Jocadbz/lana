module tests

import os
import builder
import config

fn test_build_graph_handles_empty_config() {
    cfg := config.BuildConfig{
        project_name: 'empty'
        shared_libs: []
        tools: []
    }

    summary := builder.preview_build_graph(&cfg) or { panic(err) }

    assert summary.nodes.len == 0
    assert summary.order.len == 0
}

fn test_build_graph_handles_multiple_dependencies() {
    tmp := new_temp_dir('lana_multi_deps')
    defer {
        os.rmdir_all(tmp) or {}
    }

    src_dir := os.join_path(tmp, 'src')
    lib_dir := os.join_path(src_dir, 'lib')
    tool_dir := os.join_path(src_dir, 'tools')
    os.mkdir_all(lib_dir) or { panic(err) }
    os.mkdir_all(tool_dir) or { panic(err) }

    // Create source files
    os.write_file(os.join_path(lib_dir, 'base.cpp'), '// base') or { panic(err) }
    os.write_file(os.join_path(lib_dir, 'utils.cpp'), '// utils') or { panic(err) }
    os.write_file(os.join_path(lib_dir, 'core.cpp'), '// core') or { panic(err) }
    os.write_file(os.join_path(tool_dir, 'app.cpp'), '// app') or { panic(err) }

    // core depends on base and utils
    // app depends on core
    cfg := config.BuildConfig{
        project_name: 'multi_deps'
        src_dir: src_dir
        shared_libs: [
            config.SharedLibConfig{
                name: 'base'
                sources: [os.join_path(lib_dir, 'base.cpp')]
            },
            config.SharedLibConfig{
                name: 'utils'
                sources: [os.join_path(lib_dir, 'utils.cpp')]
            },
            config.SharedLibConfig{
                name: 'core'
                sources: [os.join_path(lib_dir, 'core.cpp')]
                libraries: ['base', 'utils']
            },
        ]
        tools: [
            config.ToolConfig{
                name: 'app'
                sources: [os.join_path(tool_dir, 'app.cpp')]
                libraries: ['core']
            },
        ]
    }

    summary := builder.preview_build_graph(&cfg) or { panic(err) }

    // Should have 4 nodes
    assert summary.nodes.len == 4

    // Find app in order - it should come after core
    mut core_idx := -1
    mut app_idx := -1
    for idx, id in summary.order {
        if id == 'shared:core' {
            core_idx = idx
        }
        if id == 'tool:app' {
            app_idx = idx
        }
    }

    assert core_idx >= 0
    assert app_idx >= 0
    assert app_idx > core_idx

    // base and utils should come before core
    mut base_idx := -1
    mut utils_idx := -1
    for idx, id in summary.order {
        if id == 'shared:base' {
            base_idx = idx
        }
        if id == 'shared:utils' {
            utils_idx = idx
        }
    }

    assert base_idx < core_idx
    assert utils_idx < core_idx
}

fn test_build_graph_detects_unresolved_dependencies() {
    tmp := new_temp_dir('lana_unresolved')
    defer {
        os.rmdir_all(tmp) or {}
    }

    src_dir := os.join_path(tmp, 'src')
    os.mkdir_all(src_dir) or { panic(err) }
    os.write_file(os.join_path(src_dir, 'main.cpp'), '// main') or { panic(err) }

    cfg := config.BuildConfig{
        project_name: 'unresolved'
        src_dir: src_dir
        tools: [
            config.ToolConfig{
                name: 'app'
                sources: [os.join_path(src_dir, 'main.cpp')]
                libraries: ['nonexistent_lib']
            },
        ]
    }

    summary := builder.preview_build_graph(&cfg) or { panic(err) }

    // Should have 1 node with unresolved dependency
    assert summary.nodes.len == 1
    assert 'tool:app' in summary.unresolved
    assert summary.unresolved['tool:app'].contains('nonexistent_lib')
}

fn test_build_graph_skips_empty_sources() {
    cfg := config.BuildConfig{
        project_name: 'empty_sources'
        debug: true
        verbose: true
        shared_libs: [
            config.SharedLibConfig{
                name: 'empty_lib'
                sources: []
                debug: true
            },
        ]
        tools: [
            config.ToolConfig{
                name: 'empty_tool'
                sources: []
                debug: true
            },
        ]
    }

    summary := builder.preview_build_graph(&cfg) or { panic(err) }

    // Empty sources should be skipped
    assert summary.nodes.len == 0
}

fn test_build_graph_resolves_lib_prefix_aliases() {
    tmp := new_temp_dir('lana_aliases')
    defer {
        os.rmdir_all(tmp) or {}
    }

    src_dir := os.join_path(tmp, 'src')
    lib_dir := os.join_path(src_dir, 'lib')
    tool_dir := os.join_path(src_dir, 'tools')
    os.mkdir_all(lib_dir) or { panic(err) }
    os.mkdir_all(tool_dir) or { panic(err) }

    os.write_file(os.join_path(lib_dir, 'mylib.cpp'), '// lib') or { panic(err) }
    os.write_file(os.join_path(tool_dir, 'app.cpp'), '// app') or { panic(err) }

    // Reference library with lib/ prefix
    cfg := config.BuildConfig{
        project_name: 'aliases'
        src_dir: src_dir
        shared_libs: [
            config.SharedLibConfig{
                name: 'mylib'
                sources: [os.join_path(lib_dir, 'mylib.cpp')]
            },
        ]
        tools: [
            config.ToolConfig{
                name: 'app'
                sources: [os.join_path(tool_dir, 'app.cpp')]
                libraries: ['lib/mylib']
            },
        ]
    }

    summary := builder.preview_build_graph(&cfg) or { panic(err) }

    // Dependency should be resolved
    assert summary.nodes.len == 2
    assert summary.unresolved.len == 0

    // Find app node and check its dependencies
    for node in summary.nodes {
        if node.id == 'tool:app' {
            assert node.dependencies.contains('shared:mylib')
        }
    }
}

fn test_build_graph_resolves_so_extension_aliases() {
    tmp := new_temp_dir('lana_so_aliases')
    defer {
        os.rmdir_all(tmp) or {}
    }

    src_dir := os.join_path(tmp, 'src')
    lib_dir := os.join_path(src_dir, 'lib')
    tool_dir := os.join_path(src_dir, 'tools')
    os.mkdir_all(lib_dir) or { panic(err) }
    os.mkdir_all(tool_dir) or { panic(err) }

    os.write_file(os.join_path(lib_dir, 'core.cpp'), '// lib') or { panic(err) }
    os.write_file(os.join_path(tool_dir, 'app.cpp'), '// app') or { panic(err) }

    // Reference library with .so extension
    cfg := config.BuildConfig{
        project_name: 'so_aliases'
        src_dir: src_dir
        shared_libs: [
            config.SharedLibConfig{
                name: 'core'
                sources: [os.join_path(lib_dir, 'core.cpp')]
            },
        ]
        tools: [
            config.ToolConfig{
                name: 'app'
                sources: [os.join_path(tool_dir, 'app.cpp')]
                libraries: ['core.so']
            },
        ]
    }

    summary := builder.preview_build_graph(&cfg) or { panic(err) }

    // Dependency should be resolved
    assert summary.unresolved.len == 0

    for node in summary.nodes {
        if node.id == 'tool:app' {
            assert node.dependencies.contains('shared:core')
        }
    }
}

fn test_build_graph_includes_directives() {
    tmp := new_temp_dir('lana_directives_graph')
    defer {
        os.rmdir_all(tmp) or {}
    }

    src_dir := os.join_path(tmp, 'src')
    tool_dir := os.join_path(src_dir, 'tools')
    os.mkdir_all(tool_dir) or { panic(err) }

    os.write_file(os.join_path(tool_dir, 'custom.cpp'), '// custom') or { panic(err) }

    cfg := config.BuildConfig{
        project_name: 'directives'
        src_dir: src_dir
        build_directives: [
            config.BuildDirective{
                unit_name: 'tools/custom'
                output_path: 'tools/custom'
                is_shared: false
            },
        ]
    }

    summary := builder.preview_build_graph(&cfg) or { panic(err) }

    assert summary.nodes.len == 1
    assert summary.nodes[0].id == 'directive:tools/custom'
    assert summary.nodes[0].is_directive == true
}
