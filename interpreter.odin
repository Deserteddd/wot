package wot

import "core:fmt"
import os "core:os/os2"
import "core:reflect"
import "core:strings"
import "core:unicode/utf8"

vars: map[string]Var

funcs: map[string]Func

Func :: distinct FnDeclrStmt

Var :: struct {
    type: Type,
    value: Value,
}

Type :: enum {
    None,
    Unknown,
    Float,
    Int,
    String,
    Bool,
}

Value :: union {
    NoneExpr,
    f64,
    i64,
    Builder,
    bool
}

Builder :: strings.Builder

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
        case i64:    return .Int
        case f64:    return .Float
        case Builder: return .String
        case bool:   return .Bool
    }
    panic("Undeclared type", loc)
}

type_from_string :: proc(typename: string) -> Type {
    switch typename {
        case "int":     return .Int
        case "float":   return .Float
        case "string":  return .String
        case "bool":    return .Bool
        case:           return .Unknown 
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

eval :: proc(e: Expr) -> Value {
    result: Value
    #partial switch v in e.inner {
        case IntExpr:
            result = i64(v)
        case FloatExpr:
            result = f64(v)
        case StringExpr:
            result = Builder(v)
        case BoolExpr:
            result = bool(v)
        case IdentifierExpr:
            variable, exists := vars[string(v)]
            if !exists do runtime_error(e.pos, "Undeclared identifier %w", string(v))
            result = variable.value
        case ^BinaryExpr:
            val, ok := apply_op(v.op, eval(v.left), eval(v.right))
            if !ok do runtime_error(e.pos, "Invalid operands for binary operation")
            result = val
        case ^UnaryExpr:
            val, ok := apply_unary_op(v.op, eval(v.expr))
            if !ok do runtime_error(
                e.pos, 
                "Invalid operand for unary opertaion %w", 
                to_string_unary_op(v.op)
            )
            result = val
        case NoneExpr:
            return NoneExpr(0)
        case:
            runtime_error(e.pos, "Invalid expression")
    }
    return result
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
                case NoneExpr:
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


run :: proc(program: Program) -> Value {
    for stmt in program {
        #partial switch &s in stmt {
            case DeclrStmt:
                switch declr_stmt in s.variant {
                    case VarDeclrStmt:
                        rhs := eval(declr_stmt.value)
                        declared_type := type_from_string(declr_stmt.type)
                        value_type    := value_type(rhs)
                        type := declared_type
                        if declared_type == .Unknown {
                            type = value_type
                        } else if value_type != declared_type && !(declared_type == .Float && value_type == .Int) {
                            runtime_error(
                                declr_stmt.value.pos,
                                "Cannot assign value of type: %v to %v: %v",
                                declared_type, s.id.text, value_type
                            )
                        }
                        vars[s.id.text] = Var{type, rhs}
                    case FnDeclrStmt:
                        funcs[s.id.text] = Func(declr_stmt)
                }
            case ReturnStmt:
                val := eval(Expr(s))
                fmt.println("Returning", val)
                return val
            case AssignStmt:
                rhs := eval(s.value)
                if s.op == .Assign {
                    _, exists := vars[s.id.text]
                    if !exists do runtime_error(
                        s.id.pos,
                        "Assignment to undeclared variable: %v",
                        s.id.text
                    )
                    vars[s.id.text] = Var{type = value_type(rhs), value = rhs}
                } else {
                    old_var, exists := vars[s.id.text]
                    if !exists {
                        runtime_error(
                            s.id.pos, 
                            "Compound assignment to undefined variable %w", 
                            s.id.text
                        )
                    }
                    op, op_ok := binary_op_from_assign_op(s.op)
                    if !op_ok do runtime_error(
                        s.id.pos,
                        "Invalid compound assignment operator %w",
                        s.id.text
                    )
                    
                    value, ok := apply_op(op, old_var.value, rhs)
                    if !ok do runtime_error(
                        s.id.pos,
                        "Invalid compound assignment operands",
                    )
                    vars[s.id.text] = Var{type = value_type(value), value = value}
                }
            case CallStmt:
                defer free_all(context.temp_allocator)
                switch s.id.text {
                    case "print":
                        args_evaled := make([]Value, len(s.args), context.temp_allocator)
                        for arg, i in s.args {
                            args_evaled[i] = eval(arg)
                        }
                        print_values(args_evaled, false)

                    case "println":
                        args_evaled := make([]Value, len(s.args), context.temp_allocator)
                        for arg, i in s.args {
                            args_evaled[i] = eval(arg)
                        }
                        print_values(args_evaled, true)

                    case "printf", "printfln":
                        if len(s.args) == 0 do runtime_error(
                            s.id.pos,
                            "printf expects at least one argument (format string)"
                        )

                        args_evaled := make([]Value, len(s.args), context.temp_allocator)
                        for arg, i in s.args {
                            args_evaled[i] = eval(arg)
                        }

                        format, format_ok := args_evaled[0].(Builder)
                        format_str := strings.to_string(format)
                        if !format_ok do runtime_error(
                            s.id.pos,
                            "First argument of printf must be a string. Got: %v",
                            reflect.union_variant_typeid(args_evaled[0])
                        )

                        printf_values(format_str, args_evaled[1:])
                        if s.id.text == "printfln" do fmt.println()

                    case:
                        func, func_found := funcs[s.id.text]
                        if !func_found do runtime_error(
                            s.id.pos,
                            "Undeclared function: %v",
                            s.id.text
                        )
                        args_pos := s.id.pos
                        args_pos.column += utf8.rune_count(s.id.text)
                        if len(func.params) != len(s.args) do runtime_error(
                            args_pos,
                            "Expected %v arguments, got %v",
                            len(func.params), len(s.args)
                        )

                        for arg, i in s.args {
                            param := func.params[i]
                            rhs := eval(arg)
                            val_type := value_type(rhs)
                            if val_type != type_from_string(param.type) do runtime_error(
                                arg.pos,
                                "Invalid argument of type %v, expected %v",
                                val_type, param.type
                            )

                            vars[param.id.text] = Var{type = value_type(rhs), value = rhs}
                        }
                        if func_found {
                            run(auto_cast func.body)
                        } else {
                            runtime_error(s.id.pos, "Undeclared function: %v()", s.id.text)
                        }
                }
            case IfStmt:
                cond := eval(s.condition)
                if bool_val, bool_val_ok := cond.(bool); bool_val_ok {
                    if bool_val {
                        run(auto_cast s.main_body)
                    } else {
                        run(auto_cast s.else_body)
                    }
                } else do runtime_error(s.condition.pos, "If-condition must evaluate to bool")
            case WhileStmt:
                cond := eval(s.condition)
                if bool_val, bool_val_ok := cond.(bool); bool_val_ok {
                    for bool_val {
                        run(auto_cast s.body)
                        bool_val = eval(s.condition).(bool)
                    }
                } else do runtime_error(s.condition.pos, "While-condition must evaluate to bool")
            case BlockStmt:
                run(auto_cast s)
        }
    }
    return {}
}