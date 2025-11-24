#include <iostream>

// build-directive: unit-name(tools/main)
// build-directive: depends-units()
// build-directive: link()
// build-directive: out(tools/main)

int main() {
    std::cout << "Hello, {{project_name}}!" << std::endl;
    return 0;
}
