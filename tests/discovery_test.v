module tests

import os
import builder
import config

fn test_auto_discover_main_tool_when_other_tools_exist() {
    tmp := new_temp_dir('lana_discovery')
    defer {
        os.rmdir_all(tmp) or {}
    }

    src_dir := os.join_path(tmp, 'src')
    tools_dir := os.join_path(src_dir, 'tools')
    os.mkdir_all(tools_dir) or { panic(err) }

    // Create a tool that IS in config
    os.write_file(os.join_path(tools_dir, 'existing.cpp'), 'int main(){}') or { panic(err) }

    // Create a main source that SHOULD be discovered as the main tool
    os.write_file(os.join_path(src_dir, 'testproj.cpp'), 'int main(){}') or { panic(err) }

    mut cfg := config.BuildConfig{
        project_name: 'testproj'
        src_dir: src_dir
        tools: [
            config.ToolConfig{
                name: 'existing'
                sources: [os.join_path(tools_dir, 'existing.cpp')]
            }
        ]
    }

    // Run auto-discovery
    builder.auto_discover_sources(mut cfg)

    // Check if testproj tool was added
    mut found := false
    for tool in cfg.tools {
        if tool.name == 'testproj' {
            found = true
            assert tool.sources.len == 1
            assert tool.sources[0].ends_with('testproj.cpp')
        }
    }
    assert found
}
