module tests

import config

fn test_default_config_has_expected_values() {
    cfg := config.default_config

    assert cfg.src_dir == 'src'
    assert cfg.build_dir == 'build'
    assert cfg.bin_dir == 'bin'
    assert cfg.toolchain == 'gcc'
    assert cfg.debug == true
    assert cfg.optimize == false
    assert cfg.verbose == false
    assert cfg.shared_libs.len == 0
    assert cfg.tools.len == 0
    assert cfg.dependencies.len == 0
}

fn test_shared_lib_config_has_default_output_dir() {
    lib := config.SharedLibConfig{
        name: 'test'
    }

    assert lib.output_dir == 'bin/lib'
}

fn test_tool_config_has_default_output_dir() {
    tool := config.ToolConfig{
        name: 'test'
    }

    assert tool.output_dir == 'bin/tools'
}

fn test_build_config_has_default_dependencies_dir() {
    cfg := config.BuildConfig{}

    assert cfg.dependencies_dir == 'dependencies'
}

fn test_build_config_has_parallel_compilation_enabled_by_default() {
    cfg := config.BuildConfig{}

    assert cfg.parallel_compilation == true
}

fn test_build_config_has_default_compiler() {
    cfg := config.BuildConfig{}

    assert cfg.compiler == 'g++'
}

fn test_get_target_config_values_for_shared_lib() {
    lib := config.SharedLibConfig{
        name: 'test'
        debug: true
        optimize: false
        verbose: true
        include_dirs: ['include']
        cflags: ['-DTEST']
    }

    target := config.TargetConfig(lib)
    is_shared, use_debug, use_optimize, use_verbose, includes, cflags := config.get_target_config_values(target)

    assert is_shared == true
    assert use_debug == true
    assert use_optimize == false
    assert use_verbose == true
    assert includes.contains('include')
    assert cflags.contains('-DTEST')
}

fn test_get_target_config_values_for_tool() {
    tool := config.ToolConfig{
        name: 'test'
        debug: false
        optimize: true
        verbose: false
        include_dirs: ['src']
        cflags: ['-O3']
    }

    target := config.TargetConfig(tool)
    is_shared, use_debug, use_optimize, use_verbose, includes, cflags := config.get_target_config_values(target)

    assert is_shared == false
    assert use_debug == false
    assert use_optimize == true
    assert use_verbose == false
    assert includes.contains('src')
    assert cflags.contains('-O3')
}

fn test_build_compiler_command_basic() {
    cfg := config.BuildConfig{
        compiler: 'g++'
        debug: true
        include_dirs: ['include']
        cflags: ['-DTEST']
    }

    cmd := config.build_compiler_command('src/main.cpp', 'build/main.o', cfg)

    assert cmd.starts_with('g++')
    assert cmd.contains('-c')
    assert cmd.contains('-Iinclude')
    assert cmd.contains('-g')
    assert cmd.contains('-O0')
    assert cmd.contains('-Wall')
    assert cmd.contains('-Wextra')
    assert cmd.contains('-DTEST')
    assert cmd.contains('src/main.cpp')
    assert cmd.contains('-o build/main.o')
}

fn test_build_compiler_command_optimized() {
    cfg := config.BuildConfig{
        compiler: 'clang++'
        debug: false
        optimize: true
    }

    cmd := config.build_compiler_command('main.cpp', 'main.o', cfg)

    assert cmd.starts_with('clang++')
    assert cmd.contains('-O3')
    assert !cmd.contains('-g')
}

fn test_build_compiler_command_default_optimization() {
    cfg := config.BuildConfig{
        compiler: 'g++'
        debug: false
        optimize: false
    }

    cmd := config.build_compiler_command('main.cpp', 'main.o', cfg)

    assert cmd.contains('-O2')
    assert !cmd.contains('-O3')
    assert !cmd.contains('-g')
}
