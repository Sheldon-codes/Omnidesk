cmake_minimum_required(VERSION 3.22.1)
project(omnidesk_baresip C)

set(BARESIP_PREBUILT "${CMAKE_CURRENT_LIST_DIR}/../jniLibs/${ANDROID_ABI}")
set(BARESIP_HEADERS "${CMAKE_CURRENT_LIST_DIR}/generated/include")

foreach(lib baresip re ssl crypto)
  add_library(${lib} STATIC IMPORTED)
  set_target_properties(${lib} PROPERTIES
    IMPORTED_LOCATION "${BARESIP_PREBUILT}/lib${lib}.a")
endforeach()

add_library(omnidesk_baresip SHARED baresip_bridge.c)
target_include_directories(omnidesk_baresip PRIVATE "${BARESIP_HEADERS}")
target_link_libraries(omnidesk_baresip
  baresip re ssl crypto z log android OpenSLES)
