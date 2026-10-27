// douzero-cli: the same core behind a JSON-lines stdin/stdout loop.
// Used by reference/scripts/check_cpp.py to cross-check against the Python core.
//
//   douzero-cli [models_dir]   (default: game/models next to this repo)
#include <iostream>
#include <string>

#include "core.hpp"

int main(int argc, char** argv) {
    std::string models = argc > 1 ? argv[1] : DOUZERO_DEFAULT_MODELS;
    std::unique_ptr<dz::Core> core;
    try {
        core = std::make_unique<dz::Core>(dz::Policy::from_dir(models));
    } catch (const std::exception& e) {
        std::cerr << "douzero-cli: " << e.what() << "\n";
        return 1;
    }
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.find_first_not_of(" \t\r") == std::string::npos) continue;
        std::cout << core->handle_line(line) << std::endl;
    }
}
