module tests

import os
import config

fn test_parse_config_file_reads_sections() {
    tmp := new_temp_dir('lana_config')
    defer {
        os.rmdir_all(tmp) or {}
    }

    config_path := os.join_path(tmp, 'config.ini')
    config_content := '[global]\nproject_name = sample\nsrc_dir = src\ndebug = false\noptimize = true\nparallel_compilation = false\ninclude_dirs = include, external/include\nlibraries = cli\ncflags = -Wall -Wextra\n\n[shared_libs]\nname = core\nsources = src/lib/core.cpp\ninclude_dirs = include\ncflags = -fPIC\nlibraries = \n\n[tools]\nname = sample\nsources = src/main.cpp\nlibraries = core\n'
    os.write_file(config_path, config_content) or { panic(err) }

    cfg := config.parse_config_file(config_path) or { panic(err) }

    assert cfg.project_name == 'sample'
    assert cfg.src_dir == 'src'
    assert !cfg.debug
    assert cfg.optimize
    assert !cfg.parallel_compilation
    assert cfg.include_dirs.len == 2
    assert cfg.include_dirs.contains('include')
    assert cfg.include_dirs.contains('external/include')
    assert cfg.cflags.contains('-Wall')
    assert cfg.cflags.contains('-Wextra')
    assert cfg.libraries == ['cli']
    assert cfg.shared_libs.len == 1
    shared_cfg := cfg.shared_libs[0]
    assert shared_cfg.name == 'core'
    assert shared_cfg.include_dirs.contains('include')
    assert shared_cfg.cflags.contains('-fPIC')
    assert cfg.tools.len == 1
    tool := cfg.tools[0]
    assert tool.name == 'sample'
    assert tool.libraries == ['core']
}

fn test_parse_build_directives_extracts_units() {
    tmp := new_temp_dir('lana_directives')
    defer {
        os.rmdir_all(tmp) or {}
    }

    src_dir := os.join_path(tmp, 'src')
    tool_dir := os.join_path(src_dir, 'tools')
    lib_dir := os.join_path(src_dir, 'lib')
    os.mkdir_all(tool_dir) or { panic(err) }
    os.mkdir_all(lib_dir) or { panic(err) }

    tool_source := '// build-directive: unit-name(tools/example)\n// build-directive: depends-units(lib/cli)\n// build-directive: link(cli.so)\n// build-directive: out(tools/example)\n// build-directive: cflags(-DTEST)\n// build-directive: ldflags(-pthread)\n// build-directive: shared(false)\n'
    os.write_file(os.join_path(tool_dir, 'example.cpp'), tool_source) or { panic(err) }

    shared_source := '// build-directive: unit-name(lib/cli)\n// build-directive: depends-units()\n// build-directive: link()\n// build-directive: out(lib/cli)\n// build-directive: shared(true)\n'
    os.write_file(os.join_path(lib_dir, 'cli.cpp'), shared_source) or { panic(err) }

    mut cfg := config.BuildConfig{
        project_name: 'sample'
        src_dir: src_dir
        build_dir: os.join_path(tmp, 'build')
        bin_dir: os.join_path(tmp, 'bin')
    }

    cfg.parse_build_directives() or { panic(err) }

    assert cfg.build_directives.len == 2

    mut tool_found := false
    mut shared_found := false
    for directive in cfg.build_directives {
        if directive.unit_name == 'tools/example' {
            tool_found = true
            assert directive.depends_units == ['lib/cli']
            assert directive.link_libs == ['cli.so']
            assert directive.output_path == 'tools/example'
            assert directive.cflags.contains('-DTEST')
            assert directive.ldflags.contains('-pthread')
            assert !directive.is_shared
        }
        if directive.unit_name == 'lib/cli' {
            shared_found = true
            assert directive.is_shared
        }
    }

    assert tool_found
    assert shared_found
}
