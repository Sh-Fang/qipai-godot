cmake_minimum_required(VERSION 3.22)
project(douzero_core LANGUAGES CXX)

# Rules + encoding + ONNX inference + game flow, shared by:
#   douzero        static library (the core itself)
#   douzero-cli    JSON-lines stdin/stdout tool for tests and the Python cross-check
#   douzero_gdext  Godot extension, written to ../game/bin/

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

option(DOUZERO_GDEXTENSION "Build the Godot extension" ON)
if(ANDROID)  # configure with the NDK toolchain file, ANDROID_ABI=arm64-v8a
    set(ORT_PLATFORM android-arm64)
    set(ORT_RUNTIME libonnxruntime.so)
    set(GAME_BIN "${CMAKE_CURRENT_SOURCE_DIR}/../game/bin/android")
else()
    set(ORT_PLATFORM linux-x64)
    set(ORT_RUNTIME libonnxruntime.so.1)
    set(GAME_BIN "${CMAKE_CURRENT_SOURCE_DIR}/../game/bin")
endif()
set(ORT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/onnxruntime/${ORT_PLATFORM}"
    CACHE PATH "Unpacked ONNX Runtime release (include/ + lib/)")

add_library(onnxruntime SHARED IMPORTED)
set_target_properties(onnxruntime PROPERTIES
    IMPORTED_LOCATION "${ORT_DIR}/lib/libonnxruntime.so"
    INTERFACE_INCLUDE_DIRECTORIES "${ORT_DIR}/include")

add_library(douzero STATIC
    src/rules.cpp src/game.cpp src/policy.cpp src/session.cpp src/gomoku.cpp src/core.cpp)
target_include_directories(douzero PUBLIC src third_party)
target_link_libraries(douzero PUBLIC onnxruntime)
target_compile_options(douzero PRIVATE -Wall -Wextra)

add_executable(douzero-cli cli/main.cpp)
target_link_libraries(douzero-cli PRIVATE douzero)
target_compile_definitions(douzero-cli PRIVATE
    DOUZERO_DEFAULT_MODELS="${CMAKE_CURRENT_SOURCE_DIR}/../game/models")
set_target_properties(douzero-cli PROPERTIES BUILD_RPATH "${ORT_DIR}/lib")

if(DOUZERO_GDEXTENSION)
    set(GODOTCPP_API_VERSION "4.7" CACHE STRING "")
    set(GODOTCPP_DISABLE_EXCEPTIONS OFF CACHE BOOL "")  # the core reports errors with exceptions
    add_subdirectory(third_party/godot-cpp EXCLUDE_FROM_ALL)
    get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)

    add_library(douzero_gdext SHARED gdextension/douzero_core.cpp gdextension/register_types.cpp)
    target_link_libraries(douzero_gdext PRIVATE douzero godot-cpp)
    set_target_properties(douzero_gdext PROPERTIES
        PREFIX "lib"
        OUTPUT_NAME "douzero${GODOTCPP_SUFFIX}"
        LIBRARY_OUTPUT_DIRECTORY "$<1:${GAME_BIN}>"
        CXX_VISIBILITY_PRESET hidden
        BUILD_RPATH "$ORIGIN"
        BUILD_RPATH_USE_ORIGIN ON)
    # ship ONNX Runtime next to the extension (found via $ORIGIN rpath)
    add_custom_command(TARGET douzero_gdext POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${ORT_DIR}/lib/${ORT_RUNTIME}" "${GAME_BIN}/${ORT_RUNTIME}")
endif()
