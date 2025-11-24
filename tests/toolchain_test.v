module tests

import config

fn test_gcc_toolchain_compile_command_includes_debug_flags() {
    cfg := config.BuildConfig{
        debug: true
        optimize: false
        compiler: 'g++'
        toolchain: 'gcc'
        include_dirs: ['include']
        cflags: ['-DTEST']
    }
    tc := config.get_toolchain(cfg)

    target := config.TargetConfig(config.ToolConfig{
        name: 'test_tool'
        debug: true
    })

    cmd := tc.compile_command('test.cpp', 'test.o', &cfg, target)

    assert cmd.contains('-g')
    assert cmd.contains('-O0')
    assert cmd.contains('-Iinclude')
    assert cmd.contains('-DTEST')
    assert cmd.contains('-Wall')
    assert cmd.contains('-Wextra')
    assert cmd.contains('test.cpp')
    assert cmd.contains('-o test.o')
}

fn test_gcc_toolchain_compile_command_includes_optimize_flags() {
    cfg := config.BuildConfig{
        debug: false
        optimize: true
        compiler: 'g++'
        toolchain: 'gcc'
    }
    tc := config.get_toolchain(cfg)

    target := config.TargetConfig(config.ToolConfig{
        name: 'test_tool'
        optimize: true
    })

    cmd := tc.compile_command('src/main.cpp', 'build/main.o', &cfg, target)

    assert cmd.contains('-O3')
    assert !cmd.contains('-g')
    assert !cmd.contains('-O0')
}

fn test_clang_toolchain_compile_command() {
    cfg := config.BuildConfig{
        debug: true
        compiler: 'clang++'
        toolchain: 'clang'
    }
    tc := config.get_toolchain(cfg)

    target := config.TargetConfig(config.ToolConfig{
        name: 'test_tool'
        debug: true
    })

    cmd := tc.compile_command('main.cpp', 'main.o', &cfg, target)

    assert cmd.starts_with('clang++')
    assert cmd.contains('-c')
    assert cmd.contains('-g')
}

fn test_shared_lib_compile_includes_fpic() {
    cfg := config.BuildConfig{
        debug: false
        compiler: 'g++'
        toolchain: 'gcc'
    }
    tc := config.get_toolchain(cfg)

    target := config.TargetConfig(config.SharedLibConfig{
        name: 'mylib'
    })

    cmd := tc.compile_command('lib.cpp', 'lib.o', &cfg, target)

    assert cmd.contains('-fPIC')
}

fn test_tool_compile_does_not_include_fpic() {
    cfg := config.BuildConfig{
        debug: false
        compiler: 'g++'
        toolchain: 'gcc'
    }
    tc := config.get_toolchain(cfg)

    target := config.TargetConfig(config.ToolConfig{
        name: 'mytool'
    })

    cmd := tc.compile_command('main.cpp', 'main.o', &cfg, target)

    assert !cmd.contains('-fPIC')
}

fn test_shared_link_command_includes_shared_flag() {
    cfg := config.BuildConfig{
        compiler: 'g++'
        toolchain: 'gcc'
        bin_dir: 'bin'
    }
    tc := config.get_toolchain(cfg)

    lib_cfg := config.SharedLibConfig{
        name: 'mylib'
        libraries: ['dep']
    }

    cmd := tc.shared_link_command(['obj1.o', 'obj2.o'], 'mylib', 'bin/lib', &cfg, lib_cfg)

    assert cmd.contains('-shared')
    assert cmd.contains('obj1.o')
    assert cmd.contains('obj2.o')
    assert cmd.contains('-o bin/lib/mylib.so')
}

fn test_tool_link_command_links_libraries() {
    cfg := config.BuildConfig{
        compiler: 'g++'
        toolchain: 'gcc'
        bin_dir: 'bin'
        libraries: ['pthread']
    }
    tc := config.get_toolchain(cfg)

    tool_cfg := config.ToolConfig{
        name: 'mytool'
        libraries: ['core']
    }

    cmd := tc.tool_link_command(['main.o'], 'bin/tools/mytool', &cfg, tool_cfg)

    assert cmd.contains('main.o')
    assert cmd.contains('-lpthread')
    assert cmd.contains('-o bin/tools/mytool')
}

fn test_get_toolchain_defaults_to_gcc() {
    cfg := config.BuildConfig{
        toolchain: ''
        compiler: ''
    }
    tc := config.get_toolchain(cfg)

    assert tc.description() == 'gcc'
}

fn test_get_toolchain_returns_clang_when_specified() {
    cfg := config.BuildConfig{
        toolchain: 'clang'
        compiler: 'clang++'
    }
    tc := config.get_toolchain(cfg)

    assert tc.description() == 'clang'
}

fn test_compile_command_includes_lib_search_paths() {
    cfg := config.BuildConfig{
        compiler: 'g++'
        toolchain: 'gcc'
        lib_search_paths: ['/usr/local/lib', 'deps/lib']
    }
    tc := config.get_toolchain(cfg)

    target := config.TargetConfig(config.ToolConfig{name: 'test'})
    cmd := tc.compile_command('test.cpp', 'test.o', &cfg, target)

    assert cmd.contains('-L/usr/local/lib')
    assert cmd.contains('-Ldeps/lib')
}

fn test_target_specific_include_dirs_added() {
    cfg := config.BuildConfig{
        compiler: 'g++'
        toolchain: 'gcc'
        include_dirs: ['global/include']
    }
    tc := config.get_toolchain(cfg)

    target := config.TargetConfig(config.ToolConfig{
        name: 'test'
        include_dirs: ['tool/include']
    })

    cmd := tc.compile_command('test.cpp', 'test.o', &cfg, target)

    assert cmd.contains('-Iglobal/include')
    assert cmd.contains('-Itool/include')
}

fn test_target_specific_cflags_added() {
    cfg := config.BuildConfig{
        compiler: 'g++'
        toolchain: 'gcc'
        cflags: ['-DGLOBAL']
    }
    tc := config.get_toolchain(cfg)

    target := config.TargetConfig(config.ToolConfig{
        name: 'test'
        cflags: ['-DLOCAL']
    })

    cmd := tc.compile_command('test.cpp', 'test.o', &cfg, target)

    assert cmd.contains('-DGLOBAL')
    assert cmd.contains('-DLOCAL')
}
