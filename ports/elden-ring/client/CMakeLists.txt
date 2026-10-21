# Kagrenac Elden Ring native client reference: voiced-conversation DLL for me3. x64 MSVC, Windows SDK only.
# Reuses client/src/ai_client and config unchanged. Build outside the repository with build.ps1, or:
#   cmake -S ports/elden-ring/client -B <build folder> -G "Visual Studio 17 2022" -A x64
#   cmake --build <build folder> --config Release
cmake_minimum_required(VERSION 3.20)
project(kagrenac_elden_ring VERSION 0.1.0 LANGUAGES CXX)

if(NOT MSVC OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "The Elden Ring native client is x64 MSVC only (use -A x64).")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

set(CLIENT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../client)
file(READ ${CLIENT_DIR}/CMakeLists.txt CLIENT_CMAKE)
string(REGEX MATCH "project\\(KagrenacClient VERSION ([0-9.]+)" _ "${CLIENT_CMAKE}")
set(CLIENT_VERSION ${CMAKE_MATCH_1})
if(NOT CLIENT_VERSION)
    message(FATAL_ERROR "Cannot read the KagrenacClient version from ${CLIENT_DIR}/CMakeLists.txt.")
endif()

function(kagrenac_er_dll name)
    add_library(${name} SHARED
        src/kagrenac_er_dll.cpp
        src/kagrenac_er_ui.cpp
        src/kagrenac_er_bridge.cpp
        ${CLIENT_DIR}/src/ai_client.cpp
        ${CLIENT_DIR}/src/config.cpp
    )
    target_include_directories(${name} PRIVATE src ${CLIENT_DIR}/src ${CLIENT_DIR}/third_party)
    target_compile_definitions(${name} PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX
        EXAMPLE_CLIENT_VERSION="${CLIENT_VERSION}" ${ARGN})
    target_compile_options(${name} PRIVATE /W4 /WX /permissive- /utf-8)
    target_link_libraries(${name} PRIVATE winhttp winmm user32 gdi32 bcrypt)
    # Imports resolve from System32 only (LOAD_LIBRARY_SEARCH_SYSTEM32), never the game folder,
    # where winhttp.dll, winmm.dll and bcrypt.dll could be planted as proxy loaders.
    target_link_options(${name} PRIVATE /DEPENDENTLOADFLAG:0x800)
endfunction()

# The DLL for the game: runs only when the host is eldenring.exe.
kagrenac_er_dll(kagrenac_elden_ring)
# Test variant for a temporary harness outside the repository: runs only in
# kagrenac_er_harness.exe, so it refuses the game, and adds kagrenac_test_show().
kagrenac_er_dll(kagrenac_elden_ring_testhost KAGRENAC_ER_TEST_HOST)
