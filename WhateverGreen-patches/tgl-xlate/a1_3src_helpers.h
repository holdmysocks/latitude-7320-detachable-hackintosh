static enum brw_vertical_stride
vstride_from_align1_3src_vstride(const struct intel_device_info *devinfo,
                                 enum gfx10_align1_3src_vertical_stride vstride)
{
   switch (vstride) {
   case BRW_ALIGN1_3SRC_VERTICAL_STRIDE_0: return BRW_VERTICAL_STRIDE_0;
   case BRW_ALIGN1_3SRC_VERTICAL_STRIDE_2:
      if (devinfo->ver >= 12)
         return BRW_VERTICAL_STRIDE_1;
      else
         return BRW_VERTICAL_STRIDE_2;
   case BRW_ALIGN1_3SRC_VERTICAL_STRIDE_4: return BRW_VERTICAL_STRIDE_4;
   case BRW_ALIGN1_3SRC_VERTICAL_STRIDE_8: return BRW_VERTICAL_STRIDE_8;
   default:
      unreachable("not reached");
   }
}

static enum brw_horizontal_stride
hstride_from_align1_3src_hstride(enum gfx10_align1_3src_src_horizontal_stride hstride)
{
   switch (hstride) {
   case BRW_ALIGN1_3SRC_SRC_HORIZONTAL_STRIDE_0: return BRW_HORIZONTAL_STRIDE_0;
   case BRW_ALIGN1_3SRC_SRC_HORIZONTAL_STRIDE_1: return BRW_HORIZONTAL_STRIDE_1;
   case BRW_ALIGN1_3SRC_SRC_HORIZONTAL_STRIDE_2: return BRW_HORIZONTAL_STRIDE_2;
   case BRW_ALIGN1_3SRC_SRC_HORIZONTAL_STRIDE_4: return BRW_HORIZONTAL_STRIDE_4;
   default:
      unreachable("not reached");
   }
}

static enum brw_vertical_stride
vstride_from_align1_3src_hstride(enum gfx10_align1_3src_src_horizontal_stride hstride)
{
   switch (hstride) {
   case BRW_ALIGN1_3SRC_SRC_HORIZONTAL_STRIDE_0: return BRW_VERTICAL_STRIDE_0;
   case BRW_ALIGN1_3SRC_SRC_HORIZONTAL_STRIDE_1: return BRW_VERTICAL_STRIDE_1;
   case BRW_ALIGN1_3SRC_SRC_HORIZONTAL_STRIDE_2: return BRW_VERTICAL_STRIDE_2;
   case BRW_ALIGN1_3SRC_SRC_HORIZONTAL_STRIDE_4: return BRW_VERTICAL_STRIDE_4;
   default:
      unreachable("not reached");
   }
}

static enum brw_width
implied_width(enum brw_vertical_stride _vert_stride,
              enum brw_horizontal_stride _horiz_stride)
{
   /* "1. Width is 1 when Vertical and Horizontal Strides are both zero." */
   if (_vert_stride == BRW_VERTICAL_STRIDE_0 &&
       _horiz_stride == BRW_HORIZONTAL_STRIDE_0) {
      return BRW_WIDTH_1;

   /* "2. Width is equal to vertical stride when Horizontal Stride is zero." */
   } else if (_horiz_stride == BRW_HORIZONTAL_STRIDE_0) {
      switch (_vert_stride) {
      case BRW_VERTICAL_STRIDE_1: return BRW_WIDTH_1;
      case BRW_VERTICAL_STRIDE_2: return BRW_WIDTH_2;
      case BRW_VERTICAL_STRIDE_4: return BRW_WIDTH_4;
      case BRW_VERTICAL_STRIDE_8: return BRW_WIDTH_8;
      case BRW_VERTICAL_STRIDE_0:
      default:
         unreachable("not reached");
      }

   } else {
      /* FINISHME: Implement these: */

      /* "3. Width is equal to Vertical Stride/Horizontal Stride when both
       *     Strides are non-zero.
       *
       *  4. Vertical Stride must not be zero if Horizontal Stride is non-zero.
       *     This implies Vertical Stride is always greater than Horizontal
       *     Stride."
       *
       * Given these statements and the knowledge that the stride and width
       * values are encoded in logarithmic form, we can perform the division
       * by just subtracting.
       */
      return _vert_stride - _horiz_stride;
   }
}

