# Kagrenac Elden Ring native client reference: voiced-conversation DLL for me3. x64 MSVC, Windows SDK only.
# Reuses client/src/ai_client and config unchanged. The accepted game build comes from
# ../game-build.json. Build outside the repository with build.ps1, or:
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

# The one game build the bridge accepts, from the port's single compatibility source.
set(GAME_BUILD_FILE ${CMAKE_CURRENT_SOURCE_DIR}/../game-build.json)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${GAME_BUILD_FILE})
file(READ ${GAME_BUILD_FILE} GAME_BUILD_JSON)
string(JSON GAME_VERSION GET "${GAME_BUILD_JSON}" file_version)
string(JSON GAME_SHA256 GET "${GAME_BUILD_JSON}" sha256)
string(JSON GAME_TIMESTAMP GET "${GAME_BUILD_JSON}" pe_timestamp)
string(JSON GAME_SIZE_OF_IMAGE GET "${GAME_BUILD_JSON}" size_of_image)
if(NOT GAME_VERSION MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$" OR NOT GAME_SHA256 MATCHES "^[0-9a-f]+$"
   OR NOT GAME_TIMESTAMP MATCHES "^0x[0-9a-f]+$" OR NOT GAME_SIZE_OF_IMAGE MATCHES "^0x[0-9a-f]+$")
    message(FATAL_ERROR "${GAME_BUILD_FILE} does not hold a valid file_version, sha256, pe_timestamp and size_of_image.")
endif()
string(LENGTH "${GAME_SHA256}" GAME_SHA256_LENGTH)
if(NOT GAME_SHA256_LENGTH EQUAL 64)
    message(FATAL_ERROR "${GAME_BUILD_FILE}: sha256 must be 64 lowercase hex digits.")
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
        EXAMPLE_CLIENT_VERSION="${CLIENT_VERSION}" KAGRENAC_ER_GAME_VERSION="${GAME_VERSION}"
        KAGRENAC_ER_GAME_SHA256="${GAME_SHA256}" KAGRENAC_ER_GAME_TIMESTAMP=${GAME_TIMESTAMP}
        KAGRENAC_ER_GAME_SIZE_OF_IMAGE=${GAME_SIZE_OF_IMAGE} ${ARGN})
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
