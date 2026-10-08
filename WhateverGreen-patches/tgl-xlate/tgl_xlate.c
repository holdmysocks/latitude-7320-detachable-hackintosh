/*
 * tgl_xlate.c - Gen11 (Ice Lake) EU machine code -> Gen12 (Tiger Lake), one instruction for one, same size.
 *
 * Built on Mesa 23.3.6's instruction accessors, compaction tables and emitter (src/intel/compiler, MIT licence).
 * The same file is compiled into the host tool g11to12 and into the kext.
 */
#include <string.h>
#include "brw_eu.h"
#include "tgl_xlate.h"

#ifndef XLATE_TRACE
#define XLATE_TRACE(...) ((void)0)
#endif

volatile int kshim_assert_failed;
static struct tgl_xlate_info xl_info;
/* Raw Gen11/Gen12 opcodes Mesa does not handle as jumps: goto, join */
#define XL_HW_GOTO 0x2E
#define XL_HW_JOIN 0x2F
static struct intel_device_info d11 = { .ver = 11, .verx10 = 110, .platform = INTEL_PLATFORM_ICL };
static struct intel_device_info d12 = { .ver = 12, .verx10 = 120, .platform = INTEL_PLATFORM_TGL };
static struct brw_isa_info isa11, isa12;
static bool xl_ready;

#include "a1_3src_helpers.h"

/* ---- translation ------------------------------------------------------------------------------------------ */

/* GRF pairs that stand in for acc0/acc1 where Gen11 code uses them in the native (NF) format; -1 = none free */
static int nf_scratch[2] = { -1, -1 };

/* Set by translate_pass() for the instruction being translated: the extended descriptor of a split send when the
 * register it comes from was loaded with a constant by the instruction just before (Gen11 can only express some
 * descriptor bits through a register; Gen12 takes them as an immediate) */
static bool xl_ex_const;
static uint32_t xl_ex_value;

static int fail(const char *why, int offset)
{
   if (!xl_info.reason) { xl_info.reason = why; xl_info.offset = offset; }
   XLATE_TRACE("      UNSUPPORTED @%04x: %s\n", offset, why);
   return -1;
}

static bool valid_type(enum brw_reg_type t) { return (unsigned)t <= BRW_REGISTER_TYPE_LAST; }
#define CHK_TYPE(t) do { if (!valid_type(t)) return fail("register type", offset); } while (0)

static struct brw_reg mkreg(unsigned file, enum brw_reg_type type, unsigned nr, unsigned subnr_bytes,
                            unsigned vstride, unsigned width, unsigned hstride, bool negate, bool abs)
{
   struct brw_reg r = brw_reg(file, nr, 0, negate, abs, type, vstride, width, hstride, BRW_SWIZZLE_XYZW, WRITEMASK_XYZW);
   r.subnr = subnr_bytes;
   return r;
}

/* g[a0.n + imm]: register-indirect operand (the region and type come with it) */
static struct brw_reg mkind(enum brw_reg_type type, unsigned a0_subnr, int addr_imm, unsigned vstride, unsigned width, unsigned hstride, bool negate, bool abs)
{
   struct brw_reg r = brw_reg(BRW_GENERAL_REGISTER_FILE, 0, 0, negate, abs, type, vstride, width, hstride, BRW_SWIZZLE_XYZW, WRITEMASK_XYZW);
   r.address_mode = BRW_ADDRESS_REGISTER_INDIRECT_REGISTER;
   r.subnr = a0_subnr;
   r.indirect_offset = addr_imm;
   return r;
}

static struct brw_reg mkimm(const brw_inst *in, enum brw_reg_type type)
{
   struct brw_reg r = brw_imm_reg(type);
   if (type_sz(type) == 8) r.u64 = brw_inst_imm_uq(&d11, in);
   else r.ud = brw_inst_imm_ud(&d11, in);
   return r;
}

/* One Gen11 instruction (uncompacted) -> Gen12 instruction(s) appended to p. Returns 0, or -1 if not handled. */
static int translate_one(struct brw_codegen *p, const brw_inst *in, int offset, struct tgl_swsb swsb)
{
   unsigned op = brw_inst_opcode(&isa11, in);
   unsigned hw = brw_inst_hw_opcode(&d11, in);
   const struct opcode_desc *desc = brw_opcode_desc(&isa11, op);
   if (!desc || (op == BRW_OPCODE_ILLEGAL && hw != XL_HW_JOIN)) return fail("unknown opcode", offset);
   if (hw != XL_HW_GOTO && hw != XL_HW_JOIN && brw_inst_access_mode(&d11, in) != BRW_ALIGN_1) return fail("align16", offset);
   if (brw_inst_exec_size(&d11, in) > BRW_EXECUTE_32) return fail("execution size", offset);
   {
      unsigned op12 = op == BRW_OPCODE_SENDS ? BRW_OPCODE_SEND : op == BRW_OPCODE_SENDSC ? BRW_OPCODE_SENDC : op;
      if (!brw_opcode_desc(&isa12, op12)) return fail("opcode does not exist on Gen12", offset);
   }

   brw_set_default_access_mode(p, BRW_ALIGN_1);
   brw_set_default_exec_size(p, brw_inst_exec_size(&d11, in));
   brw_set_default_group(p, brw_inst_qtr_control(&d11, in) * 8 + brw_inst_nib_control(&d11, in) * 4);
   brw_set_default_mask_control(p, brw_inst_mask_control(&d11, in));
   brw_set_default_swsb(p, swsb);
   bool is_send = op == BRW_OPCODE_SEND || op == BRW_OPCODE_SENDC || op == BRW_OPCODE_SENDS || op == BRW_OPCODE_SENDSC;
   if (!is_send) {
      brw_set_default_predicate_control(p, brw_inst_pred_control(&d11, in));
      brw_set_default_predicate_inverse(p, brw_inst_pred_inv(&d11, in));
      brw_set_default_saturate(p, brw_inst_saturate(&d11, in));
      brw_set_default_flag_reg(p, brw_inst_flag_reg_nr(&d11, in), brw_inst_flag_subreg_nr(&d11, in));
   } else {
      brw_set_default_predicate_control(p, brw_inst_pred_control(&d11, in));
      brw_set_default_predicate_inverse(p, brw_inst_pred_inv(&d11, in));
      brw_set_default_saturate(p, 0);
      brw_set_default_flag_reg(p, brw_inst_flag_reg_nr(&d11, in), brw_inst_flag_subreg_nr(&d11, in));
   }

   if (hw == XL_HW_GOTO || hw == XL_HW_JOIN) {
      /* Same fields as break/endif: predicate and execution size from the state above, jump offsets filled in by
       * translate(). Emitted as goto; join only differs in the opcode. */
      brw_set_default_predicate_control(p, brw_inst_pred_control(&d11, in));
      brw_set_default_predicate_inverse(p, brw_inst_pred_inv(&d11, in));
      brw_set_default_flag_reg(p, brw_inst_flag_reg_nr(&d11, in), brw_inst_flag_subreg_nr(&d11, in));
      brw_inst *out = brw_next_insn(p, BRW_OPCODE_GOTO);
      brw_set_dest(p, out, vec1(retype(brw_null_reg(), BRW_REGISTER_TYPE_D)));
      brw_inst_set_jip(&d12, out, 0);
      if (hw == XL_HW_GOTO) {
         brw_inst_set_uip(&d12, out, 0);
         brw_inst_set_branch_control(&d12, out, brw_inst_branch_control(&d11, in));
      } else {
         brw_inst_set_hw_opcode(&d12, out, XL_HW_JOIN);
      }
      return 0;
   }

   /* Apple's "mov ARF 0xF0, 0 {switch}": thread switch hint, no Gen12 equivalent */
   if (op == BRW_OPCODE_MOV && brw_inst_dst_reg_file(&d11, in) == BRW_ARCHITECTURE_REGISTER_FILE &&
       brw_inst_dst_da_reg_nr(&d11, in) >= 0xF0) {
      /* A real (ordered) instruction rather than a nop, so that "@1" on the next instruction still means
       * "the instruction before the hint has completed" */
      brw_MOV(p, retype(brw_null_reg(), BRW_REGISTER_TYPE_UD), brw_imm_ud(0));
      return 0;
   }

   if (is_send) {
      bool split = op == BRW_OPCODE_SENDS || op == BRW_OPCODE_SENDSC;
      bool eot = brw_inst_eot(&d11, in);
      unsigned sfid = brw_inst_sfid(&d11, in);
      struct brw_reg dst, payload0;
      brw_inst *out;
      if (split) {
         if (brw_inst_dst_address_mode(&d11, in) != BRW_ADDRESS_DIRECT || brw_inst_send_src0_address_mode(&d11, in) != BRW_ADDRESS_DIRECT)
            return fail("split send with indirect addressing", offset);
         dst = mkreg(brw_inst_send_dst_reg_file(&d11, in), BRW_REGISTER_TYPE_UD, brw_inst_dst_da_reg_nr(&d11, in), 0, BRW_VERTICAL_STRIDE_8, BRW_WIDTH_8, BRW_HORIZONTAL_STRIDE_1, 0, 0);
         payload0 = mkreg(BRW_GENERAL_REGISTER_FILE, BRW_REGISTER_TYPE_UD, brw_inst_src0_da_reg_nr(&d11, in), 0, BRW_VERTICAL_STRIDE_8, BRW_WIDTH_8, BRW_HORIZONTAL_STRIDE_1, 0, 0);
         struct brw_reg payload1 = mkreg(brw_inst_send_src1_reg_file(&d11, in), BRW_REGISTER_TYPE_UD, brw_inst_send_src1_reg_nr(&d11, in), 0, BRW_VERTICAL_STRIDE_8, BRW_WIDTH_8, BRW_HORIZONTAL_STRIDE_1, 0, 0);
         bool desc_reg = brw_inst_send_sel_reg32_desc(&d11, in), ex_reg = brw_inst_send_sel_reg32_ex_desc(&d11, in);
         if (!desc_reg && (!ex_reg || xl_ex_const)) {
            /* Immediate descriptors; Mesa's emitter fills in SFID and EOT */
            unsigned ex = ex_reg ? (xl_ex_value & ~0x3FU) : brw_inst_sends_ex_desc(&d11, in);
            brw_send_indirect_split_message(p, sfid, dst, payload0, payload1, brw_imm_ud(0), brw_inst_send_desc(&d11, in),
                                            brw_imm_ud(0), ex, false, false, eot);
         } else {
            /* Descriptor in a0.0 and/or extended descriptor in a0.n, loaded by earlier instructions of the kernel:
             * the Gen12 send names the same registers (the tail of Mesa's brw_send_indirect_split_message) */
            brw_inst *send = brw_next_insn(p, BRW_OPCODE_SEND);
            brw_set_dest(p, send, retype(dst, BRW_REGISTER_TYPE_UW));
            brw_set_src0(p, send, retype(payload0, BRW_REGISTER_TYPE_UD));
            brw_set_src1(p, send, retype(payload1, BRW_REGISTER_TYPE_UD));
            if (desc_reg) {
               brw_inst_set_send_sel_reg32_desc(&d12, send, 1);
            } else {
               brw_inst_set_send_sel_reg32_desc(&d12, send, 0);
               brw_inst_set_send_desc(&d12, send, brw_inst_send_desc(&d11, in));
            }
            if (ex_reg && !xl_ex_const) {
               brw_inst_set_send_sel_reg32_ex_desc(&d12, send, 1);
               brw_inst_set_send_ex_desc_ia_subreg_nr(&d12, send, brw_inst_send_ex_desc_ia_subreg_nr(&d11, in));
            } else {
               brw_inst_set_send_sel_reg32_ex_desc(&d12, send, 0);
               brw_inst_set_sends_ex_desc(&d12, send, ex_reg ? (xl_ex_value & ~0x3FU) : brw_inst_sends_ex_desc(&d11, in));
            }
            brw_inst_set_sfid(&d12, send, sfid);
            brw_inst_set_eot(&d12, send, eot);
         }
      } else {
         if (brw_inst_dst_address_mode(&d11, in) != BRW_ADDRESS_DIRECT || brw_inst_src0_address_mode(&d11, in) != BRW_ADDRESS_DIRECT)
            return fail("send with indirect addressing", offset);
         if (brw_inst_src1_reg_file(&d11, in) != BRW_IMMEDIATE_VALUE)
            return fail("send with register descriptor", offset);
         dst = mkreg(brw_inst_dst_reg_file(&d11, in), BRW_REGISTER_TYPE_UD, brw_inst_dst_da_reg_nr(&d11, in), 0, BRW_VERTICAL_STRIDE_8, BRW_WIDTH_8, BRW_HORIZONTAL_STRIDE_1, 0, 0);
         payload0 = mkreg(brw_inst_src0_reg_file(&d11, in), BRW_REGISTER_TYPE_UD, brw_inst_src0_da_reg_nr(&d11, in), 0, BRW_VERTICAL_STRIDE_8, BRW_WIDTH_8, BRW_HORIZONTAL_STRIDE_1, 0, 0);
         brw_send_indirect_message(p, sfid, dst, payload0, brw_imm_ud(0), brw_inst_imm_ud(&d11, in), eot);
      }
      out = &p->store[p->nr_insn - 1];
      if (op == BRW_OPCODE_SENDC || op == BRW_OPCODE_SENDSC)
         brw_inst_set_opcode(&isa12, out, BRW_OPCODE_SENDC);
      return 0;
   }

   if (desc->nsrc == 3) {
      /* Align1 three-source form, decoded the way Mesa's disassembler does for Gen10-11 */
      CHK_TYPE(brw_inst_3src_a1_dst_type(&d11, in));
      if (brw_inst_3src_access_mode(&d11, in) != BRW_ALIGN_1) return fail("align16", offset);
      struct brw_reg dst = mkreg(brw_inst_3src_a1_dst_reg_file(&d11, in) ? BRW_ARCHITECTURE_REGISTER_FILE : BRW_GENERAL_REGISTER_FILE,
                                 brw_inst_3src_a1_dst_type(&d11, in), brw_inst_3src_dst_reg_nr(&d11, in),
                                 brw_inst_3src_a1_dst_subreg_nr(&d11, in), BRW_VERTICAL_STRIDE_8, BRW_WIDTH_8, BRW_HORIZONTAL_STRIDE_1, 0, 0);
      struct brw_reg s[3];
      enum brw_reg_type t0 = brw_inst_3src_a1_src0_type(&d11, in), t1 = brw_inst_3src_a1_src1_type(&d11, in), t2 = brw_inst_3src_a1_src2_type(&d11, in);
      CHK_TYPE(dst.type); CHK_TYPE(t0); CHK_TYPE(t1); CHK_TYPE(t2);
      /* NF (the accumulator's native format, Gen11 only) marks an accumulator operand; Gen12 has no such type */
      /* "mad acc:NF, ..." followed by "mad dst, acc:NF, ..." is Gen11's plane evaluation with the intermediate
       * kept in the accumulator's native format. Gen12 has neither NF nor an accumulator source in this form:
       * the intermediate goes through a general register nothing else in the kernel uses, as a float. */
      bool src0_acc = t0 == BRW_REGISTER_TYPE_NF;
      if (dst.type == BRW_REGISTER_TYPE_NF) {
         int r = nf_scratch[dst.nr & 1];
         if (r < 0) return fail("no free register to replace the NF accumulator", offset);
         dst = mkreg(BRW_GENERAL_REGISTER_FILE, BRW_REGISTER_TYPE_F, r, 0, BRW_VERTICAL_STRIDE_8, BRW_WIDTH_8, BRW_HORIZONTAL_STRIDE_1, 0, 0);
      }
      if (src0_acc) t0 = BRW_REGISTER_TYPE_F;
      if (src0_acc) {
         int r = nf_scratch[brw_inst_3src_src0_reg_nr(&d11, in) & 1];
         if (r < 0) return fail("no free register to replace the NF accumulator", offset);
         s[0] = mkreg(BRW_GENERAL_REGISTER_FILE, BRW_REGISTER_TYPE_F, r, 0, BRW_VERTICAL_STRIDE_8, BRW_WIDTH_8, BRW_HORIZONTAL_STRIDE_1,
                      brw_inst_3src_src0_negate(&d11, in), brw_inst_3src_src0_abs(&d11, in));
      } else if (brw_inst_3src_a1_src0_reg_file(&d11, in) != BRW_ALIGN1_3SRC_GENERAL_REGISTER_FILE) {
         s[0] = brw_imm_reg(t0); s[0].ud = brw_inst_3src_a1_src0_imm(&d11, in);
      } else {
         unsigned vs = vstride_from_align1_3src_vstride(&d11, brw_inst_3src_a1_src0_vstride(&d11, in));
         unsigned hs = hstride_from_align1_3src_hstride(brw_inst_3src_a1_src0_hstride(&d11, in));
         s[0] = mkreg(brw_inst_3src_a1_src0_reg_file(&d11, in) == BRW_ALIGN1_3SRC_GENERAL_REGISTER_FILE ? BRW_GENERAL_REGISTER_FILE : BRW_ARCHITECTURE_REGISTER_FILE,
                      t0, brw_inst_3src_src0_reg_nr(&d11, in), brw_inst_3src_a1_src0_subreg_nr(&d11, in),
                      vs, implied_width(vs, hs), hs, brw_inst_3src_src0_negate(&d11, in), brw_inst_3src_src0_abs(&d11, in));
      }
      {
         unsigned vs = vstride_from_align1_3src_vstride(&d11, brw_inst_3src_a1_src1_vstride(&d11, in));
         unsigned hs = hstride_from_align1_3src_hstride(brw_inst_3src_a1_src1_hstride(&d11, in));
         s[1] = mkreg(brw_inst_3src_a1_src1_reg_file(&d11, in) == BRW_ALIGN1_3SRC_GENERAL_REGISTER_FILE ? BRW_GENERAL_REGISTER_FILE : BRW_ARCHITECTURE_REGISTER_FILE,
                      t1, brw_inst_3src_src1_reg_nr(&d11, in), brw_inst_3src_a1_src1_subreg_nr(&d11, in),
                      vs, implied_width(vs, hs), hs, brw_inst_3src_src1_negate(&d11, in), brw_inst_3src_src1_abs(&d11, in));
      }
      if (brw_inst_3src_a1_src2_reg_file(&d11, in) != BRW_ALIGN1_3SRC_GENERAL_REGISTER_FILE) {
         s[2] = brw_imm_reg(t2); s[2].ud = brw_inst_3src_a1_src2_imm(&d11, in);
      } else {
         unsigned vs = vstride_from_align1_3src_hstride(brw_inst_3src_a1_src2_hstride(&d11, in));
         unsigned hs = hstride_from_align1_3src_hstride(brw_inst_3src_a1_src2_hstride(&d11, in));
         s[2] = mkreg(BRW_GENERAL_REGISTER_FILE, t2, brw_inst_3src_src2_reg_nr(&d11, in), brw_inst_3src_a1_src2_subreg_nr(&d11, in),
                      vs, implied_width(vs, hs), hs, brw_inst_3src_src2_negate(&d11, in), brw_inst_3src_src2_abs(&d11, in));
      }
      brw_inst *out;
      switch (op) {
      case BRW_OPCODE_MAD: out = brw_MAD(p, dst, s[0], s[1], s[2]); break;
      case BRW_OPCODE_LRP: return fail("lrp does not exist on Gen12", offset);
      case BRW_OPCODE_CSEL: out = brw_CSEL(p, dst, s[0], s[1], s[2]); break;
      case BRW_OPCODE_BFE: out = brw_BFE(p, dst, s[0], s[1], s[2]); break;
      case BRW_OPCODE_BFI2: out = brw_BFI2(p, dst, s[0], s[1], s[2]); break;
      default: return fail("3-source opcode", offset);
      }
      brw_inst_set_3src_cond_modifier(&d12, out, brw_inst_3src_cond_modifier(&d11, in));
      return 0;
   }

   switch (op) {
   case BRW_OPCODE_IF: case BRW_OPCODE_ELSE: case BRW_OPCODE_ENDIF: case BRW_OPCODE_WHILE:
   case BRW_OPCODE_BREAK: case BRW_OPCODE_CONTINUE: case BRW_OPCODE_HALT: {
      /* Jump offsets are filled in by translate() once the new layout is known */
      brw_inst *out = brw_next_insn(p, op);
      brw_set_dest(p, out, vec1(retype(brw_null_reg(), BRW_REGISTER_TYPE_D)));
      brw_inst_set_jip(&d12, out, 0);
      if (brw_has_uip(&d11, op)) brw_inst_set_uip(&d12, out, 0);
      if (op == BRW_OPCODE_IF || op == BRW_OPCODE_ELSE)
         brw_inst_set_branch_control(&d12, out, brw_inst_branch_control(&d11, in));
      return 0;
   }
   case BRW_OPCODE_JMPI: {
      /* Jump distance in bytes from the instruction after the jmpi; filled in by translate() */
      if (brw_inst_src1_reg_file(&d11, in) != BRW_IMMEDIATE_VALUE) return fail("jmpi through a register", offset);
      brw_JMPI(p, brw_imm_d(0), brw_inst_pred_control(&d11, in));
      return 0;
   }
   case BRW_OPCODE_DO: case BRW_OPCODE_BRD: case BRW_OPCODE_BRC:
   case BRW_OPCODE_CALL: case BRW_OPCODE_CALLA: case BRW_OPCODE_RET:
      return fail("flow control (call/ret/brd/brc)", offset);
   case BRW_OPCODE_NOP:
      brw_NOP(p);
      return 0;
   }

   CHK_TYPE(brw_inst_dst_type(&d11, in));
   if (desc->nsrc >= 1) CHK_TYPE(brw_inst_src0_type(&d11, in));
   if (desc->nsrc >= 2) CHK_TYPE(brw_inst_src1_type(&d11, in));
   brw_inst *out = brw_next_insn(p, op);
   if (brw_inst_dst_address_mode(&d11, in) != BRW_ADDRESS_DIRECT)
      brw_set_dest(p, out, mkind(brw_inst_dst_type(&d11, in), brw_inst_dst_ia_subreg_nr(&d11, in), brw_inst_dst_ia1_addr_imm(&d11, in),
                                 3, 3, brw_inst_dst_hstride(&d11, in), 0, 0));
   else
   brw_set_dest(p, out, mkreg(brw_inst_dst_reg_file(&d11, in), brw_inst_dst_type(&d11, in), brw_inst_dst_da_reg_nr(&d11, in),
                              brw_inst_dst_da1_subreg_nr(&d11, in), 3, 3, brw_inst_dst_hstride(&d11, in), 0, 0));
   if (desc->nsrc >= 1) {
      if (brw_inst_src0_reg_file(&d11, in) == BRW_IMMEDIATE_VALUE)
         brw_set_src0(p, out, mkimm(in, brw_inst_src0_type(&d11, in)));
      else {
         if (brw_inst_src0_address_mode(&d11, in) != BRW_ADDRESS_DIRECT)
            brw_set_src0(p, out, mkind(brw_inst_src0_type(&d11, in), brw_inst_src0_ia_subreg_nr(&d11, in), brw_inst_src0_ia1_addr_imm(&d11, in),
                                       brw_inst_src0_vstride(&d11, in), brw_inst_src0_width(&d11, in), brw_inst_src0_hstride(&d11, in),
                                       brw_inst_src0_negate(&d11, in), brw_inst_src0_abs(&d11, in)));
         else
         brw_set_src0(p, out, mkreg(brw_inst_src0_reg_file(&d11, in), brw_inst_src0_type(&d11, in), brw_inst_src0_da_reg_nr(&d11, in),
                                    brw_inst_src0_da1_subreg_nr(&d11, in), brw_inst_src0_vstride(&d11, in), brw_inst_src0_width(&d11, in),
                                    brw_inst_src0_hstride(&d11, in), brw_inst_src0_negate(&d11, in), brw_inst_src0_abs(&d11, in)));
      }
   }
   if (desc->nsrc >= 2) {
      if (brw_inst_src1_reg_file(&d11, in) == BRW_IMMEDIATE_VALUE)
         brw_set_src1(p, out, mkimm(in, brw_inst_src1_type(&d11, in)));
      else {
         if (brw_inst_src1_address_mode(&d11, in) != BRW_ADDRESS_DIRECT)
            brw_set_src1(p, out, mkind(brw_inst_src1_type(&d11, in), brw_inst_src1_ia_subreg_nr(&d11, in), brw_inst_src1_ia1_addr_imm(&d11, in),
                                       brw_inst_src1_vstride(&d11, in), brw_inst_src1_width(&d11, in), brw_inst_src1_hstride(&d11, in),
                                       brw_inst_src1_negate(&d11, in), brw_inst_src1_abs(&d11, in)));
         else
         brw_set_src1(p, out, mkreg(brw_inst_src1_reg_file(&d11, in), brw_inst_src1_type(&d11, in), brw_inst_src1_da_reg_nr(&d11, in),
                                    brw_inst_src1_da1_subreg_nr(&d11, in), brw_inst_src1_vstride(&d11, in), brw_inst_src1_width(&d11, in),
                                    brw_inst_src1_hstride(&d11, in), brw_inst_src1_negate(&d11, in), brw_inst_src1_abs(&d11, in)));
      }
   }
   brw_inst_set_cond_modifier(&d12, out, brw_inst_cond_modifier(&d11, in));
   if (op == BRW_OPCODE_MATH) brw_inst_set_math_function(&d12, out, brw_inst_math_function(&d11, in));
   return 0;
}

/* ---- software scoreboard ---------------------------------------------------------------------------------- */

/* Resources an instruction reads or writes: GRF 0-127, then accumulator, flags, any other architecture register */
enum { RES_ACC = 128, RES_FLAG = 129, RES_ARF = 130, RES_COUNT = 131 };
struct resset { uint64_t w[3]; };
static void rs_add(struct resset *s, unsigned r) { if (r < RES_COUNT) s->w[r / 64] |= 1ULL << (r % 64); }
static bool rs_hit(const struct resset *a, const struct resset *b) { return (a->w[0] & b->w[0]) || (a->w[1] & b->w[1]) || (a->w[2] & b->w[2]); }
static void rs_or(struct resset *a, const struct resset *b) { for (int i = 0; i < 3; i++) a->w[i] |= b->w[i]; }

static void rs_any_grf(struct resset *s) { s->w[0] = ~0ULL; s->w[1] = ~0ULL; }
static bool xl_indirect;   /* set by resources(): the instruction uses register-indirect addressing */

static void rs_operand(struct resset *s, unsigned file, unsigned nr, unsigned subnr, unsigned bytes)
{
   if (file == BRW_GENERAL_REGISTER_FILE) {
      unsigned regs = (subnr + bytes + 31) / 32;
      for (unsigned i = 0; i < (regs ? regs : 1); i++) rs_add(s, nr + i);
   } else if (file == BRW_ARCHITECTURE_REGISTER_FILE) {
      if ((nr & 0xF0) == BRW_ARF_NULL && nr == BRW_ARF_NULL) return;
      rs_add(s, (nr & 0xF0) == BRW_ARF_ACCUMULATOR ? RES_ACC : (nr & 0xF0) == BRW_ARF_FLAG ? RES_FLAG : RES_ARF);
   }
}

/* Bytes an operand spans: n elements of its type, or one element for a scalar <0;1,0> region */
static unsigned xl_span(unsigned n, enum brw_reg_type type, bool scalar)
{
   unsigned sz = (unsigned)type <= BRW_REGISTER_TYPE_LAST ? type_sz(type) : 8;
   return scalar ? sz : n * sz;
}

/* What a Gen11 instruction reads and writes. For a send: rd = payloads, wr = response registers. */
static void resources(const brw_inst *in, struct resset *rd, struct resset *wr)
{
   unsigned op = brw_inst_opcode(&isa11, in);
   const struct opcode_desc *desc = brw_opcode_desc(&isa11, op);
   unsigned n = 1u << brw_inst_exec_size(&d11, in);
   memset(rd, 0, sizeof(*rd)); memset(wr, 0, sizeof(*wr));
   xl_indirect = false;
   if (brw_inst_hw_opcode(&d11, in) == XL_HW_GOTO || brw_inst_hw_opcode(&d11, in) == XL_HW_JOIN) {
      if (brw_inst_pred_control(&d11, in)) rs_add(rd, RES_FLAG);
      return;
   }
   if (op == BRW_OPCODE_SEND || op == BRW_OPCODE_SENDC || op == BRW_OPCODE_SENDS || op == BRW_OPCODE_SENDSC) {
      bool split = op == BRW_OPCODE_SENDS || op == BRW_OPCODE_SENDSC;
      unsigned d = split ? brw_inst_send_desc(&d11, in) : brw_inst_imm_ud(&d11, in);
      unsigned mlen = (d >> 25) & 0xF, rlen = (d >> 20) & 0x1F;
      unsigned dfile = split ? brw_inst_send_dst_reg_file(&d11, in) : brw_inst_dst_reg_file(&d11, in);
      rs_operand(wr, dfile, brw_inst_dst_da_reg_nr(&d11, in), 0, rlen * 32);
      rs_operand(rd, BRW_GENERAL_REGISTER_FILE, brw_inst_src0_da_reg_nr(&d11, in), 0, mlen * 32);
      if (split)
         rs_operand(rd, brw_inst_send_src1_reg_file(&d11, in), brw_inst_send_src1_reg_nr(&d11, in), 0, ((brw_inst_sends_ex_desc(&d11, in) >> 6) & 0xF) * 32);
      if (split ? (brw_inst_send_sel_reg32_desc(&d11, in) || brw_inst_send_sel_reg32_ex_desc(&d11, in)) : brw_inst_src1_reg_file(&d11, in) != BRW_IMMEDIATE_VALUE)
         rs_add(rd, RES_ARF);
      return;
   }
   if (!desc) return;
   if (desc->nsrc == 3) {
      rs_operand(wr, brw_inst_3src_a1_dst_reg_file(&d11, in) ? BRW_ARCHITECTURE_REGISTER_FILE : BRW_GENERAL_REGISTER_FILE,
                 brw_inst_3src_dst_reg_nr(&d11, in), brw_inst_3src_a1_dst_subreg_nr(&d11, in), xl_span(n, brw_inst_3src_a1_dst_type(&d11, in), false));
      bool g0 = brw_inst_3src_a1_src0_reg_file(&d11, in) == BRW_ALIGN1_3SRC_GENERAL_REGISTER_FILE;
      if (g0 || brw_inst_3src_a1_src0_type(&d11, in) == BRW_REGISTER_TYPE_NF)
         rs_operand(rd, g0 ? BRW_GENERAL_REGISTER_FILE : BRW_ARCHITECTURE_REGISTER_FILE, brw_inst_3src_src0_reg_nr(&d11, in), brw_inst_3src_a1_src0_subreg_nr(&d11, in),
                    xl_span(n, brw_inst_3src_a1_src0_type(&d11, in), brw_inst_3src_a1_src0_vstride(&d11, in) == BRW_ALIGN1_3SRC_VERTICAL_STRIDE_0));
      rs_operand(rd, brw_inst_3src_a1_src1_reg_file(&d11, in) == BRW_ALIGN1_3SRC_GENERAL_REGISTER_FILE ? BRW_GENERAL_REGISTER_FILE : BRW_ARCHITECTURE_REGISTER_FILE,
                 brw_inst_3src_src1_reg_nr(&d11, in), brw_inst_3src_a1_src1_subreg_nr(&d11, in),
                 xl_span(n, brw_inst_3src_a1_src1_type(&d11, in), brw_inst_3src_a1_src1_vstride(&d11, in) == BRW_ALIGN1_3SRC_VERTICAL_STRIDE_0));
      if (brw_inst_3src_a1_src2_reg_file(&d11, in) == BRW_ALIGN1_3SRC_GENERAL_REGISTER_FILE)
         rs_operand(rd, BRW_GENERAL_REGISTER_FILE, brw_inst_3src_src2_reg_nr(&d11, in), brw_inst_3src_a1_src2_subreg_nr(&d11, in),
                    xl_span(n, brw_inst_3src_a1_src2_type(&d11, in), brw_inst_3src_a1_src2_hstride(&d11, in) == BRW_ALIGN1_3SRC_SRC_HORIZONTAL_STRIDE_0));
      if (brw_inst_3src_cond_modifier(&d11, in)) rs_add(wr, RES_FLAG);
   } else {
      if (brw_inst_dst_address_mode(&d11, in) != BRW_ADDRESS_DIRECT) { rs_any_grf(wr); rs_add(rd, RES_ARF); xl_indirect = true; }
      else
      rs_operand(wr, brw_inst_dst_reg_file(&d11, in), brw_inst_dst_da_reg_nr(&d11, in), brw_inst_dst_da1_subreg_nr(&d11, in),
                 xl_span(n, brw_inst_dst_type(&d11, in), false));
      if (desc->nsrc >= 1 && brw_inst_src0_reg_file(&d11, in) != BRW_IMMEDIATE_VALUE && brw_inst_src0_address_mode(&d11, in) != BRW_ADDRESS_DIRECT) {
         rs_any_grf(rd); rs_add(rd, RES_ARF); xl_indirect = true;
      } else if (desc->nsrc >= 1 && brw_inst_src0_reg_file(&d11, in) != BRW_IMMEDIATE_VALUE)
         rs_operand(rd, brw_inst_src0_reg_file(&d11, in), brw_inst_src0_da_reg_nr(&d11, in), brw_inst_src0_da1_subreg_nr(&d11, in),
                    xl_span(n, brw_inst_src0_type(&d11, in), brw_inst_src0_vstride(&d11, in) == BRW_VERTICAL_STRIDE_0 && brw_inst_src0_width(&d11, in) == BRW_WIDTH_1));
      if (desc->nsrc >= 2 && brw_inst_src1_reg_file(&d11, in) != BRW_IMMEDIATE_VALUE && brw_inst_src1_address_mode(&d11, in) != BRW_ADDRESS_DIRECT) {
         rs_any_grf(rd); rs_add(rd, RES_ARF); xl_indirect = true;
      } else if (desc->nsrc >= 2 && brw_inst_src1_reg_file(&d11, in) != BRW_IMMEDIATE_VALUE)
         rs_operand(rd, brw_inst_src1_reg_file(&d11, in), brw_inst_src1_da_reg_nr(&d11, in), brw_inst_src1_da1_subreg_nr(&d11, in),
                    xl_span(n, brw_inst_src1_type(&d11, in), brw_inst_src1_vstride(&d11, in) == BRW_VERTICAL_STRIDE_0 && brw_inst_src1_width(&d11, in) == BRW_WIDTH_1));
      if (brw_inst_cond_modifier(&d11, in)) rs_add(wr, RES_FLAG);
      if (brw_inst_acc_wr_control(&d11, in)) rs_add(wr, RES_ACC);
      if (op == BRW_OPCODE_MAC || op == BRW_OPCODE_MACH || op == BRW_OPCODE_SADA2) rs_add(rd, RES_ACC);
   }
   if (brw_inst_pred_control(&d11, in)) rs_add(rd, RES_FLAG);
}

/*
 * Translate a kernel.
 *
 * Gen12 does not track dependencies between instructions; each instruction says what it waits for (SWSB).
 * On Tiger Lake an instruction can name one thing: the previous ordered (non-send) instruction ("@1"), or a
 * send by its token ("$n.dst"); a send can combine "@1" with setting its own token. The scheme:
 *   - by default an instruction waits for the previous one, so at most one ALU instruction is ever in flight;
 *   - each send gets a free token;
 *   - an instruction waits for an outstanding send instead of the previous instruction when it touches
 *     nothing still in flight; otherwise a "sync.nop $n.dst" is inserted in front of it;
 *   - before every flow-control instruction and every jump target all outstanding sends are waited for, so
 *     the state is the same on every path.
 * Inserted instructions, and compacted instructions with no Gen12 compact form, make the kernel grow. It may
 * grow into the zero padding up to the next 64-byte boundary (kernel start pointers are 64-byte aligned); if
 * that is not enough everything that has a compact form is compacted; if it still does not fit the kernel is
 * rejected. Jump offsets are recomputed for the new layout.
 */
#define XL_MAX_INSNS 48000

struct xl_insn {
   brw_inst full;            /* Gen11, uncompacted */
   uint32_t old_off;
   uint8_t compacted, is_send, is_flow, is_label, eot, ex_const, is_pad, indirect;
   uint32_t ex_value;
   int32_t first_out;        /* index in p.store of the first instruction emitted for it (a sync, or itself) */
   int32_t main_out;         /* index of its own translation */
};
static struct xl_insn xl_in[XL_MAX_INSNS + 1];
static uint32_t xl_out_off[2 * XL_MAX_INSNS + 64];
static uint8_t xl_out_small[2 * XL_MAX_INSNS + 64];
static uint8_t xl_out_try[2 * XL_MAX_INSNS + 64];   /* 1 = try to compact */

/*
 * Jump fields of a Gen11 instruction: 0 none, 1 jmpi (immediate, counted from the next instruction),
 * 2 JIP, 3 JIP and UIP (both counted from the instruction itself). goto (0x2E) and join (0x2F) are read from the
 * raw opcode: Mesa's tables have no join and do not list goto among the instructions with jump fields.
 */
static int xl_jump_kind(const brw_inst *in)
{
   unsigned hw = brw_inst_hw_opcode(&d11, in);
   if (hw == XL_HW_GOTO) return 3;
   if (hw == XL_HW_JOIN) return 2;
   unsigned op = brw_inst_opcode(&isa11, in);
   if (op == BRW_OPCODE_JMPI) return brw_inst_src1_reg_file(&d11, in) == BRW_IMMEDIATE_VALUE ? 1 : 0;
   if (!brw_has_jip(&d11, op)) return 0;
   return brw_has_uip(&d11, op) ? 3 : 2;
}

static bool xl_is_send(unsigned op) { return op == BRW_OPCODE_SEND || op == BRW_OPCODE_SENDC || op == BRW_OPCODE_SENDS || op == BRW_OPCODE_SENDSC; }
static bool xl_is_flow(unsigned op)
{
   return op == BRW_OPCODE_IF || op == BRW_OPCODE_ELSE || op == BRW_OPCODE_ENDIF || op == BRW_OPCODE_WHILE ||
          op == BRW_OPCODE_BREAK || op == BRW_OPCODE_CONTINUE || op == BRW_OPCODE_HALT || op == BRW_OPCODE_JMPI ||
          op == BRW_OPCODE_CALL || op == BRW_OPCODE_CALLA || op == BRW_OPCODE_RET || op == BRW_OPCODE_BRD || op == BRW_OPCODE_BRC;
}

/* Index of the instruction at a byte offset of the Gen11 kernel (n = one past the end), or -1 */
static int xl_index_of(int n, int64_t old_off)
{
   int lo = 0, hi = n;
   while (lo <= hi) {
      int mid = (lo + hi) / 2;
      int64_t v = (int64_t)xl_in[mid].old_off;
      if (v == old_off) return mid;
      if (v < old_off) lo = mid + 1; else hi = mid - 1;
   }
   return -1;
}

static void xl_sync(struct brw_codegen *p, unsigned token)
{
   brw_set_default_access_mode(p, BRW_ALIGN_1);
   brw_set_default_exec_size(p, BRW_EXECUTE_1);
   brw_set_default_group(p, 0);
   brw_set_default_mask_control(p, BRW_MASK_DISABLE);
   brw_set_default_predicate_control(p, BRW_PREDICATE_NONE);
   brw_set_default_predicate_inverse(p, false);
   brw_set_default_saturate(p, 0);
   brw_set_default_flag_reg(p, 0, 0);
   brw_set_default_swsb(p, tgl_swsb_sbid(TGL_SBID_DST, token));
   brw_SYNC(p, TGL_SYNC_NOP);
}

static int translate_pass(int n, int old_len, int limit, bool compact_all, uint8_t *outbuf)
{
   static struct brw_codegen p;
   brw_init_codegen(&isa12, &p, ralloc_context(NULL));
   p.automatic_exec_sizes = false;   /* every instruction keeps the execution size it had */
   int bad = 0;
   struct { bool used; struct resset rd, wr; int order; } tok[16];
   memset(tok, 0, sizeof(tok));
   struct resset inflight = {{0}};   /* written by ALU instructions not known to have completed */
   bool first = true;

   for (int i = 0; i < n && !kshim_assert_failed; i++) {
      struct xl_insn *x = &xl_in[i];
      int o = (int)x->old_off;
      if (x->is_pad) {
         /* Never executed: stays 8 bytes of zeros (a placeholder instruction holds its slot until the layout) */
         x->first_out = x->main_out = (int32_t)p.nr_insn;
         brw_NOP(&p);
         continue;
      }
      struct resset rd, wr, all;
      resources(&x->full, &rd, &wr);
      all = rd; rs_or(&all, &wr);
      x->first_out = (int32_t)p.nr_insn;
      bool boundary = x->is_flow || x->is_label;
      bool next_boundary = i + 1 < n && (xl_in[i + 1].is_flow || xl_in[i + 1].is_label);

      /* Same state on every path: nothing outstanding at a branch or a jump target */
      if (boundary)
         for (int t = 0; t < 16; t++)
            if (tok[t].used) { xl_sync(&p, t); tok[t].used = false; }

      /* Outstanding sends this instruction depends on: it reads or writes their response, or writes their payload */
      int conflicts = 0, conflict = -1, oldest = -1, outstanding = 0;
      for (int t = 0; t < 16; t++) {
         if (!tok[t].used) continue;
         outstanding++;
         if (oldest < 0 || tok[t].order < tok[oldest].order) oldest = t;
         if (rs_hit(&all, &tok[t].wr) || rs_hit(&wr, &tok[t].rd)) { conflicts++; conflict = t; }
      }
      /* The EUs complete ordered instructions in order (Mesa's scoreboard pass relies on it: it keeps only the
       * nearest ordered dependency), so "@1" also covers everything older. Only an instruction that gives up
       * "@1" to wait for a send has to be independent of what may still be in flight. */
      bool independent = !rs_hit(&all, &inflight);

      struct tgl_swsb swsb = first ? tgl_swsb_null() : tgl_swsb_regdist(1);
      int waited = -1;
      if (x->is_send) {
         for (int t = 0; t < 16; t++)
            if (tok[t].used && (rs_hit(&all, &tok[t].wr) || rs_hit(&wr, &tok[t].rd))) { xl_sync(&p, t); tok[t].used = false; }
         if (outstanding - conflicts >= 16 && oldest >= 0 && tok[oldest].used) { xl_sync(&p, oldest); tok[oldest].used = false; }
         int t; for (t = 0; t < 16 && tok[t].used; t++);
         if (t == 16) { fail("no free scoreboard token", o); bad++; t = 0; }
         tok[t].used = true; tok[t].rd = rd; tok[t].wr = wr; tok[t].order = i;
         swsb.mode = TGL_SBID_SET; swsb.sbid = t;
      } else if (conflicts == 1 && independent && !next_boundary && !boundary) {
         waited = conflict;
         swsb = tgl_swsb_sbid(TGL_SBID_DST, waited);
         tok[waited].used = false;
      } else if (conflicts >= 1) {
         for (int t = 0; t < 16; t++)
            if (tok[t].used && (rs_hit(&all, &tok[t].wr) || rs_hit(&wr, &tok[t].rd))) { xl_sync(&p, t); tok[t].used = false; }
      } else if (oldest >= 0 && independent && !next_boundary && !boundary) {
         waited = oldest;
         swsb = tgl_swsb_sbid(TGL_SBID_DST, waited);
         tok[waited].used = false;
      }

      unsigned before = p.nr_insn;
      xl_ex_const = x->ex_const;
      xl_ex_value = x->ex_value;
      if (translate_one(&p, &x->full, o, swsb) < 0) { bad++; brw_NOP(&p); }
      if (p.nr_insn != before + 1) { fail("expanded to more than one instruction", o); bad++; }
      x->main_out = (int32_t)(p.nr_insn - 1);
      first = false;

      if (x->is_send) memset(&inflight, 0, sizeof(inflight));
      else if (waited >= 0) rs_or(&inflight, &wr);
      else inflight = wr;
      if (p.nr_insn > 2 * XL_MAX_INSNS) { fail("too many instructions", o); bad++; break; }
   }
   if (bad || kshim_assert_failed) return -1;

   /* Layout. Which output instructions may be compacted: the translation of a compacted instruction, or
    * everything except flow control when room is short. */
   int nout = (int)p.nr_insn;
   memset(xl_out_try, compact_all ? 1 : 0, (size_t)nout);
   for (int i = 0; i < n; i++) {
      if (xl_in[i].is_pad) xl_out_try[xl_in[i].main_out] = 2;
      else if (xl_in[i].is_flow || (xl_in[i].indirect && !xl_in[i].compacted)) xl_out_try[xl_in[i].main_out] = 0;
      else if (xl_in[i].compacted) xl_out_try[xl_in[i].main_out] = 1;
   }
   int total = 0;
   for (int k = 0; k < nout; k++) {
      brw_compact_inst c;
      xl_out_small[k] = xl_out_try[k] == 2 || (xl_out_try[k] && brw_try_compact_instruction(&isa12, &c, &p.store[k]));
      xl_out_off[k] = (uint32_t)total;
      total += xl_out_small[k] ? 8 : 16;
   }
   xl_out_off[nout] = (uint32_t)total;
   if (total > limit) return -2;

   /* Jump offsets: relative to the jump instruction itself, in bytes, to the first instruction emitted for the
    * target (so a wait inserted in front of a jump target is executed on that path too) */
   for (int i = 0; i < n; i++) {
      struct xl_insn *x = &xl_in[i];
      if (!x->is_flow) continue;
      brw_inst *out = &p.store[x->main_out];
      int self = (int)xl_out_off[x->main_out];
      int kind = xl_jump_kind(&x->full);
      if (kind == 0) continue;   /* rejected in translate_one */
      if (kind == 1) {
         int t = xl_index_of(n, (int64_t)x->old_off + (x->compacted ? 8 : 16) + (int)brw_inst_imm_d(&d11, &x->full));
         if (t < 0) { fail("jump target is not an instruction", (int)x->old_off); return -1; }
         brw_set_src1(&p, out, brw_imm_d((t == n ? total : (int)xl_out_off[xl_in[t].first_out]) - (self + 16)));
         continue;
      }
      int tj = xl_index_of(n, (int64_t)x->old_off + (int)brw_inst_jip(&d11, &x->full));
      if (tj < 0) { fail("jump target is not an instruction", (int)x->old_off); return -1; }
      brw_inst_set_jip(&d12, out, (tj == n ? total : (int)xl_out_off[xl_in[tj].first_out]) - self);
      if (kind == 3) {
         int tu = xl_index_of(n, (int64_t)x->old_off + (int)brw_inst_uip(&d11, &x->full));
         if (tu < 0) { fail("jump target is not an instruction", (int)x->old_off); return -1; }
         brw_inst_set_uip(&d12, out, (tu == n ? total : (int)xl_out_off[xl_in[tu].first_out]) - self);
      }
   }
   if (kshim_assert_failed) return -1;

   for (int k = 0; k < nout; k++) {
      brw_compact_inst c;
      if (xl_out_try[k] == 2) memset(outbuf + xl_out_off[k], 0, 8);
      else if (xl_out_small[k] && brw_try_compact_instruction(&isa12, &c, &p.store[k])) memcpy(outbuf + xl_out_off[k], &c, 8);
      else if (xl_out_small[k]) { fail("compaction changed", xl_out_off[k]); return -1; }
      else memcpy(outbuf + xl_out_off[k], &p.store[k], 16);
   }
   /* Nothing of the old code is left behind */
   if (total < old_len) memset(outbuf + total, 0, (size_t)(old_len - total));
   XLATE_TRACE("   %d instructions -> %d, %d bytes -> %d (limit %d)%s\n", n, nout, old_len, total, limit, compact_all ? ", all compacted" : "");
   return total > old_len ? total : old_len;
}

static int translate(const uint8_t *code, int size, uint8_t *outbuf)
{
   /* Decode. A kernel normally ends at its send with EOT, but code that jumps reach can follow it, and
    * compilers pad with zeros (8 bytes at a time) inside a kernel; so decoding goes on while a jump seen so far
    * targets something further on. */
   int o = 0, n = 0, max_target = 0;
   bool ended = false, flow = false, indirect = false;
   struct resset used = {{0}};
   bool nf16 = false, nf = false;
   while (o + 8 <= size && n < XL_MAX_INSNS) {
      const brw_inst *in = (const brw_inst *)(code + o);
      struct xl_insn *x = &xl_in[n];
      memset(x, 0, sizeof(*x));
      x->old_off = (uint32_t)o;
      if (((const uint64_t *)in)[0] == 0) {
         if (max_target <= o) break;
         x->is_pad = 1; x->compacted = 1;
         o += 8; n++;
         continue;
      }
      x->compacted = brw_inst_cmpt_control(&d11, in);
      if (!x->compacted && o + 16 > size) break;
      if (x->compacted) brw_uncompact_instruction(&isa11, &x->full, (brw_compact_inst *)in); else x->full = *in;
      unsigned op = brw_inst_opcode(&isa11, &x->full);
      const struct opcode_desc *desc = brw_opcode_desc(&isa11, op);
      unsigned hw = brw_inst_hw_opcode(&d11, &x->full);
      if (!desc || (op == BRW_OPCODE_ILLEGAL && hw != XL_HW_JOIN)) { fail("unknown opcode", o); return -o - 1; }
      x->is_send = xl_is_send(op);
      x->is_flow = xl_is_flow(op) || hw == XL_HW_GOTO || hw == XL_HW_JOIN;
      flow |= x->is_flow;
      int len = x->compacted ? 8 : 16;
      if (x->is_flow) {
         int64_t t = -1, u = -1; int kind = xl_jump_kind(&x->full);
         if (kind == 1) t = (int64_t)o + len + (int)brw_inst_imm_d(&d11, &x->full);
         if (kind >= 2) t = (int64_t)o + (int)brw_inst_jip(&d11, &x->full);
         if (kind == 3) u = (int64_t)o + (int)brw_inst_uip(&d11, &x->full);
         if (t > size || u > size) { xl_info.need_more = 1; fail("jump beyond the bytes read", o); return -o - 1; }
         if (t > max_target) max_target = (int)t;
         if (u > max_target) max_target = (int)u;
      }
      struct resset rd, wr;
      resources(&x->full, &rd, &wr); rs_or(&used, &rd); rs_or(&used, &wr);
      indirect |= xl_indirect;
      x->indirect = xl_indirect;
      if (desc->nsrc == 3 && brw_inst_3src_access_mode(&d11, &x->full) == BRW_ALIGN_1 &&
          (brw_inst_3src_a1_dst_type(&d11, &x->full) == BRW_REGISTER_TYPE_NF || brw_inst_3src_a1_src0_type(&d11, &x->full) == BRW_REGISTER_TYPE_NF)) {
         nf = true;
         if (brw_inst_exec_size(&d11, &x->full) > BRW_EXECUTE_8) nf16 = true;
      }
      o += len;
      n++;
      if (x->is_send && brw_inst_eot(&d11, &x->full)) {
         x->eot = 1; ended = true;
         if (max_target <= o) break;
      }
   }
   if (max_target > o) ended = false;
   if (nf && indirect) { fail("NF accumulator together with register-indirect addressing", 0); return -o - 1; }
   xl_info.instructions = n;
   if (!ended) { xl_info.need_more = o + 16 >= size || n >= XL_MAX_INSNS; fail("no end of thread within the buffer", o); return -o - 1; }
   int old_len = o;
   xl_in[n].old_off = (uint32_t)old_len;   /* a jump may target the end */
   xl_in[n].first_out = -1;

   /* Jump targets */
   for (int i = 0; i < n && flow; i++) {
      struct xl_insn *x = &xl_in[i];
      if (!x->is_flow || x->is_pad) continue;
      int kind = xl_jump_kind(&x->full), t;
      if (kind == 1 && (t = xl_index_of(n, (int64_t)x->old_off + (x->compacted ? 8 : 16) + (int)brw_inst_imm_d(&d11, &x->full))) >= 0) xl_in[t].is_label = 1;
      if (kind >= 2 && (t = xl_index_of(n, (int64_t)x->old_off + (int)brw_inst_jip(&d11, &x->full))) >= 0) xl_in[t].is_label = 1;
      if (kind == 3 && (t = xl_index_of(n, (int64_t)x->old_off + (int)brw_inst_uip(&d11, &x->full))) >= 0) xl_in[t].is_label = 1;
   }

   /* A split send that takes its extended descriptor from a0.n, loaded with a constant just before */
   for (int i = 1; i < n; i++) {
      struct xl_insn *x = &xl_in[i], *m = &xl_in[i - 1];
      if (x->is_pad || m->is_pad) continue;
      unsigned op = brw_inst_opcode(&isa11, &x->full);
      if ((op != BRW_OPCODE_SENDS && op != BRW_OPCODE_SENDSC) || !brw_inst_send_sel_reg32_ex_desc(&d11, &x->full) || x->is_label) continue;
      if (brw_inst_opcode(&isa11, &m->full) != BRW_OPCODE_MOV || brw_inst_access_mode(&d11, &m->full) != BRW_ALIGN_1) continue;
      if (brw_inst_dst_reg_file(&d11, &m->full) != BRW_ARCHITECTURE_REGISTER_FILE || brw_inst_dst_da_reg_nr(&d11, &m->full) != BRW_ARF_ADDRESS) continue;
      if (brw_inst_dst_address_mode(&d11, &m->full) != BRW_ADDRESS_DIRECT || brw_inst_src0_reg_file(&d11, &m->full) != BRW_IMMEDIATE_VALUE) continue;
      if (brw_inst_dst_type(&d11, &m->full) != BRW_REGISTER_TYPE_UD || brw_inst_src0_type(&d11, &m->full) != BRW_REGISTER_TYPE_UD) continue;
      if (brw_inst_pred_control(&d11, &m->full) || brw_inst_dst_da1_subreg_nr(&d11, &m->full) != 4 * brw_inst_send_ex_desc_ia_subreg_nr(&d11, &x->full)) continue;
      x->ex_const = 1;
      x->ex_value = brw_inst_imm_ud(&d11, &m->full);
   }

   /* Registers the kernel never names stand in for acc0/acc1 in the native (NF) format: one each for SIMD8,
    * a pair each for SIMD16 */
   nf_scratch[0] = nf_scratch[1] = -1;
   if (nf) {
      int found = 0, width = nf16 ? 2 : 1;
      for (int r = 127 - (width - 1); r >= 2 && found < 2; r--) {
         bool free_ = true;
         for (int k = 0; k < width; k++) if (used.w[(r + k) / 64] >> ((r + k) % 64) & 1) free_ = false;
         if (!free_) continue;
         nf_scratch[found++] = r;
         for (int k = 0; k < width; k++) rs_add(&used, (unsigned)(r + k));
      }
   }

   /* Room to grow: the zero padding after the kernel up to the next 64-byte boundary */
   int limit = (old_len + 63) & ~63;
   if (limit > size) limit = size;
   for (int k = old_len; k < limit; k++) if (code[k]) { limit = old_len; break; }

   int len = translate_pass(n, old_len, limit, false, outbuf);
   if (len == -2) {
      kshim_assert_failed = 0;
      len = translate_pass(n, old_len, limit, true, outbuf);
      if (len == -2) fail("does not fit: no room for inserted or uncompacted instructions", old_len);
   }
   if (kshim_assert_failed) fail("encoder assertion", old_len);
   if (len <= 0 || xl_info.reason) return -old_len - 1;
   return len;
}

int tgl_xlate_kernel(const uint8_t *code, int size, uint8_t *out, struct tgl_xlate_info *info)
{
   if (!xl_ready) {
      brw_init_isa_info(&isa11, &d11);
      brw_init_isa_info(&isa12, &d12);
      xl_ready = true;
   }
   memset(&xl_info, 0, sizeof(xl_info));
   kshim_assert_failed = 0;
   int len = translate(code, size, out);
   if (info) *info = xl_info;
   return len;
}
