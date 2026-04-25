package wot

import "core:fmt"
import os "core:os/os2"

// OpCode is the minimal instruction set for declarations, assignments, and arithmetic.
OpCode :: enum u8 {
    Halt,
    Return,
    Const,
    LoadLocal,
    StoreLocal,
    LoadGlobal,
    StoreGlobal,
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    CmpEq,
    NotEq,
    Lt,
    Gt,
    LtEq,
    GtEq,
    Jump,
    JumpIfFalse,
    Call,
    Neg,
    Not,
    And,
    Or,
}

// Instruction is a fixed-width 32-bit instruction with named fields.
Instruction :: struct #packed {
    opcode: OpCode,
    a, b, c: u8
}

// Chunk stores emitted instructions and constant/global symbol tables.
Chunk :: struct {
    code:       [dynamic]Instruction,
    constants:  [dynamic]Value,
    locals:     [dynamic]SymbolId,
    local_idx:  map[SymbolId]u32,
    symbols:    [dynamic]SymbolId,
    symbol_idx: map[SymbolId]u32,
}

FunctionIR :: struct {
    name:        SymbolId,
    params:      []ParamInfo,
    return_type: string,
    body:        Chunk,
}

ProgramIR :: struct {
    entry:        Chunk,
    functions:    [dynamic]FunctionIR,
    function_idx: map[SymbolId]u32,
}

// make_instruction_abc builds an instruction using 3 byte operands.
make_instruction_abc :: #force_inline proc(op: OpCode, a, b, c: u8) -> Instruction {
    return Instruction {
        opcode = op,
        a = a,
        b = b,
        c = c,
    }
}

// make_instruction_abx builds an instruction using one 16-bit operand in b/c.
make_instruction_abx :: #force_inline proc(op: OpCode, a: u8, bx: u16) -> Instruction {
    return Instruction {
        opcode = op,
        a = a,
        b = u8(bx & 0x00ff),
        c = u8((bx >> 8) & 0x00ff),
    }
}

// bx_of decodes the 16-bit operand from instruction fields b/c.
bx_of :: #force_inline proc(ins: Instruction) -> u16 {
    return u16(ins.b) | (u16(ins.c) << 8)
}

// sbx_of decodes a signed 16-bit operand from instruction fields b/c.
sbx_of :: #force_inline proc(ins: Instruction) -> i16 {
    return i16(bx_of(ins))
}

// emit appends one instruction into the chunk.
emit :: proc(chunk: ^Chunk, ins: Instruction, line: u32 = 0) -> u32 {
    _ = line
    append(&chunk.code, ins)
    return u32(len(chunk.code) - 1)
}

// emit_abc emits an instruction that uses A/B/C operands.
emit_abc :: proc(chunk: ^Chunk, op: OpCode, a, b, c: u8, line: u32 = 0) -> u32 {
    return emit(chunk, make_instruction_abc(op, a, b, c), line)
}

// emit_abx emits an instruction that uses A/Bx operands.
emit_abx :: proc(chunk: ^Chunk, op: OpCode, a: u8, bx: u16, line: u32 = 0) -> u32 {
    return emit(chunk, make_instruction_abx(op, a, bx), line)
}

// emit_asbx emits an instruction that uses A/sBx operands.
emit_asbx :: proc(chunk: ^Chunk, op: OpCode, a: u8, sbx: i16, line: u32 = 0) -> u32 {
    return emit_abx(chunk, op, a, u16(sbx), line)
}

// emit_jump_placeholder emits a jump with a placeholder offset.
emit_jump_placeholder :: proc(chunk: ^Chunk, op: OpCode, line: u32 = 0) -> u32 {
    return emit_asbx(chunk, op, 0, 0, line)
}

// patch_jump_to_current patches a placeholder jump to target the current end of code.
patch_jump_to_current :: proc(chunk: ^Chunk, jump_ip: u32) {
    target_ip := i32(len(chunk.code))
    offset := target_ip - i32(jump_ip) - 1
    if offset < -32768 || offset > 32767 do panic("Jump offset out of i16 range")
    chunk.code[int(jump_ip)].b = u8(u16(i16(offset)) & 0x00ff)
    chunk.code[int(jump_ip)].c = u8((u16(i16(offset)) >> 8) & 0x00ff)
}

// add_constant inserts a literal into the constant pool and returns its index.
add_constant :: proc(chunk: ^Chunk, value: Value) -> u16 {
    if len(chunk.constants) >= 65536 do panic("Too many constants for ABx operand")
    append(&chunk.constants, value)
    return u16(len(chunk.constants) - 1)
}

// add_symbol inserts or reuses a global symbol slot and returns its index.
add_symbol :: proc(chunk: ^Chunk, sym: SymbolId) -> u16 {
    if chunk.symbol_idx == nil {
        chunk.symbol_idx = make_map(map[SymbolId]u32)
    }

    existing, found := chunk.symbol_idx[sym]
    if found {
        if existing > 65535 do panic("Symbol index out of range")
        return u16(existing)
    }

    if len(chunk.symbols) >= 65536 do panic("Too many symbols for ABx operand")
    idx := u32(len(chunk.symbols))
    append(&chunk.symbols, sym)
    chunk.symbol_idx[sym] = idx
    return u16(idx)
}

// add_local inserts or reuses a local symbol slot and returns its index.
add_local :: proc(chunk: ^Chunk, sym: SymbolId) -> u16 {
    if chunk.local_idx == nil {
        chunk.local_idx = make_map(map[SymbolId]u32)
    }

    existing, found := chunk.local_idx[sym]
    if found {
        if existing > 65535 do panic("Local symbol index out of range")
        return u16(existing)
    }

    if len(chunk.locals) >= 65536 do panic("Too many local symbols for ABx operand")
    idx := u32(len(chunk.locals))
    append(&chunk.locals, sym)
    chunk.local_idx[sym] = idx
    return u16(idx)
}

// emit_binary_op emits bytecode for supported arithmetic and comparison binary operators.
emit_binary_op :: proc(chunk: ^Chunk, op: BinaryOp, line: u32) {
    #partial switch op {
        case .Add: emit_abc(chunk, .Add, 0, 0, 0, line)
        case .Sub: emit_abc(chunk, .Sub, 0, 0, 0, line)
        case .Mul: emit_abc(chunk, .Mul, 0, 0, 0, line)
        case .Div: emit_abc(chunk, .Div, 0, 0, 0, line)
        case .Mod: emit_abc(chunk, .Mod, 0, 0, 0, line)
        case .CmpEq: emit_abc(chunk, .CmpEq, 0, 0, 0, line)
        case .NotEq: emit_abc(chunk, .NotEq, 0, 0, 0, line)
        case .Lt: emit_abc(chunk, .Lt, 0, 0, 0, line)
        case .Gt: emit_abc(chunk, .Gt, 0, 0, 0, line)
        case .Lt_Eq: emit_abc(chunk, .LtEq, 0, 0, 0, line)
        case .Gt_Eq: emit_abc(chunk, .GtEq, 0, 0, 0, line)
        case .And: emit_abc(chunk, .And, 0, 0, 0, line)
        case .Or: emit_abc(chunk, .Or, 0, 0, 0, line)
        case:
            fmt.eprintln("Invalid binary op:", op)
            os.exit(1)
    }
}

emit_unary_op :: proc(chunk: ^Chunk, op: UnaryOp, line: u32) {
    #partial switch op {
        case .Sub: emit_abc(chunk, .Neg, 0, 0, 0, line)
        case .Not: emit_abc(chunk, .Not, 0, 0, 0, line)
        case:
            panic("Unsupported binary operator in IR")
    }
}

// compile_expr emits IR for literals, identifiers, and arithmetic expressions.
compile_expr :: proc(chunk: ^Chunk, expr: Expr, locals: ^map[SymbolId]u32 = nil) {
    #partial switch value in expr.variant {
        case Int:
            idx := add_constant(chunk, Int(value))
            emit_abx(chunk, .Const, 0, idx, expr.pos.line)
        case Float:
            idx := add_constant(chunk, Float(value))
            emit_abx(chunk, .Const, 0, idx, expr.pos.line)
        case Bool:
            idx := add_constant(chunk, Bool(value))
            emit_abx(chunk, .Const, 0, idx, expr.pos.line)
        case Char:
            idx := add_constant(chunk, Char(value))
            emit_abx(chunk, .Const, 0, idx, expr.pos.line)
        case Identifier:
            if locals != nil {
                local_slot, is_local := locals[expr.id]
                if is_local {
                    emit_abx(chunk, .LoadLocal, 0, u16(local_slot), expr.pos.line)
                    break
                }
            }
            slot := add_symbol(chunk, expr.id)
            emit_abx(chunk, .LoadGlobal, 0, slot, expr.pos.line)
        case ^BinaryExpr:
            compile_expr(chunk, value.left, locals)
            compile_expr(chunk, value.right, locals)
            emit_binary_op(chunk, value.op, expr.pos.line)
        case ^CallExpr:
            for arg in value.args {
                compile_expr(chunk, arg, locals)
            }

            callee_slot := add_symbol(chunk, value.callee.id)
            emit_abx(chunk, .Call, u8(len(value.args)), callee_slot, expr.pos.line)
        case ^UnaryExpr:
            compile_expr(chunk, value.expr, locals)
            emit_unary_op(chunk, value.op, expr.pos.line)
        case:
            panic("Only literals, identifiers, and binary expressions are supported")
    }
}

// compile_assignment emits IR for plain and arithmetic compound assignments.
compile_assignment :: proc(chunk: ^Chunk, stmt: AssignStmt, locals: ^map[SymbolId]u32 = nil) {
    slot: u16
    is_local := false
    if locals != nil {
        local_slot, found := locals[stmt.id.sym]
        if found {
            slot = u16(local_slot)
            is_local = true
        }
    }

    if !is_local {
        slot = add_symbol(chunk, stmt.id.sym)
    }

    #partial switch stmt.op {
        case .Assign:
            compile_expr(chunk, stmt.value, locals)
        case .AddEq:
            if is_local {
                emit_abx(chunk, .LoadLocal, 0, slot, stmt.id.pos.line)
            } else {
                emit_abx(chunk, .LoadGlobal, 0, slot, stmt.id.pos.line)
            }
            compile_expr(chunk, stmt.value, locals)
            emit_abc(chunk, .Add, 0, 0, 0, stmt.id.pos.line)
        case .SubEq:
            if is_local {
                emit_abx(chunk, .LoadLocal, 0, slot, stmt.id.pos.line)
            } else {
                emit_abx(chunk, .LoadGlobal, 0, slot, stmt.id.pos.line)
            }
            compile_expr(chunk, stmt.value, locals)
            emit_abc(chunk, .Sub, 0, 0, 0, stmt.id.pos.line)
        case .MulEq:
            if is_local {
                emit_abx(chunk, .LoadLocal, 0, slot, stmt.id.pos.line)
            } else {
                emit_abx(chunk, .LoadGlobal, 0, slot, stmt.id.pos.line)
            }
            compile_expr(chunk, stmt.value, locals)
            emit_abc(chunk, .Mul, 0, 0, 0, stmt.id.pos.line)
        case .DivEq:
            if is_local {
                emit_abx(chunk, .LoadLocal, 0, slot, stmt.id.pos.line)
            } else {
                emit_abx(chunk, .LoadGlobal, 0, slot, stmt.id.pos.line)
            }
            compile_expr(chunk, stmt.value, locals)
            emit_abc(chunk, .Div, 0, 0, 0, stmt.id.pos.line)
        case .ModEq:
            if is_local {
                emit_abx(chunk, .LoadLocal, 0, slot, stmt.id.pos.line)
            } else {
                emit_abx(chunk, .LoadGlobal, 0, slot, stmt.id.pos.line)
            }
            compile_expr(chunk, stmt.value, locals)
            emit_abc(chunk, .Mod, 0, 0, 0, stmt.id.pos.line)
        case:
            panic("Unsupported assignment operator")
    }

    if is_local {
        emit_abx(chunk, .StoreLocal, 0, slot, stmt.id.pos.line)
    } else {
        emit_abx(chunk, .StoreGlobal, 0, slot, stmt.id.pos.line)
    }
}

// compile_if emits IR for if/else using a conditional jump and optional end jump.
compile_if :: proc(chunk: ^Chunk, stmt: IfStmt, in_function: bool = false, locals: ^map[SymbolId]u32 = nil) {
    compile_expr(chunk, stmt.condition, locals)
    false_jump := emit_jump_placeholder(chunk, .JumpIfFalse, stmt.pos.line)

    compile_block(chunk, stmt.main_body, in_function, locals)

    if len(stmt.else_body) > 0 {
        end_jump := emit_jump_placeholder(chunk, .Jump, stmt.pos.line)
        patch_jump_to_current(chunk, false_jump)
        compile_block(chunk, stmt.else_body, in_function, locals)
        patch_jump_to_current(chunk, end_jump)
    } else {
        patch_jump_to_current(chunk, false_jump)
    }
}

compile_call :: proc(chunk: ^Chunk, stmt: CallStmt, locals: ^map[SymbolId]u32 = nil) {

    if len(stmt.args) > 255 do panic("Too many call arguments for ABC operand")

    for arg in stmt.args {
        compile_expr(chunk, arg, locals)
    }

    callee_slot := add_symbol(chunk, stmt.id.sym)
    emit_abx(chunk, .Call, u8(len(stmt.args)), callee_slot, stmt.id.pos.line)
}

compile_while :: proc(chunk: ^Chunk, stmt: WhileStmt, in_function: bool = false, locals: ^map[SymbolId]u32 = nil) {
    loop_start := u32(len(chunk.code))
    compile_expr(chunk, stmt.condition, locals)
    false_jump := emit_jump_placeholder(chunk, .JumpIfFalse, stmt.pos.line)

    compile_block(chunk, stmt.body, in_function, locals)

    // Jump back to loop_start to re-evaluate condition
    back_jump_offset := i16(loop_start) - i16(len(chunk.code)) - 1
    emit_asbx(chunk, .Jump, 0, back_jump_offset, stmt.pos.line)
    
    // Patch false_jump to exit loop
    patch_jump_to_current(chunk, false_jump)
}

// compile_block emits IR for all statements in a block.
compile_block :: proc(chunk: ^Chunk, block: BlockStmt, in_function: bool = false, locals: ^map[SymbolId]u32 = nil) {
    for child in block {
        compile_stmt(chunk, child, in_function, locals)
    }
}

// compile_stmt emits IR for declaration and assignment statements only.
compile_stmt :: proc(chunk: ^Chunk, stmt: Stmt, in_function: bool = false, locals: ^map[SymbolId]u32 = nil) {
    #partial switch s in stmt {
        case DeclrStmt:
            #partial switch decl in s.variant {
                case VarDeclrStmt:
                    compile_expr(chunk, decl.value, locals)
                    if locals != nil {
                        slot := add_local(chunk, s.id.sym)
                        locals[s.id.sym] = u32(slot)
                        emit_abx(chunk, .StoreLocal, 0, slot, s.id.pos.line)
                    } else {
                        slot := add_symbol(chunk, s.id.sym)
                        emit_abx(chunk, .StoreGlobal, 0, slot, s.id.pos.line)
                    }
                case FnDeclrStmt:
                    panic("Nested function declarations are not supported in IR yet")
            }
        case ReturnStmt:
            if !in_function do panic("Return outside function is not supported in IR")
            compile_expr(chunk, Expr(s), locals)
            emit_abc(chunk, .Return, 0, 0, 0)
        case BlockStmt:
            compile_block(chunk, s, in_function, locals)
        case IfStmt:
            compile_if(chunk, s, in_function, locals)

        case WhileStmt:
            compile_while(chunk, s, in_function, locals)

        case AssignStmt:
            compile_assignment(chunk, s, locals)
        case CallStmt:
            compile_call(chunk, s, locals)
    }
}

compile_function_decl :: proc(ir: ^ProgramIR, id: Token, decl: FnDeclrStmt) {
    if ir.function_idx == nil {
        ir.function_idx = make_map(map[SymbolId]u32)
    }

    _, exists := ir.function_idx[id.sym]
    if exists do panic("Duplicate function declaration in IR")

    fn_ir := FunctionIR {
        name = id.sym,
        params = decl.params,
        return_type = decl.return_type,
    }

    fn_locals := make_map(map[SymbolId]u32)
    defer delete(fn_locals)

    for param in decl.params {
        slot := add_local(&fn_ir.body, param.id.sym)
        fn_locals[param.id.sym] = u32(slot)
    }

    compile_block(&fn_ir.body, decl.body, true, &fn_locals)
    emit_abc(&fn_ir.body, .Return, 0, 0, 0)

    append(&ir.functions, fn_ir)
    ir.function_idx[id.sym] = u32(len(ir.functions) - 1)
}

// generate_program_ir compiles a block into minimal declaration/assignment IR.
generate_program_ir :: proc(program: BlockStmt) -> ProgramIR {
    ir: ProgramIR

    for stmt in program {
        if decl_stmt, is_decl := stmt.(DeclrStmt); is_decl {
            if fn_decl, is_fn := decl_stmt.variant.(FnDeclrStmt); is_fn {
                compile_function_decl(&ir, decl_stmt.id, fn_decl)
            }
        }
    }

    for stmt in program {
        if decl_stmt, is_decl := stmt.(DeclrStmt); is_decl {
            if _, is_fn := decl_stmt.variant.(FnDeclrStmt); is_fn {
                continue
            }
        }
        compile_stmt(&ir.entry, stmt)
    }
    emit_abc(&ir.entry, .Halt, 0, 0, 0)

    return ProgramIR {
        entry = ir.entry,
        functions = ir.functions,
        function_idx = ir.function_idx,
    }
}
