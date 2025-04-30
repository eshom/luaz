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

comptime {
    @export(&luaP_opmodes, .{ .name = "luaP_opmodes", .visibility = .hidden });
}

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
pub inline fn MASK1(n: anytype, p: anytype) comptime_int {
    return ~(~0 << n) << p;
}

/// creates a mask with 'n' 0 bits at position 'p'
pub inline fn MASK0(n: anytype, p: anytype) comptime_int {
    return ~MASK1(n, p);
}

// the following Macros help to manipulate instructions

pub inline fn GET_OPCODE(i: anytype) comptime_int {
    return (i >> POS_OP) & MASK1(SIZE_OP, 0);
}

pub inline fn SET_OPCODE(i: anytype, o: anytype) void {
    i = (i & MASK0(SIZE_OP, POS_OP)) | ((o << POS_OP) & MASK1(SIZE_OP, POS_OP));
}

pub inline fn checkopm(i: anytype, m: anytype) comptime_int {
    getOpMode(GET_OPCODE(i)) == m;
}

pub inline fn getarg(i: anytype, pos: anytype, size: anytype) @TypeOf(i) {
    return @intCast((i >> pos) & MASK1(size, 0));
}

pub inline fn setarg(
    i: anytype,
    v: anytype,
    pos: anytype,
    size: anytype,
) void {
    i = (i & MASK0(size, pos)) | ((v << pos) & MASK1(size, pos));
}

pub inline fn GETARG_A(i: anytype) @TypeOf(i) {
    getarg(i, POS_A, SIZE_A);
}

pub inline fn SETARG_A(i: anytype, v: anytype) void {
    setarg(i, v, POS_A, SIZE_A);
}

pub inline fn GETARG_B(i: anytype) comptime_int {
    check_exp(checkopm(i, OpMode.iABC), getarg(i, POS_B, SIZE_B));
}

pub inline fn GETARG_sB(i: anytype) comptime_int {
    sC2int(GETARG_B(i));
}

pub inline fn SETARG_B(i: anytype) void {
    setarg(i, v, POS_B, SIZE_B);
}

pub inline fn GETARG_C(i: anytype) comptime_int {
    check_exp(checkopm(i, OpMode.iABC), getarg(i, POS_C, SIZE_C));
}

pub inline fn GETARG_sC(i: anytype) comptime_int {
    sC2int(GETARG_C(i));
}

pub inline fn SETARG_C(i: anytype, v: anytype) void {
    setarg(i, v, POS_C, SIZE_C);
}

pub inline fn TESTARG_k(i: anytype) comptime_int {
    check_exp(checkopm(i, OpMode.iABC), i & (1 << POS_k));
}

pub inline fn GETARG_k(i: anytype) comptime_int {
    check_exp(checkopm(i, OpMode.iABC), getarg(i, POS_k, 1));
}

pub inline fn SETARG_k(i: anytype, v: anytype) void {
    setarg(i, v, POS_k, 1);
}

pub inline fn GETARG_Bx(i: anytype) comptime_int {
    check_exp(checkopm(i, OpMode.iABx), getarg(i, POS_Bx, SIZE_Bx));
}

pub inline fn SETARG_Bx(i: anytype, v: anytype) void {
    setarg(i, v, POS_Bx, SIZE_Bx);
}

pub inline fn GETARG_Ax(i: anytype) comptime_int {
    check_exp(checkopm(i, OpMode.iAx), getarg(i, POS_Ax, SIZE_Ax));
}

pub inline fn SETARG_Ax(i: anytype, v: comptime_int) void {
    setarg(i, v, POS_Ax, SIZE_Ax);
}

pub inline fn GETARG_sBx(i: anytype) comptime_int {
    check_exp(checkopm(i, OpMode.iAsBx), getarg(i, POS_Bx, SIZE_Bx) - OFFSET_sBx);
}

pub inline fn SETARG_sBx(i: anytype, b: anytype) void {
    SETARG_Bx(i, b + OFFSET_sBx);
}

pub inline fn GETARG_sJ(i: anytype) comptime_int {
    check_exp(checkopm(i, OpMode.isJ), getarg(i, POS_sJ, SIZE_sJ) - OFFSET_sJ);
}

pub inline fn SETARG_sJ(i: anytype, j: anytype) void {
    setarg(i, j + OFFSET_sJ, POS_sJ, SIZE_sJ);
}

pub inline fn CREATE_ABCk(
    o: climits.Instruction,
    a: climits.Instruction,
    b: climits.Instruction,
    c: climits.Instruction,
    k: climits.Instruction,
) climits.Instruction {
    return (o << POS_OP) | (a << POS_A) | (b << POS_B) | (c << POS_C) | (k << POS_k);
}

pub inline fn CREATE_ABx(
    o: climits.Instruction,
    a: climits.Instruction,
    bc: climits.Instruction,
) climits.Instruction {
    return (o << POS_OP) | (a << POS_A) | (bc << POS_Bx);
}

pub inline fn CREATE_Ax(
    o: climits.Instruction,
    a: climits.Instruction,
) climits.Instruction {
    return (o << POS_OP) | (a << POS_A);
}

pub inline fn CREATE_sJ(
    o: climits.Instruction,
    j: climits.Instruction,
    k: climits.Instruction,
) climits.Instruction {
    return (o << POS_OP) | (j << POS_sJ) | (k << POS_k);
}

// TODO: figure this debug business, and does it matter?

// #if !defined(MAXINDEXRK)  /* (for debugging only) */
// #define MAXINDEXRK MAXARG_B
// #endif

/// invalid register that fits in 8 bits
pub const NO_REG = MAXARG_A;

// R[x] - register
// K[x] - constant (in constant table)
// RK(x) == if k(i) then K[x] else R[x]

/// Grep "ORDER OP" if you change these enums. Opcodes marked with a (*)
/// has extra descriptions in the notes after the enumeration.
pub const OpCode = enum(c_uint) {
    //----------------------------------------------------------------------
    //  name         args    description
    //------------------------------------------------------------------------*/
    OP_MOVE, //      A B     R[A] := R[B]
    OP_LOADI, //     A sBx   R[A] := sBx
    OP_LOADF, //     A sBx   R[A] := (lua_Number)sBx
    OP_LOADK, //     A Bx    R[A] := K[Bx]
    OP_LOADKX, //    A       R[A] := K[extra arg]
    OP_LOADFALSE, // A       R[A] := false
    OP_LFALSESKIP, //A       R[A] := false; pc++    (*)
    OP_LOADTRUE, //  A       R[A] := true
    OP_LOADNIL, //   A B     R[A], R[A+1], ..., R[A+B] := nil
    OP_GETUPVAL, //  A B     R[A] := UpValue[B]
    OP_SETUPVAL, //  A B     UpValue[B] := R[A]

    OP_GETTABUP, //  A B C   R[A] := UpValue[B][K[C]:shortstring]
    OP_GETTABLE, //  A B C   R[A] := R[B][R[C]]
    OP_GETI, //      A B C   R[A] := R[B][C]
    OP_GETFIELD, //  A B C   R[A] := R[B][K[C]:shortstring]

    OP_SETTABUP, //  A B C   UpValue[A][K[B]:shortstring] := RK(C)
    OP_SETTABLE, //  A B C   R[A][R[B]] := RK(C)
    OP_SETI, //      A B C   R[A][B] := RK(C)
    OP_SETFIELD, //  A B C   R[A][K[B]:shortstring] := RK(C)

    OP_NEWTABLE, //  A B C k R[A] := {}

    OP_SELF, //      A B C   R[A+1] := R[B]; R[A] := R[B][RK(C):string]

    OP_ADDI, //      A B sC  R[A] := R[B] + sC

    OP_ADDK, //      A B C   R[A] := R[B] + K[C]:number
    OP_SUBK, //      A B C   R[A] := R[B] - K[C]:number
    OP_MULK, //      A B C   R[A] := R[B] * K[C]:number
    OP_MODK, //      A B C   R[A] := R[B] % K[C]:number
    OP_POWK, //      A B C   R[A] := R[B] ^ K[C]:number
    OP_DIVK, //      A B C   R[A] := R[B] / K[C]:number
    OP_IDIVK, //     A B C   R[A] := R[B] // K[C]:number

    OP_BANDK, //     A B C   R[A] := R[B] & K[C]:integer
    OP_BORK, //      A B C   R[A] := R[B] | K[C]:integer
    OP_BXORK, //     A B C   R[A] := R[B] ~ K[C]:integer

    OP_SHRI, //      A B sC  R[A] := R[B] >> sC
    OP_SHLI, //      A B sC  R[A] := sC << R[B]

    OP_ADD, //       A B C   R[A] := R[B] + R[C]
    OP_SUB, //       A B C   R[A] := R[B] - R[C]
    OP_MUL, //       A B C   R[A] := R[B] * R[C]
    OP_MOD, //       A B C   R[A] := R[B] % R[C]
    OP_POW, //       A B C   R[A] := R[B] ^ R[C]
    OP_DIV, //       A B C   R[A] := R[B] / R[C]
    OP_IDIV, //      A B C   R[A] := R[B] // R[C]

    OP_BAND, //      A B C   R[A] := R[B] & R[C]
    OP_BOR, //       A B C   R[A] := R[B] | R[C]
    OP_BXOR, //      A B C   R[A] := R[B] ~ R[C]
    OP_SHL, //       A B C   R[A] := R[B] << R[C]
    OP_SHR, //       A B C   R[A] := R[B] >> R[C]

    OP_MMBIN, //     A B C    call C metamethod over R[A] and R[B]    (*)
    OP_MMBINI, //    A sB C k call C metamethod over R[A] and sB
    OP_MMBINK, //    A B C k  call C metamethod over R[A] and K[B]

    OP_UNM, //       A B     R[A] := -R[B]
    OP_BNOT, //      A B     R[A] := ~R[B]
    OP_NOT, //       A B     R[A] := not R[B]
    OP_LEN, //       A B     R[A] := #R[B] (length operator)

    OP_CONCAT, //    A B     R[A] := R[A].. ... ..R[A + B - 1]

    OP_CLOSE, //     A       close all upvalues >= R[A]
    OP_TBC, //       A       mark variable A "to be closed"
    OP_JMP, //       sJ      pc += sJ
    OP_EQ, //        A B k   if ((R[A] == R[B]) ~= k) then pc++
    OP_LT, //        A B k   if ((R[A] <  R[B]) ~= k) then pc++
    OP_LE, //        A B k   if ((R[A] <= R[B]) ~= k) then pc++

    OP_EQK, //       A B k   if ((R[A] == K[B]) ~= k) then pc++
    OP_EQI, //       A sB k  if ((R[A] == sB) ~= k) then pc++
    OP_LTI, //       A sB k  if ((R[A] < sB) ~= k) then pc++
    OP_LEI, //       A sB k  if ((R[A] <= sB) ~= k) then pc++
    OP_GTI, //       A sB k  if ((R[A] > sB) ~= k) then pc++
    OP_GEI, //       A sB k  if ((R[A] >= sB) ~= k) then pc++

    OP_TEST, //      A k     if (not R[A] == k) then pc++
    OP_TESTSET, //   A B k   if (not R[B] == k) then pc++ else R[A] := R[B] (*)

    OP_CALL, //      A B C   R[A], ... ,R[A+C-2] := R[A](R[A+1], ... ,R[A+B-1])
    OP_TAILCALL, //  A B C k return R[A](R[A+1], ... ,R[A+B-1])

    OP_RETURN, //    A B C k return R[A], ... ,R[A+B-2]    (see note)
    OP_RETURN0, //           return
    OP_RETURN1, //   A       return R[A]

    OP_FORLOOP, //   A Bx    update counters; if loop continues then pc-=Bx;
    OP_FORPREP, //   A Bx    <check values and prepare counters>;
    //                       if not to run then pc+=Bx+1;

    OP_TFORPREP, //  A Bx    create upvalue for R[A + 3]; pc+=Bx
    OP_TFORCALL, //  A C     R[A+4], ... ,R[A+3+C] := R[A](R[A+1], R[A+2]);
    OP_TFORLOOP, //  A Bx    if R[A+2] ~= nil then { R[A]=R[A+2]; pc -= Bx }

    OP_SETLIST, //   A B C k R[A][C+i] := R[A+i], 1 <= i <= B

    OP_CLOSURE, //   A Bx    R[A] := closure(KPROTO[Bx])

    OP_VARARG, //    A C     R[A], R[A+1], ..., R[A+C-2] = vararg

    OP_VARARGPREP, //A       (adjust vararg parameters)

    OP_EXTRAARG, //  Ax      extra (larger) argument for previous opcode
};

pub const NUM_OPCODES = @intFromEnum(OpCode.OP_EXTRAARG) + 1;

//===========================================================================
//  Notes:
//
//  (*) Opcode OP_LFALSESKIP is used to convert a condition to a boolean
//  value, in a code equivalent to (not cond ? false : true).  (It
//  produces false and skips the next instruction producing true.)
//
//  (*) Opcodes OP_MMBIN and variants follow each arithmetic and
//  bitwise opcode. If the operation succeeds, it skips this next
//  opcode. Otherwise, this opcode calls the corresponding metamethod.
//
//  (*) Opcode OP_TESTSET is used in short-circuit expressions that need
//  both to jump and to produce a value, such as (a = b or c).
//
//  (*) In OP_CALL, if (B == 0) then B = top - A. If (C == 0), then
//  'top' is set to last_result+1, so next open instruction (OP_CALL,
//  OP_RETURN*, OP_SETLIST) may use 'top'.
//
//  (*) In OP_VARARG, if (C == 0) then use actual number of varargs and
//  set top (like in OP_CALL with C == 0).
//
//  (*) In OP_RETURN, if (B == 0) then return up to 'top'.
//
//  (*) In OP_LOADKX and OP_NEWTABLE, the next instruction is always
//  OP_EXTRAARG.
//
//  (*) In OP_SETLIST, if (B == 0) then real B = 'top'; if k, then
//  real C = EXTRAARG _ C (the bits of EXTRAARG concatenated with the
//  bits of C).
//
//  (*) In OP_NEWTABLE, B is log2 of the hash size (which is always a
//  power of 2) plus 1, or zero for size zero. If not k, the array size
//  is C. Otherwise, the array size is EXTRAARG _ C.
//
//  (*) For comparisons, k specifies what condition the test should accept
//  (true or false).
//
//  (*) In OP_MMBINI/OP_MMBINK, k means the arguments were flipped
//   (the constant is the first operand).
//
//  (*) All 'skips' (pc++) assume that next instruction is a jump.
//
//  (*) In instructions OP_RETURN/OP_TAILCALL, 'k' specifies that the
//  function builds upvalues, which may need to be closed. C > 0 means
//  the function is vararg, so that its 'func' must be corrected before
//  returning; in this case, (C - 1) is its number of fixed parameters.
//
//  (*) In comparisons with an immediate operand, C signals whether the
//  original operand was a float. (It must be corrected in case of
//  metamethods.)
//
//===========================================================================*/

/// masks for instruction properties. The format is:
/// bits 0-2: op mode
/// bit 3: instruction set register A
/// bit 4: operator is a test (next instruction must be a jump)
/// bit 5: instruction uses 'L->top' set by previous instruction (when B == 0)
/// bit 6: instruction sets 'L->top' for next instruction (when C == 0)
/// bit 7: instruction is an MM instruction (call a metamethod)
pub const luaP_opmodes: [NUM_OPCODES]climits.lu_byte = .{
    //     MM OT IT T  A  mode             opcode
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_MOVE
    opmode(0, 0, 0, 0, 1, OpMode.iAsBx), //OP_LOADI
    opmode(0, 0, 0, 0, 1, OpMode.iAsBx), //OP_LOADF
    opmode(0, 0, 0, 0, 1, OpMode.iABx), // OP_LOADK
    opmode(0, 0, 0, 0, 1, OpMode.iABx), // OP_LOADKX
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_LOADFALSE
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_LFALSESKIP
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_LOADTRUE
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_LOADNIL
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_GETUPVAL
    opmode(0, 0, 0, 0, 0, OpMode.iABC), // OP_SETUPVAL
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_GETTABUP
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_GETTABLE
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_GETI
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_GETFIELD
    opmode(0, 0, 0, 0, 0, OpMode.iABC), // OP_SETTABUP
    opmode(0, 0, 0, 0, 0, OpMode.iABC), // OP_SETTABLE
    opmode(0, 0, 0, 0, 0, OpMode.iABC), // OP_SETI
    opmode(0, 0, 0, 0, 0, OpMode.iABC), // OP_SETFIELD
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_NEWTABLE
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_SELF
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_ADDI
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_ADDK
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_SUBK
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_MULK
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_MODK
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_POWK
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_DIVK
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_IDIVK
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_BANDK
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_BORK
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_BXORK
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_SHRI
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_SHLI
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_ADD
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_SUB
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_MUL
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_MOD
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_POW
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_DIV
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_IDIV
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_BAND
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_BOR
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_BXOR
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_SHL
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_SHR
    opmode(1, 0, 0, 0, 0, OpMode.iABC), // OP_MMBIN
    opmode(1, 0, 0, 0, 0, OpMode.iABC), // OP_MMBINI
    opmode(1, 0, 0, 0, 0, OpMode.iABC), // OP_MMBINK
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_UNM
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_BNOT
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_NOT
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_LEN
    opmode(0, 0, 0, 0, 1, OpMode.iABC), // OP_CONCAT
    opmode(0, 0, 0, 0, 0, OpMode.iABC), // OP_CLOSE
    opmode(0, 0, 0, 0, 0, OpMode.iABC), // OP_TBC
    opmode(0, 0, 0, 0, 0, OpMode.isJ), //  OP_JMP
    opmode(0, 0, 0, 1, 0, OpMode.iABC), // OP_EQ
    opmode(0, 0, 0, 1, 0, OpMode.iABC), // OP_LT
    opmode(0, 0, 0, 1, 0, OpMode.iABC), // OP_LE
    opmode(0, 0, 0, 1, 0, OpMode.iABC), // OP_EQK
    opmode(0, 0, 0, 1, 0, OpMode.iABC), // OP_EQI
    opmode(0, 0, 0, 1, 0, OpMode.iABC), // OP_LTI
    opmode(0, 0, 0, 1, 0, OpMode.iABC), // OP_LEI
    opmode(0, 0, 0, 1, 0, OpMode.iABC), // OP_GTI
    opmode(0, 0, 0, 1, 0, OpMode.iABC), // OP_GEI
    opmode(0, 0, 0, 1, 0, OpMode.iABC), // OP_TEST
    opmode(0, 0, 0, 1, 1, OpMode.iABC), // OP_TESTSET
    opmode(0, 1, 1, 0, 1, OpMode.iABC), // OP_CALL
    opmode(0, 1, 1, 0, 1, OpMode.iABC), // OP_TAILCALL
    opmode(0, 0, 1, 0, 0, OpMode.iABC), // OP_RETURN
    opmode(0, 0, 0, 0, 0, OpMode.iABC), // OP_RETURN0
    opmode(0, 0, 0, 0, 0, OpMode.iABC), // OP_RETURN1
    opmode(0, 0, 0, 0, 1, OpMode.iABx), // OP_FORLOOP
    opmode(0, 0, 0, 0, 1, OpMode.iABx), // OP_FORPREP
    opmode(0, 0, 0, 0, 0, OpMode.iABx), // OP_TFORPREP
    opmode(0, 0, 0, 0, 0, OpMode.iABC), // OP_TFORCALL
    opmode(0, 0, 0, 0, 1, OpMode.iABx), // OP_TFORLOOP
    opmode(0, 0, 1, 0, 0, OpMode.iABC), // OP_SETLIST
    opmode(0, 0, 0, 0, 1, OpMode.iABx), // OP_CLOSURE
    opmode(0, 1, 0, 0, 1, OpMode.iABC), // OP_VARARG
    opmode(0, 0, 1, 0, 1, OpMode.iABC), // OP_VARARGPREP
    opmode(0, 0, 0, 0, 0, OpMode.iAx), //  OP_EXTRAARG
};

pub inline fn getOpMode(m: comptime_int) OpMode {
    return @enumFromInt(luaP_opmodes[m] & 7);
}

pub inline fn testAMode(m: comptime_int) OpMode {
    return @enumFromInt(luaP_opmodes[m] & (1 << 3));
}

pub inline fn testTMode(m: comptime_int) OpMode {
    return @enumFromInt(luaP_opmodes[m] & (1 << 4));
}

pub inline fn testITMode(m: comptime_int) OpMode {
    return @enumFromInt(luaP_opmodes[m] & (1 << 5));
}

pub inline fn testOTMode(m: comptime_int) OpMode {
    return @enumFromInt(luaP_opmodes[m] & (1 << 6));
}

pub inline fn testMMMode(m: comptime_int) OpMode {
    return @enumFromInt(luaP_opmodes[m] & (1 << 7));
}

/// "out top" (set top for next instruction)
pub inline fn isOT(i: anytype) bool {
    return (testOTMode(GET_OPCODE(i)) and GETARG_C(i) == 0) or
        GET_OPCODE(i) == OpCode.OP_TAILCALL;
}

pub inline fn isIT(i: anytype) bool {
    return testITMode(GET_OPCODE(i)) and GETARG_B(i) == 0;
}

pub inline fn opmode(
    mm: anytype,
    ot: anytype,
    it: anytype,
    t: anytype,
    a: anytype,
    m: anytype,
) @TypeOf(mm, ot, it, t, a, m) {
    return (((mm) << 7) | ((ot) << 6) | ((it) << 5) | ((t) << 4) | ((a) << 3) | (m));
}

pub const LFIELDS_PER_FLUSH = 50;
