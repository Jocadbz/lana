module deps

import os

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