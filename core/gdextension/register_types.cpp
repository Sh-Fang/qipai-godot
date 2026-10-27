#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

#include "douzero_core.hpp"

using namespace godot;

static void initialize(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) GDREGISTER_CLASS(DouZeroCore);
}

static void uninitialize(ModuleInitializationLevel) {}

extern "C" GDExtensionBool GDE_EXPORT douzero_library_init(GDExtensionInterfaceGetProcAddress get_proc_address,
                                                           GDExtensionClassLibraryPtr library,
                                                           GDExtensionInitialization* r_initialization) {
    GDExtensionBinding::InitObject init(get_proc_address, library, r_initialization);
    init.register_initializer(initialize);
    init.register_terminator(uninitialize);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
