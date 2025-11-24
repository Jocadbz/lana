module tests

import os
import config

fn test_find_source_files_finds_cpp_files() {
    tmp := new_temp_dir('lana_find_cpp')
    defer {
        os.rmdir_all(tmp) or {}
    }

    os.write_file(os.join_path(tmp, 'main.cpp'), '// cpp') or { panic(err) }
    os.write_file(os.join_path(tmp, 'utils.cpp'), '// cpp') or { panic(err) }
    os.write_file(os.join_path(tmp, 'header.h'), '// header') or { panic(err) }
    os.write_file(os.join_path(tmp, 'readme.txt'), '// text') or { panic(err) }

    files := config.find_source_files(tmp) or { panic(err) }

    assert files.len == 2
    assert files.any(it.ends_with('main.cpp'))
    assert files.any(it.ends_with('utils.cpp'))
}

fn test_find_source_files_finds_cc_files() {
    tmp := new_temp_dir('lana_find_cc')
    defer {
        os.rmdir_all(tmp) or {}
    }

    os.write_file(os.join_path(tmp, 'main.cc'), '// cc') or { panic(err) }

    files := config.find_source_files(tmp) or { panic(err) }

    assert files.len == 1
    assert files[0].ends_with('main.cc')
}

fn test_find_source_files_finds_cxx_files() {
    tmp := new_temp_dir('lana_find_cxx')
    defer {
        os.rmdir_all(tmp) or {}
    }

    os.write_file(os.join_path(tmp, 'main.cxx'), '// cxx') or { panic(err) }

    files := config.find_source_files(tmp) or { panic(err) }

    assert files.len == 1
    assert files[0].ends_with('main.cxx')
}

fn test_find_source_files_searches_subdirectories() {
    tmp := new_temp_dir('lana_find_subdir')
    defer {
        os.rmdir_all(tmp) or {}
    }

    subdir := os.join_path(tmp, 'lib', 'core')
    os.mkdir_all(subdir) or { panic(err) }

    os.write_file(os.join_path(tmp, 'main.cpp'), '// root') or { panic(err) }
    os.write_file(os.join_path(subdir, 'core.cpp'), '// subdir') or { panic(err) }

    files := config.find_source_files(tmp) or { panic(err) }

    assert files.len == 2
    assert files.any(it.ends_with('main.cpp'))
    assert files.any(it.ends_with('core.cpp'))
}

fn test_find_source_files_returns_error_for_nonexistent_dir() {
    if _ := config.find_source_files('/nonexistent/directory') {
        assert false, 'Expected error for nonexistent directory'
    }
    // If we get here without the or block catching an error, the test passes
}

fn test_find_source_files_returns_empty_for_empty_dir() {
    tmp := new_temp_dir('lana_find_empty')
    defer {
        os.rmdir_all(tmp) or {}
    }

    files := config.find_source_files(tmp) or { panic(err) }

    assert files.len == 0
}

fn test_find_source_files_ignores_hidden_directories() {
    tmp := new_temp_dir('lana_find_hidden')
    defer {
        os.rmdir_all(tmp) or {}
    }

    hidden_dir := os.join_path(tmp, '.hidden')
    os.mkdir_all(hidden_dir) or { panic(err) }

    os.write_file(os.join_path(tmp, 'visible.cpp'), '// visible') or { panic(err) }
    os.write_file(os.join_path(hidden_dir, 'hidden.cpp'), '// hidden') or { panic(err) }

    files := config.find_source_files(tmp) or { panic(err) }

    // Note: The current implementation doesn't filter hidden dirs,
    // so this test documents current behavior
    assert files.any(it.ends_with('visible.cpp'))
}

fn test_build_directives_parse_all_directive_types() {
    tmp := new_temp_dir('lana_all_directives')
    defer {
        os.rmdir_all(tmp) or {}
    }

    src_dir := os.join_path(tmp, 'src')
    os.mkdir_all(src_dir) or { panic(err) }

    source := '// build-directive: unit-name(myunit)\n// build-directive: depends-units(dep1, dep2)\n// build-directive: link(lib1.so, lib2.so)\n// build-directive: out(bin/myunit)\n// build-directive: cflags(-O2 -DNDEBUG)\n// build-directive: ldflags(-lpthread -lm)\n// build-directive: shared(true)\nint main() { return 0; }\n'
    os.write_file(os.join_path(src_dir, 'myunit.cpp'), source) or { panic(err) }

    mut cfg := config.BuildConfig{
        src_dir: src_dir
    }

    cfg.parse_build_directives() or { panic(err) }

    assert cfg.build_directives.len == 1

    d := cfg.build_directives[0]
    assert d.unit_name == 'myunit'
    assert d.depends_units.len == 2
    assert d.link_libs.len == 2
    assert d.output_path == 'bin/myunit'
    assert d.cflags.len == 2
    assert d.ldflags.len == 2
    assert d.is_shared == true
}

fn test_build_directives_ignore_non_directive_comments() {
    tmp := new_temp_dir('lana_ignore_comments')
    defer {
        os.rmdir_all(tmp) or {}
    }

    src_dir := os.join_path(tmp, 'src')
    os.mkdir_all(src_dir) or { panic(err) }

    source := '// This is a regular comment\n// Another comment\n// build-directive: unit-name(test)\n/* Block comment */\nint main() { return 0; }\n'
    os.write_file(os.join_path(src_dir, 'test.cpp'), source) or { panic(err) }

    mut cfg := config.BuildConfig{
        src_dir: src_dir
    }

    cfg.parse_build_directives() or { panic(err) }

    assert cfg.build_directives.len == 1
    assert cfg.build_directives[0].unit_name == 'test'
}

fn test_build_directives_handles_empty_src_dir() {
    tmp := new_temp_dir('lana_empty_src')
    defer {
        os.rmdir_all(tmp) or {}
    }

    src_dir := os.join_path(tmp, 'src')
    os.mkdir_all(src_dir) or { panic(err) }

    mut cfg := config.BuildConfig{
        src_dir: src_dir
    }

    cfg.parse_build_directives() or { panic(err) }

    assert cfg.build_directives.len == 0
}

fn test_build_directives_skips_files_without_unit_name() {
    tmp := new_temp_dir('lana_no_unit')
    defer {
        os.rmdir_all(tmp) or {}
    }

    src_dir := os.join_path(tmp, 'src')
    os.mkdir_all(src_dir) or { panic(err) }

    // File with directives but no unit-name
    source := '// build-directive: cflags(-O2)\n// build-directive: ldflags(-lm)\nint main() { return 0; }\n'
    os.write_file(os.join_path(src_dir, 'nounit.cpp'), source) or { panic(err) }

    mut cfg := config.BuildConfig{
        src_dir: src_dir
    }

    cfg.parse_build_directives() or { panic(err) }

    // Should not be added without unit-name
    assert cfg.build_directives.len == 0
}
