(***********************************************************************)
(*                                                                     *)
(*                                OCaml                                *)
(*                                                                     *)
(*        Fabrice Le Fessant, projet Gallium, INRIA Rocquencourt       *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

(** Helpers for Intel code generators *)

(* The DSL* modules expose functions to emit x86/x86_64 instructions
   using a syntax close to AT&T (in particular, arguments are reversed compared
   to the official Intel syntax).

   Some notes:

     - Unary floating point instructions such as fadd/fmul/fstp/fld/etc come with a single version
       supporting both the single and double precision instructions.  (As with Intel syntax.)

     - A legacy bug in GAS:
       https://sourceware.org/binutils/docs-2.22/as/i386_002dBugs.html#i386_002dBugs
       is not replicated here.  It is managed by Intel_gas.
*)


open Intel_ast
open Intel_proc

module Check = struct

  (* These functions are used to check the datatype on instruction arguments
     against a gas-style instruction suffix. *)

  let check ty = function
    | Mem32 {typ; _}
    | Mem64 {typ; _} -> assert(typ = ty)
    | arg ->
        match arg, ty with
        | (Reg16 _ | Reg32 _ | Reg64 _ | Regf _), BYTE
        | (Reg8 _ | Reg32 _ | Reg64 _ | Regf _), WORD
        | (Reg8 _ | Reg16 _ | Reg64 _ | Regf _), DWORD
        | (Reg8 _ | Reg16 _ | Reg32 _ | Regf _), QWORD
        | (Reg8 _ | Reg16 _ | Reg32 _ | Reg64 _), REAL8 -> assert false
        | _ -> ()

  let byte x = check BYTE x; x
  let word x = check WORD x; x
  let dword x = check DWORD x; x
  let qword x = check QWORD x; x
  let option chk = function
      None -> None
    | Some arg -> Some (chk arg)
end

module DSL = struct
  let sym s = Sym s

  (* Override emitaux.ml *)
  let emit_nat n = Imm (Int64.of_nativeint n)
  let int n = Imm (Int64.of_int n)

  let const_64 n = Const n
  let const_32 n = Const (Int64.of_int32 n)
  let const_nat n = Const (Int64.of_nativeint n)
  let const n = Const (Int64.of_int n)

  let _cfi_startproc () = directive Cfi_startproc
  let _cfi_endproc () = directive Cfi_endproc
  let _cfi_adjust_cfa_offset n = directive (Cfi_adjust_cfa_offset n)
  let _file num filename = directive (File (num, filename))
  let _loc num loc = directive (Loc (num, loc))
  let _section segment flags args = directive (Section (segment, flags, args))
  let _text () = _section [ ".text" ] None []
  let _data () = _section [ ".data" ] None []
  let _section segment flags args = directive (Section (segment, flags, args))
  let _386 () = directive Mode386
  let _model name = directive (Model name)
  let _global s = directive (Global s)
  let _align n = directive (Align (false, n))
  let _llabel s = directive (NewLabel (s, NO)) (* local label *)
  let _comment s = directive (Comment s)
  let _extrn s ptr = directive (External (s, ptr))
  let _private_extern s = directive (Private_extern s)
  let _indirect_symbol s = directive (Indirect_symbol s)
  let _size name cst = directive (Size (name, cst))
  let _type name typ = directive (Type (name, typ))

  let _qword cst = directive (Quad cst)
  let _long cst = directive (Long cst)
  let _word cst = directive (Word cst)
  let _byte n = directive (Byte n)
  let _ascii s = directive (Bytes s)
  let _space n = directive (Space n)
  let _setvar (arg1, arg2) = directive (Set (arg1, arg2))
  let _end () = directive End
  (* mnemonics *)

end

module INS = struct

  open Check

  (* eta-expand to create ref everytime *)
  let jmp arg = emit (JMP arg)
  let call arg = emit (CALL arg)
  let set cond arg = emit (SET (cond, arg))

  let j cond arg = emit (J (cond, arg))
  let je = j E
  let jae = j AE
  let jb = j B
  let jg = j G
  let jbe = j BE
  let ja = j A
  let jne = j NE
  let jp = j P


  let ret () = emit RET
  let hlt () = emit HLT
  let nop () = emit NOP

  (* Word mnemonics *)
  let movw (arg1, arg2) = emit (MOV (word arg1, word arg2))

  (* Byte mnemonics *)
  let decb arg = emit (DEC (byte arg))
  let cmpb (x, y) = emit (CMP (byte x, byte y))
  let movb (x, y) = emit (MOV (byte x, byte y))
  let andb (x, y)= emit (AND (byte x, byte y))
  let xorb (x, y)= emit (XOR (byte x, byte y))
  let testb (x, y)= emit (TEST (byte x, byte y))

  (* Long-word mnemonics *)
  let movl (x, y) = emit (MOV (dword x, dword y))
end

module INS32 = struct

  open Check
  include INS

  (* Long-word mnemonics *)
  let addl (x, y) = emit (ADD (dword x, dword y))
  let subl (x, y) = emit (SUB (dword x, dword y))
  let andl (x, y) = emit (AND (dword x, dword y))
  let orl (x, y) = emit (OR (dword x, dword y))
  let xorl (x, y) = emit (XOR (dword x, dword y))
  let cmpl (x, y) = emit (CMP (dword x, dword y))
  let testl (x, y) = emit (TEST (dword x, dword y))

  let movzbl (x, y) = emit (MOVZX (byte x, dword y))
  let movsbl (x, y) = emit (MOVSX (byte x, dword y))
  let movzwl (x, y) = emit (MOVZX (word x, dword y))
  let movswl (x, y) = emit (MOVSX (word x, dword y))

  let sall (arg1, arg2) = emit (SAL  (arg1, dword arg2))
  let sarl (arg1, arg2) = emit (SAR  (arg1, dword arg2))
  let shrl (arg1, arg2) = emit (SHR  (arg1, dword arg2))
  let imull (arg1, arg2) = emit (IMUL (dword arg1, option dword arg2))

  let idivl arg = emit (IDIV (dword arg))
  let popl arg = emit (POP (dword arg))
  let pushl arg = emit (PUSH (dword arg))
  let decl arg = emit (DEC (dword arg))
  let incl arg = emit (INC (dword arg))
  let leal (arg1, arg2) = emit (LEA (arg1, dword arg2))

  let fistpl arg = emit (FISTP (dword arg))
  let fildl arg = emit (FILD (dword arg))

  let fchs () = emit FCHS
  let fabs () = emit FABS

  let fadd x = emit (FADD x)
  let fsub x = emit (FSUB x)
  let fdiv x = emit (FDIV x)
  let fmul x = emit (FMUL x)
  let fsubr x = emit (FSUBR x)
  let fdivr x = emit (FDIVR x)

  let faddp (arg1, arg2) = emit (FADDP (arg1, arg2))
  let fmulp (arg1, arg2) = emit (FMULP (arg1, arg2))
  let fcompp () = emit FCOMPP
  let fcomp arg = emit (FCOMP arg)
  let fld arg = emit (FLD arg)
  let fnstsw arg = emit (FNSTSW arg)
  let fld1 () = emit FLD1
  let fpatan () = emit FPATAN
  let fptan () = emit FPTAN
  let fcos () = emit FCOS
  let fldln2 () = emit FLDLN2
  let fldlg2 () = emit FLDLG2
  let fxch arg = emit (FXCH arg)
  let fyl2x () = emit FYL2X
  let fsin () = emit FSIN
  let fsqrt () = emit FSQRT
  let fstp arg = emit (FSTP arg)
  let fldz () = emit FLDZ
  let fnstcw arg = emit (FNSTCW arg)
  let fldcw arg = emit (FLDCW arg)
  let cltd () = emit CDQ

  let fsubp (arg1, arg2) = emit (FSUBP (arg1, arg2))
  let fsubrp (arg1, arg2) = emit (FSUBRP (arg1, arg2))
  let fdivp (arg1, arg2) = emit (FDIVP (arg1, arg2))
  let fdivrp (arg1, arg2) = emit (FDIVRP (arg1, arg2))
end

module DSL32 = struct

  include DSL

  let _label s = directive (NewLabel (s, DWORD))

  let eax = Reg32 EAX
  let ebx = Reg32 EBX
  let ecx = Reg32 ECX
  let edx = Reg32 EDX
  let ebp = Reg32 EBP
  let esp = Reg32 ESP

  let st0 = Regf (ST 0)
  let st1 = Regf (ST 1)

  let mem_ptr typ ?(scale = 1) ?base ?sym offset idx =
    assert(scale > 0);
    Mem32 {typ; idx; scale; base; sym; displ=Int64.of_int offset}

  let mem_sym typ ?(ofs = 0) l =
    Mem32 {typ; idx=EAX; scale=0; base=None;
           sym=Some l; displ=Int64.of_int ofs}
end


module INS64 = struct

  open Check
  include INS

  let addq (x, y) = emit (ADD (qword x, qword y))
  let subq (x, y) = emit (SUB (qword x, qword y))
  let andq (x, y) = emit (AND (qword x, qword y))
  let orq (x, y) = emit (OR (qword x, qword y))
  let xorq (x, y) = emit (XOR (qword x, qword y))
  let cmpq (x, y) = emit (CMP (qword x, qword y))
  let testq (x, y) = emit (TEST (qword x, qword y))

  let movq (x, y) = emit (MOV (qword x, qword y))

  let movzbq (x, y) = emit (MOVZX (byte x, qword y))
  let movsbq (x, y) = emit (MOVSX (byte x, qword y))
  let movzwq (x, y) = emit (MOVZX (word x, qword y))
  let movswq (x, y) = emit (MOVSX (word x, qword y))

  let idivq arg = emit (IDIV (qword arg))

  let salq (arg1, arg2) = emit (SAL (arg1, qword arg2))
  let sarq (arg1, arg2) = emit (SAR (arg1, qword arg2))
  let shrq (arg1, arg2) = emit (SHR (arg1, qword arg2))
  let imulq (arg1, arg2) = emit (IMUL (qword arg1, option qword arg2))

  let popq arg = emit (POP (qword arg))
  let pushq arg = emit (PUSH (qword arg))
  let leaq (arg1, arg2) = emit (LEA (arg1, qword arg2))

  let movsd (arg1, arg2) = emit (MOVSD (arg1, arg2))
  let ucomisd (arg1, arg2) = emit (UCOMISD (arg1, arg2))
  let comisd (arg1, arg2) = emit (COMISD (arg1, arg2))
  let movapd (arg1, arg2) = emit (MOVAPD (arg1, arg2))
  let movabsq (arg1, arg2) = emit (MOV (Imm arg1, qword arg2))
  let xorpd (arg1, arg2) = emit (XORPD (arg1, arg2))
  let andpd (arg1, arg2) = emit (ANDPD (arg1, arg2))

  let movslq (arg1, arg2) = emit (MOVSXD  (arg1, arg2))
  let movss (arg1, arg2) = emit (MOVSS (arg1, arg2))
  let cvtss2sd (arg1, arg2) = emit (CVTSS2SD (arg1, arg2))
  let cvtsd2ss (arg1, arg2) = emit (CVTSD2SS (arg1, arg2))
  let cvtsi2sd (arg1, arg2) = emit (CVTSI2SD (arg1, arg2))
  let cvttsd2si (arg1, arg2) = emit (CVTTSD2SI (arg1, arg2))
  let addsd (arg1, arg2) = emit (ADDSD (arg1, arg2))
  let subsd  (arg1, arg2) = emit (SUBSD (arg1, arg2))
  let mulsd (arg1, arg2) = emit (MULSD (arg1, arg2))
  let divsd (arg1, arg2) = emit (DIVSD (arg1, arg2))
  let sqrtsd (arg1, arg2) = emit (SQRTSD (arg1, arg2))

  let cqto () = emit CQTO

  let incq arg = emit (INC (qword arg))
  let decq arg = emit (DEC (qword arg))
  let xchg (arg1, arg2) = emit (XCHG (arg1, arg2))
  let bswap arg = emit (BSWAP arg)
end

module DSL64 = struct
  include DSL

  let _label s = directive (NewLabel (s, QWORD))

  let al  = Reg8 AL
  let ah  = Reg8 AH
  let cl  = Reg8 CL
  let rax = Reg64 RAX
  let r10 = Reg64 R10
  let r11 = Reg64 R11
  let r14 = Reg64 R14
  let r15 = Reg64 R15
  let rsp = Reg64 RSP
  let rbp = Reg64 RBP
  let xmm15 = Regf (XMM 15)

  let mem_ptr typ ?(scale = 1) ?base offset idx =
    assert(scale > 0);
    Mem64 {typ; idx; scale; base; sym=None; displ=Int64.of_int offset}

  let from_rip typ ?(ofs = 0) s =
    Mem64 {typ; idx=RIP; scale=1; base=None; sym=Some s; displ=Int64.of_int ofs}
end