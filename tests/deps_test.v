module tests

import os
import deps
import config

fn test_extract_dependencies_finds_includes() {
    tmp := new_temp_dir('lana_deps')
    defer {
        os.rmdir_all(tmp) or {}
    }

    source_path := os.join_path(tmp, 'sample.cpp')
    source_content := '#include "foo/bar.h"\n#include <vector>\nint main() { return 0; }\n'
    os.write_file(source_path, source_content) or { panic(err) }

    parsed := deps.extract_dependencies(source_path) or { panic(err) }

    assert parsed.any(it.contains('foo/bar.h'))
    assert parsed.any(it.contains('vector'))
}

fn test_fetch_dependencies_runs_build_commands() {
    tmp := new_temp_dir('lana_fetch')
    defer {
        os.rmdir_all(tmp) or {}
    }

    dep_root := os.join_path(tmp, 'deps')
    mut cfg := config.BuildConfig{
        dependencies_dir: dep_root
        dependencies: [
            config.Dependency{
                name: 'local'
                extract_to: 'localpkg'
                build_cmds: ['touch built.txt']
            }
        ]
    }

    deps.fetch_dependencies(cfg) or { panic(err) }

    assert os.is_dir(os.join_path(dep_root, 'localpkg'))
    assert os.is_file(os.join_path(dep_root, 'localpkg', 'built.txt'))
}
