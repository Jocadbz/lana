module tests

import config
import builder

fn test_static_link_defaults_to_false() {
    cfg := config.default_config

    assert cfg.static_link == false
}

fn test_tool_config_static_link_defaults_to_false() {
    tool := config.ToolConfig{
        name: 'test'
    }

    assert tool.static_link == false
}

fn test_static_link_command_includes_static_flag() {
    cfg := config.BuildConfig{
        compiler: 'g++'
        toolchain: 'gcc'
        bin_dir: 'bin'
    }
    tc := config.get_toolchain(cfg)

    tool_cfg := config.ToolConfig{
        name: 'mytool'
        static_link: true
    }

    cmd := tc.tool_link_command(['main.o'], 'bin/tools/mytool', &cfg, tool_cfg)

    assert cmd.contains('-static')
    assert cmd.contains('-static-libgcc')
    assert cmd.contains('-static-libstdc++')
}

fn test_static_link_command_uses_static_libraries() {
    cfg := config.BuildConfig{
        compiler: 'g++'
        toolchain: 'gcc'
        bin_dir: 'bin'
    }
    tc := config.get_toolchain(cfg)

    tool_cfg := config.ToolConfig{
        name: 'mytool'
        libraries: ['core']
        static_link: true
    }

    cmd := tc.tool_link_command(['main.o'], 'bin/tools/mytool', &cfg, tool_cfg)

    assert cmd.contains('-l:core.a')
    assert !cmd.contains('-l:core.so')
}

fn test_dynamic_link_command_uses_shared_libraries() {
    cfg := config.BuildConfig{
        compiler: 'g++'
        toolchain: 'gcc'
        bin_dir: 'bin'
    }
    tc := config.get_toolchain(cfg)

    tool_cfg := config.ToolConfig{
        name: 'mytool'
        libraries: ['core']
        static_link: false
    }

    cmd := tc.tool_link_command(['main.o'], 'bin/tools/mytool', &cfg, tool_cfg)

    assert cmd.contains('-l:core.so')
    assert !cmd.contains('-l:core.a')
    assert !cmd.contains('-static')
}

fn test_clang_static_link_command() {
    cfg := config.BuildConfig{
        compiler: 'clang++'
        toolchain: 'clang'
        bin_dir: 'bin'
    }
    tc := config.get_toolchain(cfg)

    tool_cfg := config.ToolConfig{
        name: 'mytool'
        static_link: true
    }

    cmd := tc.tool_link_command(['main.o'], 'bin/tools/mytool', &cfg, tool_cfg)

    assert cmd.starts_with('clang++')
    assert cmd.contains('-static')
}

fn test_any_tool_needs_static_link_returns_false_when_no_tools() {
    cfg := config.BuildConfig{
        tools: []
    }

    assert builder.any_tool_needs_static_link(cfg) == false
}

fn test_any_tool_needs_static_link_returns_false_when_all_dynamic() {
    cfg := config.BuildConfig{
        tools: [
            config.ToolConfig{ name: 'tool1', static_link: false },
            config.ToolConfig{ name: 'tool2', static_link: false }
        ]
    }

    assert builder.any_tool_needs_static_link(cfg) == false
}

fn test_any_tool_needs_static_link_returns_true_when_one_static() {
    cfg := config.BuildConfig{
        tools: [
            config.ToolConfig{ name: 'tool1', static_link: false },
            config.ToolConfig{ name: 'tool2', static_link: true },
            config.ToolConfig{ name: 'tool3', static_link: false }
        ]
    }

    assert builder.any_tool_needs_static_link(cfg) == true
}

fn test_any_tool_needs_static_link_returns_true_when_all_static() {
    cfg := config.BuildConfig{
        tools: [
            config.ToolConfig{ name: 'tool1', static_link: true },
            config.ToolConfig{ name: 'tool2', static_link: true }
        ]
    }

    assert builder.any_tool_needs_static_link(cfg) == true
}
