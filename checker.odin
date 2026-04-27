package wot

import "core:fmt"
import "core:unicode/utf8"

check_call :: proc(id: Token, args: []Expr, scope: ^Scope) -> Value {
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

            return_val := check_block(func.body, &fn_scope, .Block)
            expected_type := type_from_string(func.return_type)
            actual_type := value_type(return_val)

            if actual_type != expected_type {
                runtime_error(
                    id.pos,
                    "Invalid return type: %v, expected %v",
                    value_type(return_val), type_from_string(func.return_type)
                )
            }
            return return_val
    }
}

check_block :: proc(block: BlockStmt, scope: ^Scope, block_type: Scope_Kind) -> Value {
    frame := scope_push(scope, block_type)
    defer scope_pop(&frame)

    return_value: Value

    for stmt in block {
        #partial switch &s in stmt {
            case DeclrStmt:
                switch declr_stmt in s.variant {
                    case VarDeclrStmt:
                        rhs := eval(declr_stmt.value, &frame)
                        value_type := value_type(rhs)
                        var := Var{value_type, rhs, declr_stmt.const}
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

                if s.deref {
                    ref, ok := assignee.value.(^Value)
                    if !ok do runtime_error(
                        s.id.pos,
                        "Cannot assign through non-reference %w",
                        s.id.text
                    )

                    target := ref^
                    if s.op != .Assign {
                        op, ok := binary_op_from_assign_op(s.op)
                        if !ok do runtime_error(
                            s.id.pos,
                            "Invalid compound assignment operator %w",
                            s.id.text
                        )

                        rhs, ok = apply_op(op, target, rhs)
                        if !ok do runtime_error(
                            s.id.pos,
                            "Cannot apply compound assignment through %w",
                            s.id.text
                        )
                    }

                    ref^ = rhs
                } else {
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

                    assignee.type = value_type(rhs)
                    assignee.value = rhs
                }
            case CallStmt:
                return_value = check_call(s.id, s.args, &frame)
            case IfStmt:
                cond := eval(s.condition, &frame)
                if _, bool_val_ok := cond.(Bool); bool_val_ok {
                    check_block(s.main_body, &frame, .Block)
                    check_block(s.else_body, &frame, .Block)
                } else do runtime_error(s.condition.pos, "If-condition must evaluate to bool")
            case WhileStmt:
                cond := eval(s.condition, &frame)
                if bool_val, bool_val_ok := cond.(Bool); bool_val_ok {
                    check_block(s.body, &frame, .Block)
                } else do runtime_error(s.condition.pos, "While-condition must evaluate to bool")
            case BlockStmt:
                check_block(s, &frame, .Block)
        }
    }
    if block_type != .Function {
        assert(return_value == None{})
    }
    return return_value
}



check_ast :: proc(program: BlockStmt) {
    fmt.println("Checking AST")
    for stmt in program {
        if declr, declr_ok := stmt.(DeclrStmt); declr_ok {
            if fn_declr, fn_declr_ok := declr.variant.(FnDeclrStmt); fn_declr_ok {
                funcs[declr.id.sym] = Func(fn_declr)
            }
        }
    }

    check_block(program, nil, .Global)
}