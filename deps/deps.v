module deps

import os
import config
import os.cmdline

pub fn extract_dependencies(source_file string) ![]string {
    mut dependencies := []string{}
    content := os.read_file(source_file) or { return []string{} }
    
    mut in_string := false
    mut current_string_char := rune(0)
    mut i := 0
    
    for i < content.len {
        c := content[i]
        
        // Handle string literals
        if (c == `"` || c == `'`) && !in_string {
            in_string = true
            current_string_char = c
        } else if c == current_string_char && in_string {
            in_string = false
            current_string_char = rune(0)
        } else if !in_string {
            if c == `#` && i + 1 < content.len && content[i + 1] == `i` {
                // Found #include
                i += 7 // skip "#include"
                for i < content.len && content[i].is_space() {
                    i++
                }
                
                if i < content.len && (content[i] == `"` || content[i] == `<`) {
                    mut quote_char := content[i]
                    i++
                    mut include_path := []u8{}
                    
                    for i < content.len && content[i] != quote_char {
                        include_path << content[i]
                        i++
                    }
                    
                    if include_path.len > 0 {
                        include_name := include_path.bytestr()
                        if include_name.contains('/') || include_name.contains('\\') {
                            // Relative path
                            dependencies << include_name
                        } else {
                            // System include - we could search standard paths
                            // but for now just add the name
                            dependencies << include_name
                        }
                    }
                }
            }
        }
        
        i++
    }
    
    return dependencies
}

pub fn generate_dependency_file(source_file string, object_file string, dep_file string) {
    dependencies := extract_dependencies(source_file) or { return }
    
    mut content := '${object_file}: ${source_file}\n'
    for dep in dependencies {
        content += '\t${dep}\n'
    }
    
    os.write_file(dep_file, content) or { }
}

// Fetch and extract dependencies declared in the build config
pub fn fetch_dependencies(build_config config.BuildConfig) ! {
    if build_config.dependencies.len == 0 {
        println('No dependencies declared in config')
        return
    }

    tmp_dir := os.join_path(build_config.dependencies_dir, 'tmp')
    os.mkdir_all(tmp_dir) or { return error('Failed to create tmp dir: ${err}') }
    deps_dir := build_config.dependencies_dir
    os.mkdir_all(deps_dir) or { return error('Failed to create dependencies dir: ${err}') }

    for dep in build_config.dependencies {
        if dep.name == '' {
            println('Skipping unnamed dependency')
            continue
        }

        println('Processing dependency: ${dep.name}')
        println('  parsed: url="${dep.url}", archive="${dep.archive}", extract_to="${dep.extract_to}"')

        if dep.url.trim_space() == '' {
            return error('Dependency ${dep.name} has empty url in config')
        }

        // Decide if URL is a git repo or an archive
        is_git := dep.url.ends_with('.git') || dep.url.starts_with('git://')

        extract_to := if dep.extract_to != '' { os.join_path(deps_dir, dep.extract_to) } else { os.join_path(deps_dir, dep.name) }

        if is_git {
            // Clone repository
            if os.is_dir(extract_to) {
                println('Dependency already cloned at ${extract_to}, skipping')
                continue
            }
            cmd := 'git clone --depth 1 ${dep.url} ${extract_to}'
            println('Running: ${cmd}')
            res := os.execute(cmd)
            if res.exit_code != 0 {
                return error('Failed to clone ${dep.url}: ${res.output}')
            }
            continue
        }

        // Archive download path
        archive_name := if dep.archive != '' { dep.archive } else { os.file_name(dep.url) }
        archive_path := os.join_path(tmp_dir, archive_name)

        if !os.is_file(archive_path) {
            println('Downloading ${dep.url} -> ${archive_path}')
            // Prefer curl, fall back to wget
            mut res := os.execute('curl -L -o ${archive_path} ${dep.url}')
            if res.exit_code != 0 {
                res = os.execute('wget -O ${archive_path} ${dep.url}')
                if res.exit_code != 0 {
                    return error('Failed to download ${dep.url}: ${res.output}')
                }
            }
        } else {
            println('Archive already exists: ${archive_path}')
        }

        // Optionally verify checksum
        if dep.checksum != '' {
            // Use sha256sum if available
            res := os.execute('sha256sum ${archive_path}')
            if res.exit_code != 0 {
                println('Warning: sha256sum not available to verify checksum')
            } else {
                parts := res.output.split(' ')
                if parts.len > 0 && parts[0].trim_space() != dep.checksum {
                    return error('Checksum mismatch for ${archive_path}')
                }
            }
        }

        // Extract archive
        if os.is_dir(extract_to) {
            println('Already extracted to ${extract_to}, skipping')
            continue
        }
        os.mkdir_all(extract_to) or { return error('Failed to create ${extract_to}: ${err}') }

        // Basic extraction handling by extension
        lower := archive_path.to_lower()
        if lower.ends_with('.tar.gz') || lower.ends_with('.tgz') || lower.ends_with('.tar.xz') || lower.ends_with('.tar') {
            cmd := 'tar -xf ${archive_path} -C ${deps_dir}'
            println('Extracting with: ${cmd}')
            res := os.execute(cmd)
            if res.exit_code != 0 {
                return error('Failed to extract ${archive_path}: ${res.output}')
            }
            // If the archive created a top-level dir, move/rename it to extract_to if needed
            // We won't attempt to be clever here; caller should set extract_to to match archive content.
        } else if lower.ends_with('.zip') {
            cmd := 'unzip -q ${archive_path} -d ${extract_to}'
            println('Extracting zip with: ${cmd}')
            res := os.execute(cmd)
            if res.exit_code != 0 {
                return error('Failed to unzip ${archive_path}: ${res.output}')
            }
        } else {
            println('Unknown archive format for ${archive_path}, skipping extraction')
        }

        // Run build commands if provided, otherwise run package-specific defaults
        if dep.build_cmds.len > 0 {
            for cmd_line in dep.build_cmds {
                println('Running build command for ${dep.name}: ${cmd_line}')
                // run in extract_to
                old_cwd := os.getwd()
                os.chdir(extract_to) or { return error('Failed to chdir: ${err}') }
                res := os.execute(cmd_line)
                os.chdir(old_cwd) or { }
                if res.exit_code != 0 {
                    return error('Build command failed for ${dep.name}: ${res.output}')
                }
            }
        } else {
            // default build steps for known dependencies
            match dep.name {
                'zlib' {
                    println('Building zlib...')
                    old_cwd := os.getwd()
                    os.chdir(extract_to) or { return error('Failed to chdir: ${err}') }
                    mut res := os.execute('./configure')
                    if res.exit_code != 0 { os.chdir(old_cwd) or {} ; return error('zlib configure failed: ${res.output}') }
                    res = os.execute('make')
                    os.chdir(old_cwd) or {}
                    if res.exit_code != 0 { return error('zlib make failed: ${res.output}') }
                }
                'sockpp' {
                    println('Building sockpp...')
                    // Try cmake build in project dir (common layout)
                    build_dir := os.join_path(extract_to, 'build')
                    os.mkdir_all(build_dir) or { return error('Failed to create build dir: ${err}') }
                    old_cwd := os.getwd()
                    os.chdir(extract_to) or { return error('Failed to chdir: ${err}') }
                    mut res := os.execute('cmake -Bbuild .')
                    if res.exit_code != 0 { os.chdir(old_cwd) or {} ; return error('sockpp cmake failed: ${res.output}') }
                    res = os.execute('cmake --build build')
                    os.chdir(old_cwd) or {}
                    if res.exit_code != 0 { return error('sockpp build failed: ${res.output}') }
                }
                'shaderc' {
                    println('Building shaderc (invoke update script + ninja)')
                    old_cwd := os.getwd()
                    os.chdir(extract_to) or { return error('Failed to chdir: ${err}') }
                    mut res := os.execute('./update_shaderc_sources.py')
                    if res.exit_code != 0 { os.chdir(old_cwd) or {} ; return error('shaderc update failed: ${res.output}') }
                    // create build dir
                    build_dir := 'build-$(date +%s)'
                    os.mkdir_all(build_dir) or { os.chdir(old_cwd) or {} ; return error('Failed to create shaderc build dir') }
                    os.chdir(build_dir) or { os.chdir(old_cwd) or {} ; return error('Failed to chdir to shaderc build dir') }
                    res = os.execute('cmake -GNinja -DCMAKE_BUILD_TYPE=Release ../src/')
                    if res.exit_code != 0 { os.chdir(old_cwd) or {} ; return error('shaderc cmake failed: ${res.output}') }
                    res = os.execute('ninja')
                    os.chdir(old_cwd) or {}
                    if res.exit_code != 0 { return error('shaderc ninja failed: ${res.output}') }
                    // attempt to copy glslc to dependencies/shaderc/bin (best-effort)
                    glslc_path := os.join_path(extract_to, build_dir, 'glslc', 'glslc')
                    out_dir := os.join_path(build_config.dependencies_dir, dep.extract_to)
                    os.mkdir_all(os.join_path(out_dir, 'bin')) or { }
                    if os.is_file(glslc_path) {
                        os.cp(glslc_path, os.join_path(out_dir, 'bin', 'glslc')) or { println('Warning: failed to copy glslc: ${err}') }
                    }
                }
                else {}
            }
        }
    }
    println('Dependencies processed successfully')
    // Clean up temporary download directory
    if os.is_dir(tmp_dir) {
        os.rmdir_all(tmp_dir) or { println('Warning: Failed to remove tmp dir: ${err}') }
    }
}