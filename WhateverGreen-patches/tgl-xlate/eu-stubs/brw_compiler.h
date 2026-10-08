/* Stub of Mesa's brw_compiler.h for the stand-alone EU tool: only what brw_eu.h and the encoder files use. */
#ifndef BRW_COMPILER_H
#define BRW_COMPILER_H
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include "dev/intel_device_info.h"
#include "util/macros.h"
#include "util/ralloc.h"
#include "util/u_math.h"
#include "compiler/shader_enums.h"
#include "compiler/glsl/list.h"
#include "brw_isa_info.h"
enum brw_shader_reloc_type { BRW_SHADER_RELOC_TYPE_U32, BRW_SHADER_RELOC_TYPE_MOV_IMM };
struct brw_shader_reloc { uint32_t id; enum brw_shader_reloc_type type; uint32_t offset; uint32_t delta; };
struct brw_shader_reloc_value { uint32_t id; uint32_t value; };
struct brw_compiler { const struct intel_device_info *devinfo; struct brw_isa_info isa; };
#endif
