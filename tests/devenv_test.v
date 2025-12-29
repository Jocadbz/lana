module tests

import os
import config
import devenv

fn test_detect_shell_from_env() {
    // Test shell detection parsing
    assert devenv.parse_shell_name('/bin/bash') == devenv.ShellType.bash
    assert devenv.parse_shell_name('/usr/bin/zsh') == devenv.ShellType.zsh
    assert devenv.parse_shell_name('/usr/local/bin/fish') == devenv.ShellType.fish
    assert devenv.parse_shell_name('/bin/sh') == devenv.ShellType.sh
    assert devenv.parse_shell_name('bash') == devenv.ShellType.bash
    assert devenv.parse_shell_name('zsh') == devenv.ShellType.zsh
    assert devenv.parse_shell_name('fish') == devenv.ShellType.fish
    assert devenv.parse_shell_name('sh') == devenv.ShellType.sh
    assert devenv.parse_shell_name('unknown_shell') == devenv.ShellType.unknown
}

fn test_shell_type_to_string() {
    assert devenv.shell_type_to_string(devenv.ShellType.bash) == 'bash'
    assert devenv.shell_type_to_string(devenv.ShellType.zsh) == 'zsh'
    assert devenv.shell_type_to_string(devenv.ShellType.fish) == 'fish'
    assert devenv.shell_type_to_string(devenv.ShellType.sh) == 'sh'
    assert devenv.shell_type_to_string(devenv.ShellType.unknown) == 'unknown'
}

fn test_get_devenv_config_uses_lib_search_paths_by_default() {
    build_config := config.BuildConfig{
        project_name: 'testproject'
        bin_dir: 'bin'
        lib_search_paths: ['custom/lib', 'other/lib']
        devenv_lib_paths: []
    }
    
    devenv_config := devenv.get_devenv_config(build_config)
    
    assert devenv_config.project_name == 'testproject'
    assert 'custom/lib' in devenv_config.lib_search_paths
    assert 'other/lib' in devenv_config.lib_search_paths
    assert 'bin/lib' in devenv_config.lib_search_paths
}

fn test_get_devenv_config_uses_devenv_lib_paths_when_set() {
    build_config := config.BuildConfig{
        project_name: 'testproject'
        bin_dir: 'bin'
        lib_search_paths: ['default/lib']
        devenv_lib_paths: ['devenv/lib', 'devenv/extra']
    }
    
    devenv_config := devenv.get_devenv_config(build_config)
    
    assert devenv_config.project_name == 'testproject'
    // devenv_lib_paths should take priority
    assert 'devenv/lib' in devenv_config.lib_search_paths
    assert 'devenv/extra' in devenv_config.lib_search_paths
    // default lib path should still be added
    assert 'bin/lib' in devenv_config.lib_search_paths
    // lib_search_paths should NOT be used when devenv_lib_paths is set
    assert 'default/lib' !in devenv_config.lib_search_paths
}

fn test_generate_bash_script_contains_deactivate() {
    devenv_config := devenv.DevEnvConfig{
        lib_search_paths: ['/path/to/lib']
        project_name: 'myproject'
        bin_dir: 'bin'
    }
    
    script := devenv.generate_activation_script(devenv.ShellType.bash, devenv_config) or {
        assert false, 'Failed to generate bash script: ${err}'
        return
    }
    
    assert script.contains('deactivate')
    assert script.contains('LD_LIBRARY_PATH')
    assert script.contains('myproject')
    assert script.contains('/path/to/lib')
    assert script.contains("Lana's temp environment")
}

fn test_generate_fish_script_contains_deactivate() {
    devenv_config := devenv.DevEnvConfig{
        lib_search_paths: ['/path/to/lib']
        project_name: 'myproject'
        bin_dir: 'bin'
    }
    
    script := devenv.generate_activation_script(devenv.ShellType.fish, devenv_config) or {
        assert false, 'Failed to generate fish script: ${err}'
        return
    }
    
    assert script.contains('function deactivate')
    assert script.contains('LD_LIBRARY_PATH')
    assert script.contains('myproject')
    assert script.contains('fish_prompt')
}

fn test_generate_zsh_script_contains_deactivate() {
    devenv_config := devenv.DevEnvConfig{
        lib_search_paths: ['/path/to/lib']
        project_name: 'myproject'
        bin_dir: 'bin'
    }
    
    script := devenv.generate_activation_script(devenv.ShellType.zsh, devenv_config) or {
        assert false, 'Failed to generate zsh script: ${err}'
        return
    }
    
    assert script.contains('deactivate')
    assert script.contains('LD_LIBRARY_PATH')
    assert script.contains('PS1')
}

fn test_generate_sh_script_contains_deactivate() {
    devenv_config := devenv.DevEnvConfig{
        lib_search_paths: ['/path/to/lib']
        project_name: 'myproject'
        bin_dir: 'bin'
    }
    
    script := devenv.generate_activation_script(devenv.ShellType.sh, devenv_config) or {
        assert false, 'Failed to generate sh script: ${err}'
        return
    }
    
    assert script.contains('deactivate')
    assert script.contains('LD_LIBRARY_PATH')
}

fn test_unknown_shell_returns_error() {
    devenv_config := devenv.DevEnvConfig{
        lib_search_paths: ['/path/to/lib']
        project_name: 'myproject'
        bin_dir: 'bin'
    }
    
    script := devenv.generate_activation_script(devenv.ShellType.unknown, devenv_config) or {
        // Expected to fail
        assert err.msg().contains('unknown shell')
        return
    }
    
    assert false, 'Should have returned error for unknown shell'
}

fn test_config_parsing_devenv_lib_paths() {
    tmp := new_temp_dir('lana_devenv_config')
    defer {
        os.rmdir_all(tmp) or {}
    }

    config_path := os.join_path(tmp, 'config.ini')
    config_content := '[global]\nproject_name = testproj\nlib_search_paths = default/lib\ndevenv_lib_paths = devenv/lib1, devenv/lib2\n'
    os.write_file(config_path, config_content) or { panic(err) }

    cfg := config.parse_config_file(config_path) or { panic(err) }

    assert cfg.project_name == 'testproj'
    assert cfg.lib_search_paths.contains('default/lib')
    assert cfg.devenv_lib_paths.contains('devenv/lib1')
    assert cfg.devenv_lib_paths.contains('devenv/lib2')
}

fn test_multiple_lib_paths_joined_with_colon() {
    devenv_config := devenv.DevEnvConfig{
        lib_search_paths: ['/path/one', '/path/two', '/path/three']
        project_name: 'myproject'
        bin_dir: 'bin'
    }
    
    script := devenv.generate_activation_script(devenv.ShellType.bash, devenv_config) or {
        assert false, 'Failed to generate script: ${err}'
        return
    }
    
    // Paths should be joined with colons in the script
    assert script.contains('/path/one:/path/two:/path/three')
}
