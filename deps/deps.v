module deps

import os
import config

pub fn extract_dependencies(source_file string) ![]string {
    mut dependencies := []string{}
    content := os.read_file(source_file) or {
        return error('Failed to read source file ${source_file}: ${err}')
    }
    
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
            if c == `#` && i + 8 <= content.len && content[i..].starts_with('#include') {
                i += '#include'.len
                for i < content.len && content[i].is_space() {
                    i++
                }

                if i < content.len && (content[i] == `"` || content[i] == `<` || content[i] == `'`) {
                    opening := content[i]
                    closing := match opening {
                        `"` { `"` }
                        `'` { `'` }
                        `<` { `>` }
                        else { opening }
                    }
                    i++
                    mut include_path := []u8{}

                    for i < content.len && content[i] != closing {
                        include_path << content[i]
                        i++
                    }

                    if include_path.len > 0 {
                        include_name := include_path.bytestr()
                        if include_name.contains('/') || include_name.contains('\\') {
                            dependencies << include_name
                        } else {
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
    dependencies := extract_dependencies(source_file) or {
        eprintln('Warning: Failed to extract dependencies from ${source_file}: ${err}')
        return
    }
    
    mut content := '${object_file}: ${source_file}\n'
    for dep in dependencies {
        content += '\t${dep}\n'
    }
    
    os.write_file(dep_file, content) or {
        eprintln('Warning: Failed to write dependency file ${dep_file}: ${err}')
    }
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
        if build_config.debug || build_config.verbose {
            println('  parsed: url="${dep.url}", archive="${dep.archive}", extract_to="${dep.extract_to}"')
        }

        // Allow dependencies with only a name. If no URL is provided, skip
        // download/extract/clone steps and only run any provided build_cmds.
        url_trim := dep.url.trim_space()

        // Decide if URL is a git repo or an archive (only if URL present)
        is_git := url_trim != '' && (url_trim.ends_with('.git') || url_trim.starts_with('git://'))

        extract_to := if dep.extract_to != '' { os.join_path(deps_dir, dep.extract_to) } else { os.join_path(deps_dir, dep.name) }

        if url_trim == '' {
            println('No url provided for ${dep.name}, skipping download/extract; will only run build_cmds if present')
        } else {
            if is_git {
                // Clone repository if needed
                if os.is_dir(extract_to) {
                    if build_config.debug || build_config.verbose {
                        println('Dependency already cloned at ${extract_to}, skipping clone')
                    }
                } else {
                    cmd := 'git clone --depth 1 ${url_trim} ${extract_to}'
                    if build_config.debug || build_config.verbose {
                        println('Running: ${cmd}')
                    }
                    code := os.system(cmd)
                    if code != 0 {
                        return error('Failed to clone ${url_trim}: exit ${code}')
                    }
                }
            } else {
                // Archive download path
                archive_name := if dep.archive != '' { dep.archive } else { os.file_name(url_trim) }
                archive_path := os.join_path(tmp_dir, archive_name)

                if !os.is_file(archive_path) {
                    println('Downloading ${url_trim} -> ${archive_path}')
                    // Prefer curl, fall back to wget
                    mut code := os.system('curl -L -o ${archive_path} ${url_trim}')
                    if code != 0 {
                        code = os.system('wget -O ${archive_path} ${url_trim}')
                        if code != 0 {
                            return error('Failed to download ${url_trim}: curl/wget exit ${code}')
                        }
                    }
                } else {
                    if build_config.debug || build_config.verbose {
                        println('Archive already exists: ${archive_path}')
                    }
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
                    if build_config.debug || build_config.verbose {
                        println('Already extracted to ${extract_to}, skipping')
                    }
                } else {
                    os.mkdir_all(extract_to) or { return error('Failed to create ${extract_to}: ${err}') }

                    // Basic extraction handling by extension
                    lower := archive_path.to_lower()
                    if lower.ends_with('.tar.gz') || lower.ends_with('.tgz') || lower.ends_with('.tar.xz') || lower.ends_with('.tar') {
                        cmd := 'tar -xf ${archive_path} -C ${deps_dir}'
                        if build_config.debug || build_config.verbose {
                            println('Extracting with: ${cmd}')
                        }
                        code := os.system(cmd)
                        if code != 0 {
                            return error('Failed to extract ${archive_path}: exit ${code}')
                        }
                        // If the archive created a top-level dir, caller should set extract_to to match archive content.
                    } else if lower.ends_with('.zip') {
                        cmd := 'unzip -q ${archive_path} -d ${extract_to}'
                        if build_config.debug || build_config.verbose {
                            println('Extracting zip with: ${cmd}')
                        }
                        code := os.system(cmd)
                        if code != 0 {
                            return error('Failed to unzip ${archive_path}: exit ${code}')
                        }
                    } else {
                        println('Unknown archive format for ${archive_path}, skipping extraction')
                    }
                }
            }
        }

        // Run build commands if provided, otherwise run package-specific defaults
        if dep.build_cmds.len > 0 {
            // Choose where to run build commands:
            // - If extract_to was provided, run inside deps/<extract_to> (create it if missing)
            // - Otherwise run from project root (os.getwd())
            mut run_dir := os.getwd()
            if dep.extract_to != '' {
                run_dir = os.join_path(deps_dir, dep.extract_to)
                os.mkdir_all(run_dir) or { println('Warning: Failed to create build dir ${run_dir}: ${err}') }
            }

            for cmd_line in dep.build_cmds {
                if build_config.debug || build_config.verbose {
                    println('Running build command for ${dep.name}: ${cmd_line}')
                }
                old_cwd := os.getwd()
                os.chdir(run_dir) or { return error('Failed to chdir: ${err}') }
                code := os.system(cmd_line)
                os.chdir(old_cwd) or { }
                if code != 0 {
                    return error('Build command failed for ${dep.name}: exit ${code}')
                }
            }
        } else {
            // No package-specific defaults: if build_cmds are absent we do nothing.
            if build_config.verbose {
                println('No default build steps for dependency: ${dep.name}; provide build_cmds in config.ini to build it')
            }
        }
    }
    println('Dependencies processed successfully')
    // Clean up temporary download directory
    if os.is_dir(tmp_dir) {
        os.rmdir_all(tmp_dir) or { println('Warning: Failed to remove tmp dir: ${err}') }
    }
}