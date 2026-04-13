package wot

import "core:fmt"

vars: map[string]Var

Var :: struct {
    type: Type,
    value: Value,
    depth: int
}


Type :: enum {
    Float,
    Int,
    String,
    Bool,
}

Value :: union {
    f64,
    int,
    string,
    bool
}

value_type :: proc(v: Value) -> Type {
    #partial switch v in v {
        case int:
            return .Int
        case f64:
            return .Float
        case string:
            return .String
        case bool:
            return .Bool
    }
    panic("invalid value type")
}

binary_op_from_stmt_type :: proc(t: StmtType) -> (op: Binary_Op, ok: bool) {
    ok = true
    #partial switch t {
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

run :: proc(stmts: []^Stmt, depth := 0) {
    vars = make(map[string]Var)
    for stmt in stmts {
        #partial switch stmt.type {
            case .Assign:
                rhs := eval(stmt.value^)
                vars[stmt.id] = Var{type = value_type(rhs), value = rhs, depth = depth}

            case .AddEq, .SubEq, .MulEq, .DivEq, .ModEq:
                old_var, exists := vars[stmt.id]
                if !exists {
                    panic("Undefined identifier in compound assignment")
                }

                rhs := eval(stmt.value^)
                op, op_ok := binary_op_from_stmt_type(stmt.type)
                if !op_ok {
                    panic("Invalid compound assignment operator")
                }

                value, ok := apply_op(op, old_var.value, rhs)
                if !ok {
                    panic("Invalid compound assignment operands")
                }

                vars[stmt.id] = Var{type = value_type(value), value = value}

            case .Print:
                fmt.println(eval(stmt.value^))
            
        }
    }
}


eval :: proc(e: Expr) -> Value {
    result: Value
    #partial switch v in e {
        case IntExpr:
            result = int(v)
        case FloatExpr:
            result = f64(v)
        case StringExpr:
            result = string(v)
        case BoolExpr:
            result = bool(v)
        case IdentifierExpr:
            variable, exists := vars[string(v)]
            if !exists {
                panic("Undeclared name past parser")
            }
            result = variable.value
        case BinaryExpr:
            val, ok := apply_op(v.op, eval(v.left^), eval(v.right^))
            if !ok {
                panic("Invalid operands for binary operation")
            }
            result = val
        case:
            panic("Invalid expression")
    }
    return result
}

apply_int_op :: proc(op: Binary_Op, a, b: int) -> (val: Value, ok: bool) {
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

apply_float_op :: proc(op: Binary_Op, a, b: f64) -> (val: Value, ok: bool) {
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

apply_bool_op :: proc(op: Binary_Op, a, b: bool) -> (val: Value, ok: bool) {
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

apply_op :: proc(op: Binary_Op, v1, v2: Value) -> (val: Value, ok: bool) {
    #partial switch left in v1 {
        case int:
            right, right_ok := v2.(int)
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
                right_int, right_int_ok := v2.(int)
                if !right_int_ok do return
                return apply_float_op(op, left, f64(right_int))
            }

        case bool:
            right, right_ok := v2.(bool)
            if !right_ok do return
            return apply_bool_op(op, left, right)

        case string:
            // Strings are valid values, but binary arithmetic on strings is not supported.
            return
    }

    return
}