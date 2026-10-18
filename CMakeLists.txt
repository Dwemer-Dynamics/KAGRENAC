cmake_minimum_required(VERSION 3.20)
# The client release version. Change only this when you release your client (--version shows it).
project(KagrenacClient VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT WIN32)
    message(FATAL_ERROR "KagrenacClient uses WinHTTP and only builds on Windows.")
endif()

add_executable(KagrenacClient
    src/main.cpp
    src/ai_client.cpp
    src/config.cpp
)
target_include_directories(KagrenacClient PRIVATE third_party)
target_compile_definitions(KagrenacClient PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX
    EXAMPLE_CLIENT_VERSION="${PROJECT_VERSION}")
target_link_libraries(KagrenacClient PRIVATE winhttp)
if(MSVC)
    target_compile_options(KagrenacClient PRIVATE /W4 /utf-8 /permissive-)
endif()

# Put the shared default config next to the exe. Your private config.json goes there too.
add_custom_command(TARGET KagrenacClient POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_CURRENT_SOURCE_DIR}/config.default.json $<TARGET_FILE_DIR:KagrenacClient>
)
