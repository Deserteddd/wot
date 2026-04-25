package wot

import "core:fmt"
import os "core:os/os2"
import "core:reflect"
import "core:strings"
import "core:unicode/utf8"

funcs: map[SymbolId]Func

Func :: distinct FnDeclrStmt

Var :: struct {
    type: Type,
    value: Value,
    const: bool
}

Type :: enum {
    None,
    Float,
    Int,
    Bool,
}

Value :: union {
    None,
    Float,
    Int,
    Char,
    Bool
}

Scope_Kind :: enum {
    Global,
    Function,
    Block,
}

Scope :: struct {
    symbols: map[SymbolId]Var,
    parent: ^Scope,
    kind: Scope_Kind,
}

scope_push :: proc(parent: ^Scope, kind: Scope_Kind) -> Scope {
    if kind == .Global && parent != nil {
        panic("Global scope cannot have a parent")
    }
    if kind != .Global && parent == nil {
        panic("Non-global scope requires a parent")
    }

    return Scope {
        symbols = make_map(map[SymbolId]Var),
        parent = parent,
        kind = kind,
    }
}

scope_pop :: proc(scope: ^Scope) {
    if scope == nil do return
    if scope.symbols != nil {
        delete(scope.symbols)
    }
    scope.parent = nil
}


scope_fetch :: proc(scope: ^Scope, id: SymbolId) -> ^Var {
    if scope == nil do return nil

    s := scope
    // 1) Walk local scope chain up to the nearest function boundary.
    for s != nil {
        var, found := &s.symbols[id]
        if found do return var
        if s.kind == .Function do break
        s = s.parent
    }

    // 2) Continue upward, but only allow globals.
    for s != nil {
        if s.kind == .Global {
            var, found := &s.symbols[id]
            if found && var.const do return var
        }
        s = s.parent
    }

    return nil
}

scope_add :: proc(scope: ^Scope, id: SymbolId, v: Var) -> (overwrote: bool) {
    val, found := &scope.symbols[id]
    overwrote = found
    if overwrote do val^ = v
    else do scope.symbols[id] = v

    return
}


format_value :: proc(v: Value) -> string {
    #partial switch value in v {
        case Int, Float:
                return fmt.tprint(value)
        case Char:
                return fmt.tprint(rune(value))
        case Bool:
                return fmt.tprintf("%t", value)
    }
    panic("What")
}

print_values :: proc(args: []Value, newline: bool) {
    for value, i in args {
        if i > 0 {
            fmt.print(" ")
        }
        fmt.print(format_value(value))
    }

    if newline {
        fmt.println()
    }
}

value_type :: proc(v: Value, loc := #caller_location) -> Type {
    #partial switch v in v {
        case Int:       return .Int
        case Float:       return .Float
        case Bool:      return .Bool
        case None:      return .None
    }
    panic("Undeclared type", loc)
}

binary_op_from_assign_op :: proc(aop: AssignOp) -> (op: BinaryOp, ok: bool) {
    ok = true
    #partial switch aop {
        case .AddEq: op = .Add
        case .SubEq: op = .Sub
        case .MulEq: op = .Mul
        case .DivEq: op = .Div
        case .ModEq: op = .Mod
        case:
            ok = false
    }
    return
}

runtime_error :: proc(pos: Pos, msg: string, args: ..any, loc := #caller_location) {
    if ODIN_DEBUG {
        fmt.eprintf("%v ", loc)
    }
	fmt.eprintf("Runtime error: %s(%d:%d) ", pos.file, pos.line, pos.column)
	fmt.eprintf(msg, ..args)
	fmt.eprintf("\n")
    os.exit(1)
}

eval :: proc(e: Expr, scope: ^Scope, loc := #caller_location) -> Value {
    result: Value
    switch v in e.variant {
        case Int:
            result = Int(v)
        case Float:
            result = Float(v)
        case Bool:
            result = Bool(v)
        case Char:
            result = Char(v)
        case Identifier:
            variable := scope_fetch(scope, e.id)
            if variable == nil do runtime_error(
                e.pos, 
                "Undeclared identifier %w", 
                symbol_name(e.id),
                loc = loc
            )
            result = variable.value
        case ^BinaryExpr:
            val, ok := apply_op(
                v.op, 
                eval(v.left, scope, loc = loc), 
                eval(v.right, scope, loc = loc)
            )
            if !ok do runtime_error(e.pos, "Invalid operands for binary operation")
            result = val
        case ^UnaryExpr:
            val, ok := apply_unary_op(v.op, eval(v.expr, scope))
            if !ok do runtime_error(
                e.pos, 
                "Invalid operand for unary opertaion %w", 
                to_string_unary_op(v.op)
            )
            result = val
        case ^CallExpr:
            #partial switch callee in v.callee.variant {
                case Identifier:
                    id_token := Token {
                        kind = .Id,
                        text = string(callee),
                        sym  = v.callee.id,
                        pos = v.callee.pos,
                    }
                    result = execute_call(id_token, v.args, scope)
                case:
                    runtime_error(v.callee.pos, "Invalid call")
            }
        case None:
            return v
        case:
            runtime_error(e.pos, "Invalid expression")
    }
    return result
}

execute_call :: proc(id: Token, args: []Expr, scope: ^Scope) -> Value {
    switch id.text {
        case "print":
            args_evaled := make([]Value, len(args), context.temp_allocator)
            for arg, i in args {
                args_evaled[i] = eval(arg, scope)
            }
            print_values(args_evaled, false)
            return {}

        case "println":
            args_evaled := make([]Value, len(args), context.temp_allocator)
            for arg, i in args {
                args_evaled[i] = eval(arg, scope)
            }
            print_values(args_evaled, true)
            return {}

        case:
            // fmt.printfln("seaching function %v, from %v", id.text, funcs)
            func, func_found := funcs[id.sym]
            if !func_found do runtime_error(
                id.pos,
                "Undeclared function: %v",
                id.text
            )

            fn_scope := scope_push(scope, .Function)
            defer scope_pop(&fn_scope)


            if len(func.params) != len(args) {
                args_pos := id.pos
                args_pos.column += utf8.rune_count(id.text)
                runtime_error(
                    args_pos,
                    "Expected %v arguments, got %v",
                    len(func.params), len(args)
                )
            }

            for arg, i in args {
                param := func.params[i]
                rhs := eval(arg, scope)
                val_type := value_type(rhs)
                if val_type != type_from_string(param.type) do runtime_error(
                    arg.pos,
                    "Invalid argument of type %v, expected %v",
                    val_type, param.type
                )

                scope_add(&fn_scope, param.id.sym, Var { value_type(rhs), rhs, true})
            }

            return_val := run_block(func.body, &fn_scope, .Block)
            expected_type := type_from_string(func.return_type)
            actual_type := value_type(return_val)

            if !is_legal_cast(actual_type, expected_type) {
                runtime_error(
                    id.pos,
                    "Invalid return type: %v, expected %v",
                    value_type(return_val), type_from_string(func.return_type)
                )
            }
            return return_val
    }
}

is_legal_cast :: #force_inline proc(from: Type, to: Type) -> (legal: bool) {
    if from == to do return true
    #partial switch from {
        case .Int:
            #partial switch to {
                case .Float, .Bool: legal = true
            }
    }
    return
}

apply_unary_op :: #force_inline proc(op: UnaryOp, v: Value) -> (val: Value, ok: bool) {
    ok = true
    switch op {
        case .Not:
            bool_val, bool_val_ok := v.(Bool);
            if !bool_val_ok {
                ok = false
            } else {
                val = !bool_val
            }
        case .Sub:
            #partial switch value in v {
                case Float:
                    val = -value
                case Int:
                    val = -value
                case:
                    ok = false
            }
        case .Invalid:
            panic("Invalid unary operator")

    }
    return
}

apply_int_op :: proc(op: BinaryOp, a, b: Int) -> (val: Value, ok: bool) {
    ok = true
    #partial switch op {
        case .Add: val = a + b
        case .Sub: val = a - b
        case .Mul: val = a * b
        case .Div: val = a / b
        case .Mod: val = a % b
        case .Lt:  val = a < b
        case .Gt:  val = a > b
        case .Lt_Eq: val = a <= b
        case .Gt_Eq: val = a >= b
        case .CmpEq: val = a == b
        case .NotEq: val = a != b
        case:
            fmt.eprintfln("%v operation not supported for int type", op)
            ok = false
    }
    return
}

apply_float_op :: proc(op: BinaryOp, a, b: Float) -> (val: Value, ok: bool) {
    ok = true
    #partial switch op {
        case .Add: val = a + b
        case .Sub: val = a - b
        case .Mul: val = a * b
        case .Div: val = a / b
        case .Lt:  val = a < b
        case .Gt:  val = a > b
        case .Lt_Eq: val = a <= b
        case .Gt_Eq: val = a >= b
        case .CmpEq: val = a == b
        case .NotEq: val = a != b
        case:
            fmt.eprintfln("%v operation not supported for float type", op)
            ok = false
    }
    return
}

apply_bool_op :: proc(op: BinaryOp, a, b: Bool) -> (val: Value, ok: bool) {
    ok = true
    #partial switch op {
        case .And:      val = a && b
        case .Or:       val = a || b
        case .CmpEq:    val = a == b
        case .NotEq:    val = a != b
        case: 
            fmt.eprintfln("%v operation not supported for bool type", op)
            ok = false
    }
    return
}

apply_op :: #force_inline proc(op: BinaryOp, v1, v2: Value) -> (val: Value, ok: bool) {
    #partial switch &left in v1 {
        case Int:
            right, right_ok := v2.(Int)
            if right_ok do return apply_int_op(op, left, right)
            else {
                right_float, right_float_ok := v2.(Float)
                if !right_float_ok do return
                return apply_float_op(op, Float(left), right_float)
            }

        case Float:
            right, right_ok := v2.(Float)
            if right_ok do return apply_float_op(op, left, right)
            else {
                right_int, right_int_ok := v2.(Int)
                if !right_int_ok do return
                return apply_float_op(op, left, Float(right_int))
            }

        case Bool:
            right, right_ok := v2.(Bool)
            if !right_ok do return
            return apply_bool_op(op, left, right)
    }

    return
}

run_block :: proc(block: BlockStmt, scope: ^Scope, block_type: Scope_Kind) -> Value {
    frame := scope_push(scope, block_type)
    defer scope_pop(&frame)

    return_value: Value

    for stmt in block {
        #partial switch &s in stmt {
            case DeclrStmt:
                switch declr_stmt in s.variant {
                    case VarDeclrStmt:
                        rhs := eval(declr_stmt.value, &frame)
                        declared_type := type_from_string(declr_stmt.type)
                        value_type    := value_type(rhs)
                        type := declared_type
                        if declared_type == .None {
                            type = value_type
                        } else if !is_legal_cast(value_type, declared_type) {
                            runtime_error(
                                declr_stmt.value.pos,
                                "Cannot assign value of type \"%v\" to %v: %v",
                                declared_type, s.id.text, value_type
                            )
                        }
                        var := Var{type, rhs, declr_stmt.const}
                        scope_add(&frame, s.id.sym, var)
                    case FnDeclrStmt:
                        if block_type != .Global do runtime_error(
                            s.id.pos,
                            "Nested functions aren't supported (yet)"
                        )
                }
            case ReturnStmt:
                return eval(Expr(s), &frame)
            case AssignStmt:
                assignee := scope_fetch(&frame, s.id.sym)
                if assignee == nil do runtime_error(
                    s.id.pos,
                    "Undeclared variable: %v",
                    s.id.text
                )
                if assignee.const do runtime_error(
                    s.id.pos,
                    "Cannot assign to constant %w",
                    s.id.text
                )
                rhs := eval(s.value, &frame)
                if s.op == .Assign {
                    if !is_legal_cast(value_type(rhs), assignee.type) do runtime_error(
                        s.id.pos,
                        "Cannot assign value of type %v to %v: %v",
                        value_type(rhs), s.id.text, assignee.type
                    )
                } else {
                    op, ok := binary_op_from_assign_op(s.op)
                    if !ok do runtime_error(
                        s.id.pos,
                        "Invalid compound assignment operator %w",
                        s.id.text
                    )
                    
                    rhs, ok = apply_op(op, assignee.value, rhs)
                    if !ok do runtime_error(
                        s.id.pos,
                        "Cannot assign value of type %v to %v: %v",
                        value_type(rhs), s.id.text, assignee.type
                        
                    )
                }

                assignee.type = value_type(rhs)
                assignee.value = rhs
            case CallStmt:
                return_value = execute_call(s.id, s.args, &frame)
            case IfStmt:
                cond := eval(s.condition, &frame)
                if bool_val, bool_val_ok := cond.(Bool); bool_val_ok {
                    if bool_val {
                        return_value = run_block(s.main_body, &frame, .Block)
                    } else {
                        return_value = run_block(s.else_body, &frame, .Block)
                    }
                } else do runtime_error(s.condition.pos, "If-condition must evaluate to bool")
            case WhileStmt:
                cond := eval(s.condition, &frame)
                if bool_val, bool_val_ok := cond.(Bool); bool_val_ok {
                    for bool_val {
                        run_block(s.body, &frame, .Block)
                        bool_val = eval(s.condition, &frame).(Bool)
                    }
                } else do runtime_error(s.condition.pos, "While-condition must evaluate to bool")
            case BlockStmt:
                run_block(s, &frame, .Block)
        }
    }
    return return_value
}

run_ast :: proc(program: BlockStmt) -> Value {
    for stmt in program {
        if declr, declr_ok := stmt.(DeclrStmt); declr_ok {
            if fn_declr, fn_declr_ok := declr.variant.(FnDeclrStmt); fn_declr_ok {
                funcs[declr.id.sym] = Func(fn_declr)
            }
        }
    }
    run_block(program, nil, .Global)
    return {}
}