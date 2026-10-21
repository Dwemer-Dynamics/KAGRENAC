# Kagrenac Elden Ring native client reference: voiced-conversation DLL for me3. x64 MSVC, Windows SDK only.
# Reuses client/src/ai_client and config unchanged. The accepted game build comes from
# ../game-build.json, the companion's map tile, hostile, bridge window and attack_enabled from the
# same control config the package is built from. Build outside the repository with build.ps1, or:
#   cmake -S ports/elden-ring/client -B <build folder> -G "Visual Studio 17 2022" -A x64 -DKAGRENAC_ER_CONTROL_CONFIG=<control config>
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

# The control config the package is built from (control/build-package.ps1 checks all of it; the
# values the DLL uses are checked here with the same ranges). Always named explicitly, never a
# default, so the DLL cannot silently describe another package.
if(NOT KAGRENAC_ER_CONTROL_CONFIG OR NOT IS_ABSOLUTE "${KAGRENAC_ER_CONTROL_CONFIG}"
   OR NOT EXISTS "${KAGRENAC_ER_CONTROL_CONFIG}" OR IS_DIRECTORY "${KAGRENAC_ER_CONTROL_CONFIG}")
    message(FATAL_ERROR "Pass -DKAGRENAC_ER_CONTROL_CONFIG=<absolute path of the control config the package is built from>.")
endif()
set(CONTROL_FILE "${KAGRENAC_ER_CONTROL_CONFIG}")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${CONTROL_FILE})
# The file's SHA-256 before and after it is read (file(READ) drops CRLF's CR, so the text read is
# not hashed); a file changed while it was read is refused.
file(SHA256 ${CONTROL_FILE} CONTROL_SHA256)
file(READ ${CONTROL_FILE} CONTROL_JSON)
file(SHA256 ${CONTROL_FILE} CONTROL_FILE_SHA256)
if(NOT CONTROL_SHA256 STREQUAL CONTROL_FILE_SHA256)
    message(FATAL_ERROR "${CONTROL_FILE} changed while it was read; build again.")
endif()
function(control_get out key type)
    string(JSON t ERROR_VARIABLE err TYPE "${CONTROL_JSON}" ${key})
    if(err OR NOT t STREQUAL type)
        message(FATAL_ERROR "${CONTROL_FILE}: ${key} must be a ${type}.")
    endif()
    string(JSON v GET "${CONTROL_JSON}" ${key})
    set(${out} "${v}" PARENT_SCOPE)
endfunction()
control_get(CONTROL_MAP companion_msb STRING)
if(NOT CONTROL_MAP MATCHES "^(m60_42_36_00|m60_42_37_00|m60_43_36_00)$")
    message(FATAL_ERROR "${CONTROL_FILE}: companion_msb must be one of the extracted MSBs.")
endif()
control_get(CONTROL_HOSTILE hostile_entity NUMBER)
if(NOT CONTROL_HOSTILE MATCHES "^[0-9]+$" OR CONTROL_HOSTILE LESS 1000000 OR CONTROL_HOSTILE GREATER 4294967295)
    message(FATAL_ERROR "${CONTROL_FILE}: hostile_entity must be an integer in 1000000..4294967295.")
endif()
control_get(CONTROL_FLAG_BASE bridge_flag_base NUMBER)
if(NOT CONTROL_FLAG_BASE MATCHES "^[0-9]+$" OR CONTROL_FLAG_BASE LESS 1000000 OR CONTROL_FLAG_BASE GREATER 4294967295)
    message(FATAL_ERROR "${CONTROL_FILE}: bridge_flag_base must be an integer in 1000000..4294967295.")
endif()
math(EXPR CONTROL_FLAG_OFFSET "${CONTROL_FLAG_BASE} % 1000")
math(EXPR CONTROL_FLAG_BYTE "${CONTROL_FLAG_OFFSET} % 8")
if(NOT CONTROL_FLAG_BYTE EQUAL 0 OR CONTROL_FLAG_OFFSET GREATER 904)
    message(FATAL_ERROR "${CONTROL_FILE}: bridge_flag_base must start a byte with 96 flags left in its 1000-flag block.")
endif()
math(EXPR CONTROL_FLAG_LAST "${CONTROL_FLAG_BASE} + 95")
control_get(CONTROL_HOSTILE_NEAR bridge_hostile_near_m NUMBER)
if(NOT CONTROL_HOSTILE_NEAR MATCHES "^[0-9]+(\\.[0-9]+)?$" OR CONTROL_HOSTILE_NEAR LESS 5 OR CONTROL_HOSTILE_NEAR GREATER 100)
    message(FATAL_ERROR "${CONTROL_FILE}: bridge_hostile_near_m must be a number in 5..100.")
endif()
control_get(CONTROL_ATTACK attack_enabled BOOLEAN)
if(CONTROL_ATTACK)
    set(CONTROL_ATTACK_ENABLED true)
    set(CONTROL_ACTIONS "\"follow_player\", \"hold_position\", \"attack_hostile\"")
else()
    set(CONTROL_ATTACK_ENABLED false)
    set(CONTROL_ACTIONS "\"follow_player\", \"hold_position\"")
endif()
# What this DLL was compiled from, beside it and outside the repository; mod.ps1 build compares
# it with the config's hash before and after both builds and with the package.
file(TO_CMAKE_PATH "${CONTROL_FILE}" CONTROL_FILE_JSON)
file(CONFIGURE OUTPUT ${CMAKE_BINARY_DIR}/kagrenac_er_control.json @ONLY CONTENT [[{
    "schema_version": 1,
    "note": "Control values compiled into kagrenac_elden_ring.dll by CMakeLists.txt; not an in-game result.",
    "control_config": { "path": "@CONTROL_FILE_JSON@", "sha256": "@CONTROL_SHA256@" },
    "companion_msb": "@CONTROL_MAP@",
    "hostile_entity": @CONTROL_HOSTILE@,
    "bridge_window": [@CONTROL_FLAG_BASE@, @CONTROL_FLAG_LAST@],
    "bridge_hostile_near_m": @CONTROL_HOSTILE_NEAR@,
    "attack_enabled": @CONTROL_ATTACK_ENABLED@,
    "supported_actions": [@CONTROL_ACTIONS@]
}
]])

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
        KAGRENAC_ER_GAME_SIZE_OF_IMAGE=${GAME_SIZE_OF_IMAGE} KAGRENAC_ER_CONTROL_SHA256="${CONTROL_SHA256}"
        KAGRENAC_ER_MAP_NAME="${CONTROL_MAP}" KAGRENAC_ER_HOSTILE_ENTITY=${CONTROL_HOSTILE}u
        KAGRENAC_ER_FLAG_BASE=${CONTROL_FLAG_BASE}u KAGRENAC_ER_HOSTILE_NEAR_M=${CONTROL_HOSTILE_NEAR}
        KAGRENAC_ER_ATTACK_ENABLED=${CONTROL_ATTACK_ENABLED} ${ARGN})
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
