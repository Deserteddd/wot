package wot

import "core:fmt"
import "core:os"
import "core:unicode/utf8"
import "core:reflect"


funcs: map[SymbolId]Func

Func :: distinct FnDeclrStmt

Var :: struct {
    type: Type,
    value: Value,
    const: bool,
    inferred: bool
}

Type :: enum {
    Invalid,
    None,
    Float,
    Int,
    Bool,
    String,
    Char,
}

Value :: union #no_nil {
    None,
    Float,
    Int,
    Char,
    String,
    Bool,
}

Scope_Kind :: enum {
    Global,
    Function,
    Block,
}


Scope :: struct($T: typeid) {
    symbols: map[SymbolId]T,
    parent: ^Scope(T),
    kind: Scope_Kind,
}


scope_push :: proc(parent: ^Scope($T), kind: Scope_Kind) -> Scope(T) {
    if kind == .Global && parent != nil {
        panic("Global scope cannot have a parent")
    }
    if kind != .Global && parent == nil {
        panic("Non-global scope requires a parent")
    }

    return Scope(T) {
        symbols = make_map(map[SymbolId]T),
        parent = parent,
        kind = kind,
    }
}

scope_pop :: proc(scope: ^Scope($T)) {
    if scope == nil do return
    if scope.symbols != nil {
        delete(scope.symbols)
    }
    scope.parent = nil
}


scope_fetch :: proc(scope: ^Scope($T), id: SymbolId) -> ^T {
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
            if found && var^.const do return var
        }
        s = s.parent
    }

    return nil
}

scope_add :: proc(scope: ^Scope($T), id: SymbolId, value: T) -> bool {
    existing := scope_fetch(scope, id)
    if existing != nil {
        existing^ = value
        return true
    }
    scope.symbols[id] = value
    return false
}


format_value :: proc(v: Value) -> string {
    #partial switch value in v {
        case Int, Float:
            return fmt.tprint(value)
        case Char:
            return fmt.tprint(rune(value))
        case Bool:
            return fmt.tprintf("%t", value)
        case String: return string(value)

    }
    return "Invalid"
}

print_values :: proc(args: []Value, newline: bool) {
    for value, i in args {
        if i > 0 {
            fmt.print(" ", flush = false)
        }
        fmt.print(format_value(value), flush = false)
    }

    if newline {
        fmt.println()
    }
}

value_type :: proc(v: Value, loc := #caller_location) -> Type {
    #partial switch v in v {
        case Int:       return .Int
        case Float:     return .Float
        case Bool:      return .Bool
        case None:      return .None
        case Char:      return .Char
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
    fmt.eprint("Runtime error: ")
	if pos != {} do fmt.eprintf("%s(%d:%d) ", pos.file, pos.line, pos.column)
	fmt.eprintf(msg, ..args)
	fmt.eprintf("\n")
    os.exit(1)
}

eval :: proc(e: Expr, scope: ^Scope(Var), loc := #caller_location) -> Value {
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
        case String:
            result = String(v)
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
            left_val := eval(v.left, scope, loc = loc)
            right_val := eval(v.right, scope, loc = loc)

            left_var: ^Var
            right_var: ^Var
            if _, ok := v.left.variant.(Identifier); ok {
                left_var = scope_fetch(scope, v.left.id)
            }
            if _, ok := v.right.variant.(Identifier); ok {
                right_var = scope_fetch(scope, v.right.id)
            }

            if left_var != nil {
                promote_inferred_for_binary(left_var, value_type(right_val), v.left.pos)
                left_val = left_var.value
            }
            if right_var != nil {
                promote_inferred_for_binary(right_var, value_type(left_val), v.right.pos)
                right_val = right_var.value
            }

            left_type := value_type(left_val)
            right_type := value_type(right_val)
            if left_type == .Int && right_type == .Float {
                if left_var != nil && !left_var.inferred do runtime_error(
                    v.left.pos,
                    "Cannot use int %v with float value",
                    symbol_name(v.left.id)
                )
            }
            if left_type == .Float && right_type == .Int {
                if right_var != nil && !right_var.inferred do runtime_error(
                    v.right.pos,
                    "Cannot use int %v with float value",
                    symbol_name(v.right.id)
                )
            }

            val, ok := apply_op(v.op, left_val, right_val)
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
                        text = symbol_name(callee),
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
            runtime_error(e.pos, "Invalid expression: %w", e.variant, loc = loc)
    }
    return result
}

promote_inferred_for_binary :: proc(var: ^Var, other_type: Type, pos: Pos) {
    if var == nil do return
    if !var.inferred do return

    if var.type == .Int && other_type == .Float {
        int_val, ok := var.value.(Int)
        if !ok do runtime_error(pos, "Inferred int has non-int value")
        var.value = Float(int_val)
        var.type = .Float
        var.inferred = false
    }
}

@(private = "file")
execute_call :: proc(id: Token, args: []Expr, scope: ^Scope(Var)) -> Value {
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

        case "type_of":
            args_pos := id.pos
            args_pos.column += utf8.rune_count(id.text)
            if len(args) != 1 {
                runtime_error(
                    args_pos,
                    "Expected 1 argument, got %v",
                    len(args)
                )
            }
            #partial switch arg in args[0].variant {
            case Identifier:
                val := scope_fetch(scope, arg)
                if val == nil do runtime_error(
                    args_pos,
                    "Undeclared variable: %v",
                    symbol_name(arg)
                )
                val_type := reflect.union_variant_typeid(val.value)
                fmt.println(val_type)
            }

            return {}

        case:
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
                expected_type := type_from_string(param.type)
                if expected_type == .Float && val_type == .Int {
                    arg_var: ^Var
                    if _, ok := arg.variant.(Identifier); ok {
                        arg_var = scope_fetch(scope, arg.id)
                    }
                    if arg_var != nil {
                        if !arg_var.inferred do runtime_error(
                            arg.pos,
                            "Invalid argument of type %v, expected %v",
                            val_type, param.type
                        )
                        promote_inferred_for_binary(arg_var, .Float, arg.pos)
                        rhs = arg_var.value
                    } else {
                        rhs = Float(rhs.(Int))
                    }
                    val_type = .Float
                }
                if val_type != expected_type do runtime_error(
                    arg.pos,
                    "Invalid argument of type %v, expected %v",
                    val_type, param.type
                )

                scope_add(&fn_scope, param.id.sym, Var { value_type(rhs), rhs, true, false})
            }

            return_val := run_block(func.body, &fn_scope, .Block)
            expected_type := type_from_string(func.return_type)
            actual_type := value_type(return_val)

            if actual_type != expected_type do runtime_error(
                id.pos,
                "Invalid return type: %v, expected %v",
                value_type(return_val), type_from_string(func.return_type)
            )
            return return_val
    }
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

apply_int_op :: #force_inline proc(op: BinaryOp, a, b: Int) -> (val: Value, ok: bool) {
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

apply_float_op :: #force_inline proc(op: BinaryOp, a, b: Float) -> (val: Value, ok: bool) {
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

apply_bool_op :: #force_inline proc(op: BinaryOp, a, b: Bool) -> (val: Value, ok: bool) {
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

apply_op :: #force_inline proc(op: BinaryOp, v1, v2: Value, loc := #caller_location) -> (val: Value, ok: bool) {
    #partial switch &left in v1 {
        case Int:
            right, right_ok := v2.(Int)
            if right_ok do return apply_int_op(op, left, right)
            right_float, right_float_ok := v2.(Float)
            if right_float_ok do return apply_float_op(op, Float(left), right_float)

        case Float:
            right, right_ok := v2.(Float)
            if right_ok do return apply_float_op(op, left, right)
            right_int, right_int_ok := v2.(Int)
            if right_int_ok do return apply_float_op(op, left, Float(right_int))

        case Bool:
            right, right_ok := v2.(Bool)
            if !right_ok do return
            return apply_bool_op(op, left, right)
    }
    v1_variant := reflect.union_variant_typeid(v1)
    v2_variant := reflect.union_variant_typeid(v2)
    runtime_error({}, "Can't apply op: %v: %v %v %v: %v", v1, v1_variant, op, v2, v2_variant, loc = loc)

    return
}

@(private = "file")
run_block :: proc(block: BlockStmt, scope: ^Scope(Var), block_type: Scope_Kind) -> Value {
    frame := scope_push(scope, block_type)
    defer scope_pop(&frame)

    return_value: Value

    for stmt in block {
        #partial switch &s in stmt {
            case DeclrStmt:
                switch declr_stmt in s.variant {
                    case VarDeclrStmt:
                        rhs := eval(declr_stmt.value, &frame)
                        var_type := declr_stmt.type
                        if declr_stmt.inferred {
                            var_type = value_type(rhs)
                        }
                        var := Var{var_type, rhs, declr_stmt.const, declr_stmt.inferred}
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
                rhs_var: ^Var
                if _, ok := s.value.variant.(Identifier); ok {
                    rhs_var = scope_fetch(&frame, s.value.id)
                    if rhs_var != nil {
                        promote_inferred_for_binary(rhs_var, assignee.type, s.value.pos)
                        rhs = rhs_var.value
                    }
                }
                rhs_type := value_type(rhs)
                if assignee.type != rhs_type {
                    if assignee.type == .Float && rhs_type == .Int {
                        if rhs_var != nil && !rhs_var.inferred do runtime_error(
                            s.value.pos,
                            "Cannot assign int %v to float %v",
                            symbol_name(s.value.id),
                            s.id.text
                        )
                        rhs = Float(rhs.(Int))
                        rhs_type = .Float
                    }
                    else if assignee.type == .Int && assignee.inferred && rhs_type == .Float {
                        assignee.type = .Float
                        assignee.inferred = false
                    }
                    else do runtime_error(
                        s.id.pos,
                        "Cannot assign value of type %v to %v: %v",
                        value_type(rhs), s.id.text, assignee.type
                    )
                }

                if s.op != .Assign {
                    op, ok := binary_op_from_assign_op(s.op)
                    if !ok do runtime_error(
                        s.id.pos,
                        "Invalid compound assignment operator %w",
                        s.id.text
                    )

                    rhs, ok = apply_op(op, assignee.value, rhs)
                    if !ok do runtime_error(
                        s.id.pos,
                        "Cannot apply compound assignment to %w",
                        s.id.text
                    )
                }

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
        if declr, ok := stmt.(DeclrStmt); ok {
            if fn_declr, declr_ok := declr.variant.(FnDeclrStmt); declr_ok {
                funcs[declr.id.sym] = Func(fn_declr)
            }
        }
    }
    scope: ^Scope(Var) = nil
    run_block(program, scope, .Global)
    return {}
}