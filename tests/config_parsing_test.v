module tests

import os
import config

fn test_parse_bool_values_true() {
    tmp := new_temp_dir('lana_bool')
    defer {
        os.rmdir_all(tmp) or {}
    }

    config_path := os.join_path(tmp, 'config.ini')
    content := '[global]\nproject_name = test\ndebug = true\noptimize = yes\nverbose = 1\nparallel_compilation = on\n'
    os.write_file(config_path, content) or { panic(err) }

    cfg := config.parse_config_file(config_path) or { panic(err) }

    assert cfg.debug == true
    assert cfg.optimize == true
    assert cfg.verbose == true
    assert cfg.parallel_compilation == true
}

fn test_parse_bool_values_false() {
    tmp := new_temp_dir('lana_bool_false')
    defer {
        os.rmdir_all(tmp) or {}
    }

    config_path := os.join_path(tmp, 'config.ini')
    content := '[global]\nproject_name = test\ndebug = false\noptimize = no\nverbose = 0\nparallel_compilation = off\n'
    os.write_file(config_path, content) or { panic(err) }

    cfg := config.parse_config_file(config_path) or { panic(err) }

    assert cfg.debug == false
    assert cfg.optimize == false
    assert cfg.verbose == false
    assert cfg.parallel_compilation == false
}

fn test_parse_comma_separated_lists() {
    tmp := new_temp_dir('lana_lists')
    defer {
        os.rmdir_all(tmp) or {}
    }

    config_path := os.join_path(tmp, 'config.ini')
    content := '[global]\nproject_name = test\ninclude_dirs = include, src/include, deps/include\nlibraries = pthread, m, dl\n'
    os.write_file(config_path, content) or { panic(err) }

    cfg := config.parse_config_file(config_path) or { panic(err) }

    assert cfg.include_dirs.len == 3
    assert cfg.include_dirs.contains('include')
    assert cfg.include_dirs.contains('src/include')
    assert cfg.include_dirs.contains('deps/include')

    assert cfg.libraries.len == 3
    assert cfg.libraries.contains('pthread')
    assert cfg.libraries.contains('m')
    assert cfg.libraries.contains('dl')
}

fn test_parse_space_separated_cflags() {
    tmp := new_temp_dir('lana_cflags')
    defer {
        os.rmdir_all(tmp) or {}
    }

    config_path := os.join_path(tmp, 'config.ini')
    content := '[global]\nproject_name = test\ncflags = -Wall -Wextra -Werror -pedantic\nldflags = -pthread -lm\n'
    os.write_file(config_path, content) or { panic(err) }

    cfg := config.parse_config_file(config_path) or { panic(err) }

    assert cfg.cflags.contains('-Wall')
    assert cfg.cflags.contains('-Wextra')
    assert cfg.cflags.contains('-Werror')
    assert cfg.cflags.contains('-pedantic')

    assert cfg.ldflags.contains('-pthread')
    assert cfg.ldflags.contains('-lm')
}

fn test_parse_multiple_shared_libs() {
    tmp := new_temp_dir('lana_multi_libs')
    defer {
        os.rmdir_all(tmp) or {}
    }

    config_path := os.join_path(tmp, 'config.ini')
    content := '[global]\nproject_name = test\n\n[shared_libs]\nname = core\nsources = src/lib/core.cpp\n\n[shared_libs]\nname = utils\nsources = src/lib/utils.cpp\nlibraries = core\n'
    os.write_file(config_path, content) or { panic(err) }

    cfg := config.parse_config_file(config_path) or { panic(err) }

    assert cfg.shared_libs.len == 2
    assert cfg.shared_libs[0].name == 'core'
    assert cfg.shared_libs[1].name == 'utils'
    assert cfg.shared_libs[1].libraries.contains('core')
}

fn test_parse_multiple_tools() {
    tmp := new_temp_dir('lana_multi_tools')
    defer {
        os.rmdir_all(tmp) or {}
    }

    config_path := os.join_path(tmp, 'config.ini')
    content := '[global]\nproject_name = test\n\n[tools]\nname = cli\nsources = src/tools/cli.cpp\n\n[tools]\nname = server\nsources = src/tools/server.cpp\nlibraries = core\n'
    os.write_file(config_path, content) or { panic(err) }

    cfg := config.parse_config_file(config_path) or { panic(err) }

    assert cfg.tools.len == 2
    assert cfg.tools[0].name == 'cli'
    assert cfg.tools[1].name == 'server'
    assert cfg.tools[1].libraries.contains('core')
}

fn test_parse_dependencies_section() {
    tmp := new_temp_dir('lana_deps_parse')
    defer {
        os.rmdir_all(tmp) or {}
    }

    config_path := os.join_path(tmp, 'config.ini')
    content := '[global]\nproject_name = test\ndependencies_dir = external\n\n[dependencies]\nname = json\nurl = https://example.com/json.tar.gz\narchive = json.tar.gz\nextract_to = json\nchecksum = abc123\nbuild_cmds = mkdir build; cd build; cmake ..\n'
    os.write_file(config_path, content) or { panic(err) }

    cfg := config.parse_config_file(config_path) or { panic(err) }

    assert cfg.dependencies_dir == 'external'
    assert cfg.dependencies.len == 1
    assert cfg.dependencies[0].name == 'json'
    assert cfg.dependencies[0].url == 'https://example.com/json.tar.gz'
    assert cfg.dependencies[0].archive == 'json.tar.gz'
    assert cfg.dependencies[0].extract_to == 'json'
    assert cfg.dependencies[0].checksum == 'abc123'
    // "mkdir build; cd build; cmake .." splits into 3 commands
    assert cfg.dependencies[0].build_cmds.len == 3
    assert cfg.dependencies[0].build_cmds[0] == 'mkdir build'
    assert cfg.dependencies[0].build_cmds[1] == 'cd build'
    assert cfg.dependencies[0].build_cmds[2] == 'cmake ..'
}

fn test_config_inherits_global_values() {
    tmp := new_temp_dir('lana_inherit')
    defer {
        os.rmdir_all(tmp) or {}
    }

    config_path := os.join_path(tmp, 'config.ini')
    content := '[global]\nproject_name = test\ndebug = true\noptimize = false\ninclude_dirs = global/include\ncflags = -DGLOBAL\n\n[shared_libs]\nname = mylib\nsources = src/lib.cpp\n\n[tools]\nname = mytool\nsources = src/main.cpp\n'
    os.write_file(config_path, content) or { panic(err) }

    cfg := config.parse_config_file(config_path) or { panic(err) }

    // Shared lib inherits global values
    assert cfg.shared_libs[0].debug == true
    assert cfg.shared_libs[0].optimize == false
    assert cfg.shared_libs[0].include_dirs.contains('global/include')
    assert cfg.shared_libs[0].cflags.contains('-DGLOBAL')

    // Tool inherits global values
    assert cfg.tools[0].debug == true
    assert cfg.tools[0].optimize == false
    assert cfg.tools[0].include_dirs.contains('global/include')
    assert cfg.tools[0].cflags.contains('-DGLOBAL')
}

fn test_target_can_override_global_values() {
    tmp := new_temp_dir('lana_override')
    defer {
        os.rmdir_all(tmp) or {}
    }

    config_path := os.join_path(tmp, 'config.ini')
    content := '[global]\nproject_name = test\ndebug = true\noptimize = false\n\n[tools]\nname = release_tool\nsources = src/main.cpp\ndebug = false\noptimize = true\n'
    os.write_file(config_path, content) or { panic(err) }

    cfg := config.parse_config_file(config_path) or { panic(err) }

    // Tool overrides global debug/optimize
    assert cfg.tools[0].debug == false
    assert cfg.tools[0].optimize == true
}

fn test_parse_config_file_missing_file_returns_error() {
    if _ := config.parse_config_file('/nonexistent/config.ini') {
        assert false, 'Expected error for nonexistent file'
    }
    // If we get here without the or block catching an error, the test passes
}

fn test_comments_are_ignored() {
    tmp := new_temp_dir('lana_comments')
    defer {
        os.rmdir_all(tmp) or {}
    }

    config_path := os.join_path(tmp, 'config.ini')
    content := '# This is a comment\n[global]\n# Another comment\nproject_name = test\n# Comment at end\n'
    os.write_file(config_path, content) or { panic(err) }

    cfg := config.parse_config_file(config_path) or { panic(err) }

    assert cfg.project_name == 'test'
}

fn test_empty_lines_are_ignored() {
    tmp := new_temp_dir('lana_empty')
    defer {
        os.rmdir_all(tmp) or {}
    }

    config_path := os.join_path(tmp, 'config.ini')
    content := '\n\n[global]\n\nproject_name = test\n\n\n'
    os.write_file(config_path, content) or { panic(err) }

    cfg := config.parse_config_file(config_path) or { panic(err) }

    assert cfg.project_name == 'test'
}

fn test_quoted_values_are_trimmed() {
    tmp := new_temp_dir('lana_quoted')
    defer {
        os.rmdir_all(tmp) or {}
    }

    config_path := os.join_path(tmp, 'config.ini')
    content := '[global]\nproject_name = "my_project"\ncompiler = \'clang++\'\n'
    os.write_file(config_path, content) or { panic(err) }

    cfg := config.parse_config_file(config_path) or { panic(err) }

    assert cfg.project_name == 'my_project'
    assert cfg.compiler == 'clang++'
}
