# KAGRENAC Elden Ring diagnostic probe. x64 MSVC, Windows system libraries only.
# Build outside the repository with the Visual Studio generator, for example:
#   cmake -S ports/elden-ring/probe -B D:/build/kagrenac-elden-probe -G "Visual Studio 17 2022" -A x64
#   cmake --build D:/build/kagrenac-elden-probe --config Release
cmake_minimum_required(VERSION 3.20)
project(kagrenac_er_probe LANGUAGES CXX)

if(NOT MSVC OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "The Elden Ring probe is x64 MSVC only (use -A x64).")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_library(probe_common STATIC src/build_id.cpp)
target_compile_definitions(probe_common PUBLIC WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
target_compile_options(probe_common PUBLIC /W4 /WX /permissive- /utf-8)
target_link_libraries(probe_common PUBLIC version bcrypt)

add_library(kagrenac_er_probe SHARED src/probe_dll.cpp)
target_link_libraries(kagrenac_er_probe PRIVATE probe_common)

add_executable(kagrenac_er_inspect src/inspect.cpp)
target_link_libraries(kagrenac_er_inspect PRIVATE probe_common)
