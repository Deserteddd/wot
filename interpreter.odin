package wot

import "core:fmt"
import os "core:os/os2"
import "core:reflect"
import "core:strings"
import "core:unicode/utf8"

funcs: map[string]Func

Func :: distinct FnDeclrStmt

Builder :: strings.Builder

Var :: struct {
    type: Type,
    value: Value,
    const: bool
}

Type :: enum {
    None,
    Float,
    Int,
    String,
    Bool,
}

Value :: union {
    None,
    f64,
    i64,
    Builder,
    bool
}

Scope_Kind :: enum {
    Global,
    Function,
    Block,
}



Scope :: struct {
    symbols: map[string]Var,
    parent: ^Scope,
    kind: Scope_Kind,
}


scope_fetch :: proc(scope: ^Scope, id: string) -> ^Var {
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
            if found do return var
        }
        s = s.parent
    }

    return nil
}

scope_add :: proc(scope: ^Scope, id: string, v: Var) -> (overwrote: bool) {
    val, found := &scope.symbols[id]
    overwrote = found
    if overwrote do val^ = v
    else do scope.symbols[id] = v

    return
}


format_value_with_verb :: proc(v: Value, verb: byte) -> string {
    #partial switch value in v {
        case i64:
            switch verb {
                case 'v': return fmt.tprintf("%v", value)
                case 'd', 'i': return fmt.tprintf("%d", value)
                case 'b': return fmt.tprintf("%b", value)
                case 'o': return fmt.tprintf("%o", value)
                case 'x': return fmt.tprintf("%x", value)
                case 'X': return fmt.tprintf("%X", value)
            }
        case f64:
            switch verb {
                case 'v': return fmt.tprintf("%v", value)
                case 'f': return fmt.tprintf("%f", value)
                case 'e': return fmt.tprintf("%e", value)
                case 'E': return fmt.tprintf("%E", value)
                case 'g': return fmt.tprintf("%g", value)
                case 'G': return fmt.tprintf("%G", value)
            }
        case strings.Builder:
            switch verb {
                case 'v', 's': return fmt.tprintf("%s", strings.to_string(value))
                case 'q': return fmt.tprintf("%q", value)
            }
        case bool:
            switch verb {
                case 'v', 't': return fmt.tprintf("%t", value)
            }
    }

    panic(fmt.tprintf("Unsupported format verb '%%%c' for argument value", verb))
}

printf_values :: proc(format: string, args: []Value) {
    arg_i := 0
    segment_start := 0
    i := 0

    for i < len(format) {
        if format[i] != '%' {
            i += 1
            continue
        }

        if i > segment_start {
            fmt.print(format[segment_start:i])
        }

        if i+1 >= len(format) {
            panic("printf format string ends with '%' and missing verb")
        }

        verb := format[i+1]
        if verb == '%' {
            fmt.print("%")
            i += 2
            segment_start = i
            continue
        }

        if arg_i >= len(args) {
            panic("Not enough arguments for printf format string")
        }

        fmt.print(format_value_with_verb(args[arg_i], verb))
        arg_i += 1
        i += 2
        segment_start = i
    }

    if segment_start < len(format) {
        fmt.print(format[segment_start:])
    }

    if arg_i < len(args) {
        panic("Too many arguments for printf format string")
    }
}

print_values :: proc(args: []Value, newline: bool) {
    for value, i in args {
        if i > 0 {
            fmt.print(" ")
        }
        fmt.print(format_value_with_verb(value, 'v'))
    }

    if newline {
        fmt.println()
    }
}

value_type :: proc(v: Value, loc := #caller_location) -> Type {
    #partial switch v in v {
        case i64:       return .Int
        case f64:       return .Float
        case Builder:   return .String
        case bool:      return .Bool
        case None:      return .None
    }
    panic("Undeclared type", loc)
}

type_from_string :: proc(typename: string) -> Type {
    switch typename {
        case "int":     return .Int
        case "float":   return .Float
        case "string":  return .String
        case "bool":    return .Bool
        case:           return .None 
    }
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
        case IntExpr:
            result = i64(v)
        case FloatExpr:
            result = f64(v)
        case StringExpr:
            result = Builder(v)
        case BoolExpr:
            result = bool(v)
        case IdentifierExpr:
            variable := scope_fetch(scope, e.id.text)
            if variable == nil do runtime_error(
                e.id.pos, 
                "Undeclared identifier %w", 
                e.id.text,
                loc = loc
            )
            result = variable.value
        case ^BinaryExpr:
            val, ok := apply_op(
                v.op, 
                eval(v.left, scope, loc = loc), 
                eval(v.right, scope, loc = loc)
            )
            if !ok do runtime_error(e.id.pos, "Invalid operands for binary operation")
            result = val
        case ^UnaryExpr:
            val, ok := apply_unary_op(v.op, eval(v.expr, scope))
            if !ok do runtime_error(
                e.id.pos, 
                "Invalid operand for unary opertaion %w", 
                to_string_unary_op(v.op)
            )
            result = val
        case ^CallExpr:
            #partial switch callee in v.callee.variant {
                case IdentifierExpr:
                    id_token := Token {
                        kind = .Id,
                        text = string(callee),
                        pos = v.callee.id.pos,
                    }
                    result = execute_call(id_token, v.args, scope)
                case:
                    runtime_error(v.callee.id.pos, "Can only call identifiers")
            }
        case None:
            return v
        case:
            runtime_error(e.id.pos, "Invalid expression")
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

        case "printf", "printfln":
            if len(args) == 0 do runtime_error(
                id.pos,
                "printf expects at least one argument (format string)"
            )

            args_evaled := make([]Value, len(args), context.temp_allocator)
            for arg, i in args {
                args_evaled[i] = eval(arg, scope)
            }

            format, format_ok := args_evaled[0].(Builder)
            format_str := strings.to_string(format)
            if !format_ok do runtime_error(
                id.pos,
                "First argument of printf must be a string. Got: %v",
                reflect.union_variant_typeid(args_evaled[0])
            )

            printf_values(format_str, args_evaled[1:])
            if id.text == "printfln" do fmt.println()
            return {}

        case:
            func, func_found := funcs[id.text]
            if !func_found do runtime_error(
                id.pos,
                "Undeclared function: %v",
                id.text
            )

            fn_scope := Scope {
                symbols = make_map(map[string]Var),
                parent = scope,
                kind = .Function,
            }
            defer delete(fn_scope.symbols)


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
                    arg.id.pos,
                    "Invalid argument of type %v, expected %v",
                    val_type, param.type
                )

                scope_add(&fn_scope, param.id.text, Var { value_type(rhs), rhs, true})
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

is_legal_cast :: proc(from: Type, to: Type) -> (legal: bool) {
    if from == to do return true
    #partial switch from {
        case .Int:
            #partial switch to {
                case .Float, .Bool: legal = true
            }
    }
    return
}

apply_unary_op :: proc(op: UnaryOp, v: Value) -> (val: Value, ok: bool) {
    ok = true
    switch op {
        case .Not:
            bool_val, bool_val_ok := v.(bool);
            if !bool_val_ok {
                ok = false
            } else {
                val = !bool_val
            }
        case .Sub:
            #partial switch value in v {
                case f64:
                    val = -value
                case i64:
                    val = -value
                case:
                    ok = false
            }
        case .Invalid:
            panic("Invalid unary operator")

    }
    return
}

apply_int_op :: proc(op: BinaryOp, a, b: i64) -> (val: Value, ok: bool) {
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

apply_float_op :: proc(op: BinaryOp, a, b: f64) -> (val: Value, ok: bool) {
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

apply_bool_op :: proc(op: BinaryOp, a, b: bool) -> (val: Value, ok: bool) {
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

apply_string_op :: proc(op: BinaryOp, a: ^Builder, b: Value) -> (ok: bool) {
    ok = true
    #partial switch op {
        case .Add:
            switch b_val in b {
                case f64:
                    strings.write_f64(a, b_val, 'v')
                case i64:
                    strings.write_i64(a, b_val)
                case strings.Builder:
                    strings.write_string(a, strings.to_string(b_val))
                case bool:
                    strings.write_string(a, b_val ? "true" : "false")
                case None:
                    return
            }
        case: 
            fmt.eprintfln("%v operation not supported for string type", op)
            ok = false
    }
    return ok
}

apply_op :: proc(op: BinaryOp, v1, v2: Value) -> (val: Value, ok: bool) {
    #partial switch &left in v1 {
        case i64:
            right, right_ok := v2.(i64)
            if right_ok do return apply_int_op(op, left, right)
            else {
                right_float, right_float_ok := v2.(f64)
                if !right_float_ok do return
                return apply_float_op(op, f64(left), right_float)
            }

        case f64:
            right, right_ok := v2.(f64)
            if right_ok do return apply_float_op(op, left, right)
            else {
                right_int, right_int_ok := v2.(i64)
                if !right_int_ok do return
                return apply_float_op(op, left, f64(right_int))
            }

        case bool:
            right, right_ok := v2.(bool)
            if !right_ok do return
            return apply_bool_op(op, left, right)

        case Builder:
            ok = apply_string_op(op, &left, v2)
            val = v1
            return 
    }

    return
}

run_block :: proc(block: BlockStmt, scope: ^Scope, block_type: Scope_Kind) -> Value {
    frame := Scope {
        symbols = make_map(map[string]Var),
        parent = scope,
        kind = block_type,
    }
    defer delete(frame.symbols)

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
                                declr_stmt.value.id.pos,
                                "Cannot assign value of type \"%v\" to %v: %v",
                                declared_type, s.id.text, value_type
                            )
                        }
                        var := Var{type, rhs, declr_stmt.const}
                        scope_add(&frame, s.id.text, var)
                    case FnDeclrStmt:
                        funcs[s.id.text] = Func(declr_stmt)
                }
            case ReturnStmt:
                return eval(Expr(s), &frame)
            case AssignStmt:
                assignee := scope_fetch(&frame, s.id.text)
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
                _ = execute_call(s.id, s.args, &frame)
            case IfStmt:
                cond := eval(s.condition, &frame)
                if bool_val, bool_val_ok := cond.(bool); bool_val_ok {
                    if bool_val {
                        run_block(s.main_body, &frame, .Block)
                    } else {
                        run_block(s.else_body, &frame, .Block)
                    }
                } else do runtime_error(s.condition.id.pos, "If-condition must evaluate to bool")
            case WhileStmt:
                cond := eval(s.condition, &frame)
                if bool_val, bool_val_ok := cond.(bool); bool_val_ok {
                    for bool_val {
                        run_block(s.body, &frame, .Block)
                        bool_val = eval(s.condition, &frame).(bool)
                    }
                } else do runtime_error(s.condition.id.pos, "While-condition must evaluate to bool")
            case BlockStmt:
                run_block(s, &frame, .Block)
        }
    }
    return {}
}

run :: proc(program: BlockStmt) -> Value {
    run_block(program, nil, .Global)
    return {}
}