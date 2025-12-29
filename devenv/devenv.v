module devenv

import os
import config

// ShellType represents the detected shell type
pub enum ShellType {
    bash
    zsh
    fish
    sh
    unknown
}

// DevEnvConfig holds configuration for the temporary dev environment
pub struct DevEnvConfig {
pub:
    lib_search_paths []string
    project_name     string
    bin_dir          string
}

// detect_shell detects the current running shell from environment variables
pub fn detect_shell() ShellType {
    // Try SHELL environment variable first (user's default shell)
    shell_env := os.getenv('SHELL')
    if shell_env != '' {
        return parse_shell_name(shell_env)
    }
    
    // Fallback: try to get parent process shell (more accurate for current shell)
    // This is a best-effort approach
    return ShellType.unknown
}

// parse_shell_name extracts shell type from a shell path or name
pub fn parse_shell_name(shell_path string) ShellType {
    // Get the basename of the shell path
    mut shell_name := shell_path
    if shell_path.contains('/') {
        parts := shell_path.split('/')
        if parts.len > 0 {
            shell_name = parts[parts.len - 1]
        }
    }
    
    return match shell_name {
        'bash' { ShellType.bash }
        'zsh' { ShellType.zsh }
        'fish' { ShellType.fish }
        'sh' { ShellType.sh }
        else { ShellType.unknown }
    }
}

// shell_type_to_string converts ShellType to a human-readable string
pub fn shell_type_to_string(shell ShellType) string {
    return match shell {
        .bash { 'bash' }
        .zsh { 'zsh' }
        .fish { 'fish' }
        .sh { 'sh' }
        .unknown { 'unknown' }
    }
}

// get_devenv_config extracts dev environment config from BuildConfig
pub fn get_devenv_config(build_config config.BuildConfig) DevEnvConfig {
    // Use devenv-specific paths if configured, otherwise fall back to lib_search_paths
    mut lib_paths := []string{}
    
    // Priority: devenv_lib_paths > lib_search_paths
    if build_config.devenv_lib_paths.len > 0 {
        lib_paths = build_config.devenv_lib_paths.clone()
    } else {
        lib_paths = build_config.lib_search_paths.clone()
    }
    
    // Add default library paths if not already present
    default_lib_path := os.join_path(build_config.bin_dir, 'lib')
    if default_lib_path !in lib_paths {
        lib_paths << default_lib_path
    }
    
    return DevEnvConfig{
        lib_search_paths: lib_paths
        project_name: build_config.project_name
        bin_dir: build_config.bin_dir
    }
}

// generate_activation_script generates shell-specific activation script content
pub fn generate_activation_script(shell ShellType, devenv_config DevEnvConfig) !string {
    // Get absolute paths for lib_search_paths
    cwd := os.getwd()
    mut absolute_paths := []string{}
    for path in devenv_config.lib_search_paths {
        if os.is_abs_path(path) {
            absolute_paths << path
        } else {
            absolute_paths << os.join_path(cwd, path)
        }
    }
    
    paths_str := absolute_paths.join(':')
    project_name := if devenv_config.project_name != '' {
        devenv_config.project_name
    } else {
        'lana-project'
    }
    
    return match shell {
        .bash { generate_bash_script(paths_str, project_name) }
        .zsh { generate_zsh_script(paths_str, project_name) }
        .fish { generate_fish_script(paths_str, project_name) }
        .sh { generate_sh_script(paths_str, project_name) }
        .unknown { error('Cannot generate activation script for unknown shell. Please specify your shell manually.') }
    }
}

// generate_bash_script creates a bash activation script
fn generate_bash_script(lib_paths string, project_name string) string {
    return '# Lana temporary development environment activation script (bash)
# Source this file to activate the environment: source <(lana devenv)

# Save original values for deactivation
_LANA_OLD_PS1="\${PS1:-}"
_LANA_OLD_LD_LIBRARY_PATH="\${LD_LIBRARY_PATH:-}"
_LANA_ACTIVE=1

# Update LD_LIBRARY_PATH to include project library paths
if [ -z "\$LD_LIBRARY_PATH" ]; then
    export LD_LIBRARY_PATH="${lib_paths}"
else
    export LD_LIBRARY_PATH="${lib_paths}:\$LD_LIBRARY_PATH"
fi

# Modify prompt to show we\'re in a Lana dev environment
export PS1="(Lana\'s temp environment: ${project_name}) \${PS1}"

# Define deactivate function
deactivate() {
    if [ -n "\$_LANA_ACTIVE" ]; then
        # Restore original LD_LIBRARY_PATH
        if [ -n "\$_LANA_OLD_LD_LIBRARY_PATH" ]; then
            export LD_LIBRARY_PATH="\$_LANA_OLD_LD_LIBRARY_PATH"
        else
            unset LD_LIBRARY_PATH
        fi
        
        # Restore original PS1
        export PS1="\$_LANA_OLD_PS1"
        
        # Clean up
        unset _LANA_OLD_PS1
        unset _LANA_OLD_LD_LIBRARY_PATH
        unset _LANA_ACTIVE
        unset -f deactivate
        
        echo "Lana development environment deactivated."
    fi
}

echo "Lana development environment activated for ${project_name}."
echo "Library search paths: ${lib_paths}"
echo "Run \'deactivate\' to exit the environment."
'
}

// generate_zsh_script creates a zsh activation script
fn generate_zsh_script(lib_paths string, project_name string) string {
    return '# Lana temporary development environment activation script (zsh)
# Source this file to activate the environment: source <(lana devenv)

# Save original values for deactivation
_LANA_OLD_PS1="\${PS1:-}"
_LANA_OLD_LD_LIBRARY_PATH="\${LD_LIBRARY_PATH:-}"
_LANA_ACTIVE=1

# Update LD_LIBRARY_PATH to include project library paths
if [ -z "\$LD_LIBRARY_PATH" ]; then
    export LD_LIBRARY_PATH="${lib_paths}"
else
    export LD_LIBRARY_PATH="${lib_paths}:\$LD_LIBRARY_PATH"
fi

# Modify prompt to show we\'re in a Lana dev environment
export PS1="(Lana\'s temp environment: ${project_name}) \${PS1}"

# Define deactivate function
deactivate() {
    if [ -n "\$_LANA_ACTIVE" ]; then
        # Restore original LD_LIBRARY_PATH
        if [ -n "\$_LANA_OLD_LD_LIBRARY_PATH" ]; then
            export LD_LIBRARY_PATH="\$_LANA_OLD_LD_LIBRARY_PATH"
        else
            unset LD_LIBRARY_PATH
        fi
        
        # Restore original PS1
        export PS1="\$_LANA_OLD_PS1"
        
        # Clean up
        unset _LANA_OLD_PS1
        unset _LANA_OLD_LD_LIBRARY_PATH
        unset _LANA_ACTIVE
        unset -f deactivate
        
        echo "Lana development environment deactivated."
    fi
}

echo "Lana development environment activated for ${project_name}."
echo "Library search paths: ${lib_paths}"
echo "Run \'deactivate\' to exit the environment."
'
}

// generate_fish_script creates a fish shell activation script
fn generate_fish_script(lib_paths string, project_name string) string {
    return '# Lana temporary development environment activation script (fish)
# Source this file to activate the environment: source (lana devenv | psub)

# Save original values for deactivation
if set -q LD_LIBRARY_PATH
    set -gx _LANA_OLD_LD_LIBRARY_PATH ${"$"}LD_LIBRARY_PATH
else
    set -gx _LANA_OLD_LD_LIBRARY_PATH ""
end

set -gx _LANA_ACTIVE 1

# Update LD_LIBRARY_PATH to include project library paths
if test -z "${"$"}LD_LIBRARY_PATH"
    set -gx LD_LIBRARY_PATH "${lib_paths}"
else
    set -gx LD_LIBRARY_PATH "${lib_paths}:${"$"}LD_LIBRARY_PATH"
end

# Store original fish_prompt function
functions -c fish_prompt _lana_old_fish_prompt

# Override fish_prompt to show Lana environment
function fish_prompt
    echo -n "(Lana\'s temp environment: ${project_name}) "
    _lana_old_fish_prompt
end

# Define deactivate function
function deactivate
    if set -q _LANA_ACTIVE
        # Restore original LD_LIBRARY_PATH
        if test -n "${"$"}_LANA_OLD_LD_LIBRARY_PATH"
            set -gx LD_LIBRARY_PATH ${"$"}_LANA_OLD_LD_LIBRARY_PATH
        else
            set -e LD_LIBRARY_PATH
        end
        
        # Restore original fish_prompt
        functions -e fish_prompt
        functions -c _lana_old_fish_prompt fish_prompt
        functions -e _lana_old_fish_prompt
        
        # Clean up
        set -e _LANA_OLD_LD_LIBRARY_PATH
        set -e _LANA_ACTIVE
        functions -e deactivate
        
        echo "Lana development environment deactivated."
    end
end

echo "Lana development environment activated for ${project_name}."
echo "Library search paths: ${lib_paths}"
echo "Run \'deactivate\' to exit the environment."
'
}

// generate_sh_script creates a POSIX sh activation script
fn generate_sh_script(lib_paths string, project_name string) string {
    return '# Lana temporary development environment activation script (sh)
# Source this file to activate the environment: . $(lana devenv --output-file)

# Save original values for deactivation
_LANA_OLD_PS1="${'$'}PS1"
_LANA_OLD_LD_LIBRARY_PATH="${'$'}LD_LIBRARY_PATH"
_LANA_ACTIVE=1

# Update LD_LIBRARY_PATH to include project library paths
if [ -z "${'$'}LD_LIBRARY_PATH" ]; then
    LD_LIBRARY_PATH="${lib_paths}"
else
    LD_LIBRARY_PATH="${lib_paths}:${'$'}LD_LIBRARY_PATH"
fi
export LD_LIBRARY_PATH

# Modify prompt to show we\'re in a Lana dev environment
PS1="(Lana\'s temp environment: ${project_name}) ${'$'}PS1"
export PS1

# Define deactivate function
deactivate() {
    if [ -n "${'$'}_LANA_ACTIVE" ]; then
        # Restore original LD_LIBRARY_PATH
        if [ -n "${'$'}_LANA_OLD_LD_LIBRARY_PATH" ]; then
            LD_LIBRARY_PATH="${'$'}_LANA_OLD_LD_LIBRARY_PATH"
            export LD_LIBRARY_PATH
        else
            unset LD_LIBRARY_PATH
        fi
        
        # Restore original PS1
        PS1="${'$'}_LANA_OLD_PS1"
        export PS1
        
        # Clean up
        unset _LANA_OLD_PS1
        unset _LANA_OLD_LD_LIBRARY_PATH
        unset _LANA_ACTIVE
        
        echo "Lana development environment deactivated."
    fi
}

echo "Lana development environment activated for ${project_name}."
echo "Library search paths: ${lib_paths}"
echo "Run \'deactivate\' to exit the environment."
'
}

// activate_devenv is the main entry point for the devenv command
pub fn activate_devenv(build_config config.BuildConfig, shell_override string) ! {
    // Detect shell or use override
    mut shell := detect_shell()
    if shell_override != '' {
        shell = parse_shell_name(shell_override)
        if shell == .unknown {
            return error('Unknown shell specified: ${shell_override}. Supported shells: bash, zsh, fish, sh')
        }
    }
    
    if shell == .unknown {
        // Try to provide helpful message
        eprintln('Could not detect your shell automatically.')
        eprintln('Please specify your shell using: lana devenv --shell <bash|zsh|fish|sh>')
        eprintln('Or set the SHELL environment variable.')
        return error('Shell detection failed')
    }
    
    // Get dev environment configuration
    devenv_config := get_devenv_config(build_config)
    
    // Generate and print the activation script
    script := generate_activation_script(shell, devenv_config)!
    print(script)
}

// print_devenv_info prints information about the dev environment without activating
pub fn print_devenv_info(build_config config.BuildConfig) {
    devenv_config := get_devenv_config(build_config)
    shell := detect_shell()
    
    println('Lana Temporary Development Environment')
    println('======================================')
    println('')
    println('Detected shell: ${shell_type_to_string(shell)}')
    println('Project name: ${devenv_config.project_name}')
    println('Library search paths:')
    for path in devenv_config.lib_search_paths {
        println('  - ${path}')
    }
    println('')
    println('To activate the environment:')
    
    match shell {
        .bash, .zsh { println('  source <(lana devenv)') }
        .fish { println('  source (lana devenv | psub)') }
        .sh { println('  eval "$(lana devenv)"') }
        .unknown { 
            println('  # Shell not detected. Use --shell to specify:')
            println('  source <(lana devenv --shell bash)')
        }
    }
    println('')
    println('To deactivate: run \'deactivate\' in your shell')
}
