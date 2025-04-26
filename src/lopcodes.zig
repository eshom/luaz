//!   We assume that instructions are unsigned 32-bit integers.
//!   All instructions have an opcode in the first 7 bits.
//!   Instructions can have the following formats:
//!
//!         3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
//!         1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
//! iABC          C(8)     |      B(8)     |k|     A(8)      |   Op(7)     |
//! iABx                Bx(17)               |     A(8)      |   Op(7)     |
//! iAsBx              sBx (signed)(17)      |     A(8)      |   Op(7)     |
//! iAx                           Ax(25)                     |   Op(7)     |
//! isJ                           sJ (signed)(25)            |   Op(7)     |
//!
//!   A signed argument is represented in excess K: the represented value is
//!   the written unsigned value minus K, where K is half the maximum for the
//!   corresponding unsigned argument.

const climits = @import("llimits_h");

const std = @import("std");

// basic instruction formats
pub const OpMode = enum(c_uint) { iABC, iABx, iAsBx, iAx, isJ };

// size and position of opcode arguments
pub const SIZE_C = 8;
pub const SIZE_B = 8;
pub const SIZE_Bx = SIZE_C + SIZE_B + 1;
pub const SIZE_A = 8;
pub const SIZE_Ax = SIZE_Bx + SIZE_A;
pub const SIZE_sJ = SIZE_Bx + SIZE_A;

pub const SIZE_OP = 7;
pub const POS_OP = 0;

pub const POS_A = POS_OP + SIZE_OP;
pub const POS_k = POS_A + SIZE_A;
pub const POS_B = POS_k + 1;
pub const POS_C = POS_B + SIZE_B;

const POS_Bx = POS_k;
const POS_Ax = POS_A;
const POS_sJ = POS_A;

// limits for opcode arguments.
// we use (signed) 'int' to manipulate most arguments,
// so they must fit in ints.

// Check whether type 'int' has at least 'b' bits ('b' < 32)
pub inline fn L_INTHASBITS(b: comptime_int) bool {
    (std.math.maxInt(c_uint) >> b - 1) >= 1;
}

pub inline fn MAXARG_Bx() comptime_int {
    if (L_INTHASBITS(SIZE_Bx)) {
        return (1 << SIZE_Bx) - 1;
    } else {
        return std.math.maxInt(c_int);
    }
}

pub const OFFSET_sBx = MAXARG_Bx() >> 1; // sBx is signed

pub inline fn MAXARG_Ax() comptime_int {
    if (L_INTHASBITS(SIZE_Ax)) {
        return (1 << SIZE_Ax) - 1;
    } else {
        return std.math.maxInt(c_int);
    }
}

pub inline fn MAXARG_sJ() comptime_int {
    if (L_INTHASBITS(SIZE_sJ)) {
        return (1 << SIZE_sJ) - 1;
    } else {
        return std.math.maxInt(c_int);
    }
}

pub const OFFSET_sJ = MAXARG_sJ() >> 1;

pub const MAXARG_A = (1 << SIZE_A) - 1;
pub const MAXARG_B = (1 << SIZE_B) - 1;
pub const MAXARG_C = (1 << SIZE_C) - 1;
pub const OFFSET_sC = MAXARG_C >> 1;

pub inline fn int2sC(i: comptime_int) comptime_int {
    return i + OFFSET_sC;
}

pub inline fn sC2int(i: comptime_int) comptime_int {
    return i - OFFSET_sC;
}

// TODO: Why triple NOT?

/// creates a mask with 'n' 1 bits at position 'p'
pub inline fn MASK1(n: comptime_int, p: comptime_int) climits.Instruction {
    return ~(~0 << n) << p;
}

/// creates a mask with 'n' 0 bits at position 'p'
pub inline fn MASK0(n: comptime_int, p: comptime_int) climits.Instruction {
    return ~MASK1(n, p);
}

// the following Macros help to manipulate instructions

pub inline fn GET_OPCODE(i: comptime_int) OpCode {
    return (i >> POS_OP) & MASK1(SIZE_OP, 0);
}

pub inline fn SET_OPCODE(i: climits.Instruction, o: OpCode) void {
    i = (i & MASK0(SIZE_OP, POS_OP)) | ((o << POS_OP) & MASK1(SIZE_OP, POS_OP));
}

pub inline fn checkopm(i: climits.Instruction, m: OpMode) bool {
    getOpMode(GET_OPCODE(i)) == m;
}

pub inline fn getarg(i: climits.Instruction, pos: comptime_int, size: comptime_int) c_int {
    return @intCast((i >> pos) & MASK1(size, 0));
}

pub inline fn setarg(
    i: climits.Instruction,
    v: climits.Instruction,
    pos: comptime_int,
    size: comptime_int,
) void {
    i = (i & MASK0(size, pos)) | ((v << pos) & MASK1(size, pos));
}

pub inline fn GETARG_A(i: climits.Instruction) c_int {
    getarg(i, POS_A, SIZE_A);
}

pub inline fn SETARG_A(i: climits.Instruction, v: comptime_int) void {
    setarg(i, v, POS_A, SIZE_A);
}

pub inline fn GETARG_B(i: climits.Instruction) c_int {
    check_exp(checkopm(i, OpMode.iABC), getarg(i, POS_B, SIZE_B));
}

pub inline fn GETARG_sB(i: climits.Instruction) c_int {
    sC2int(GETARG_B(i));
}

pub inline fn SETARG_B(i: climits.Instruction, v: comptime_int) void {
    setarg(i, v, POS_B, SIZE_B);
}

pub inline fn GETARG_C(i: climits.Instruction) c_int {
    check_exp(checkopm(i, OpMode.iABC), getarg(i, POS_C, SIZE_C));
}

pub inline fn GETARG_sC(i: climits.Instruction) c_int {
    sC2int(GETARG_C(i));
}

pub inline fn SETARG_C(i: climits.Instruction, v: comptime_int) void {
    setarg(i, v, POS_C, SIZE_C);
}

pub inline fn TESTARG_k(i: climits.Instruction) c_int {
    check_exp(checkopm(i, OpMode.iABC), i & (1 << POS_k));
}

pub inline fn GETARG_k(i: climits.Instruction) c_int {
    check_exp(checkopm(i, OpMode.iABC), getarg(i, POS_k, 1));
}

pub inline fn SETARG_k(i: climits.Instruction, v: comptime_int) void {
    setarg(i, v, POS_k, 1);
}

pub inline fn GETARG_Bx(i: climits.Instruction) c_int {
    check_exp(checkopm(i, OpMode.iABx), getarg(i, POS_Bx, SIZE_Bx));
}

pub inline fn SETARG_Bx(i: climits.Instruction, v: comptime_int) void {
    setarg(i, v, POS_Bx, SIZE_Bx);
}

pub inline fn GETARG_Ax(i: climits.Instruction) c_int {
    check_exp(checkopm(i, OpMode.iAx), getarg(i, POS_Ax, SIZE_Ax));
}

pub inline fn SETARG_Ax(i: climits.Instruction, v: comptime_int) void {
    setarg(i, v, POS_Ax, SIZE_Ax);
}

pub inline fn GETARG_sBx(i: climits.Instruction) c_int {
    check_exp(checkopm(i, OpMode.iAsBx), getarg(i, POS_Bx, SIZE_Bx) - OFFSET_sBx);
}

pub inline fn SETARG_sBx(i: climits.Instruction, b: comptime_int) void {
    SETARG_Bx(i, b + OFFSET_sBx);
}

pub inline fn GETARG_sJ(i: climits.Instruction) c_int {
    check_exp(checkopm(i, OpMode.isJ), getarg(i, POS_sJ, SIZE_sJ) - OFFSET_sJ);
}

pub inline fn SETARG_sJ(i: climits.Instruction, j: comptime_int) void {
    setarg(i, j + OFFSET_sJ, POS_sJ, SIZE_sJ);
}
