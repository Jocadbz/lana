module tests

import os
import builder
import config

fn test_preview_build_graph_orders_dependencies() {
    tmp := new_temp_dir('lana_graph')
    defer {
        os.rmdir_all(tmp) or {}
    }

    src_dir := os.join_path(tmp, 'src')
    lib_dir := os.join_path(src_dir, 'lib')
    tool_dir := os.join_path(src_dir, 'tools')
    os.mkdir_all(lib_dir) or { panic(err) }
    os.mkdir_all(tool_dir) or { panic(err) }

    core_src := os.join_path(lib_dir, 'core.cpp')
    tool_src := os.join_path(tool_dir, 'demo.cpp')
    os.write_file(core_src, '// core stub\n') or { panic(err) }
    os.write_file(tool_src, '// tool stub\n') or { panic(err) }

    mut cfg := config.BuildConfig{
        project_name: 'demo'
        src_dir: src_dir
        build_dir: os.join_path(tmp, 'build')
        bin_dir: os.join_path(tmp, 'bin')
        toolchain: 'gcc'
        compiler: 'g++'
        debug: true
        shared_libs: [
            config.SharedLibConfig{
                name: 'core'
                sources: [core_src]
            }
        ]
        tools: [
            config.ToolConfig{
                name: 'demo'
                sources: [tool_src]
                libraries: ['core']
            }
        ]
    }

    summary := builder.preview_build_graph(&cfg) or { panic(err) }

    assert summary.nodes.len == 2
    assert summary.unresolved.len == 0

    mut shared_found := false
    mut tool_found := false
    for node in summary.nodes {
        if node.id == 'shared:core' {
            shared_found = true
            assert node.dependencies.len == 0
        }
        if node.id == 'tool:demo' {
            tool_found = true
            assert node.dependencies.contains('shared:core')
        }
    }

    assert shared_found
    assert tool_found
    assert summary.order.len == 2
    assert summary.order[0] == 'shared:core'
    assert summary.order[1] == 'tool:demo'
}
