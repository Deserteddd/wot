package wot

import "core:fmt"
import "core:unicode/utf8"
import "core:reflect"


checker_error :: proc(pos: Pos, msg: string, args: ..any, loc := #caller_location) {
    if ODIN_DEBUG {
        fmt.eprintfln("%v ", loc)
    }
    fmt.eprint("Error: ")
	if pos != {} do fmt.eprintf("%s(%d:%d) ", pos.file, pos.line, pos.column)
	fmt.eprintf(msg, ..args)
	fmt.eprintf("\n")
}

check_block :: proc(block: BlockStmt, scope: ^Scope(VarDeclrStmt), block_type: Scope_Kind) {
    frame := scope_push(scope, block_type)
    defer scope_pop(&frame)

    for &stmt in block {
        #partial switch &s in stmt {
        case DeclrStmt:
            switch &declr_stmt in s.variant {
                case VarDeclrStmt: // Check variable declarations
                    if declr_stmt.type == .None {
                        inferred_type := infer(declr_stmt.value, &frame)
                        if inferred_type == .Invalid do checker_error(
                            s.id.pos,
                            "Couldn't infer the type for %v",
                            s.id.text
                        )
                        declr_stmt.type = inferred_type
                        declr_stmt.inferred = true
                    } else if !check(declr_stmt.value, declr_stmt.type, &frame) do checker_error(
                        s.id.pos,
                        "Invalid type %v for %v",
                        declr_stmt.type, s.id.text
                    )

                    if scope_add(&frame, s.id.sym, declr_stmt) do checker_error(
                        s.id.pos,
                        "Redeclaration of %w in current scope",
                        s.id.text
                    )


                    
                case FnDeclrStmt:
                    if block_type != .Global do checker_error(
                        s.id.pos,
                        "Nested functions aren't supported (yet)"
                    )
            }
        case BlockStmt:
            check_block(s, &frame, .Block)
        }
    }

    for key, value in frame.symbols {
        fmt.printfln("%v = (%v: %v)", 
            symbol_name(key), 
            reflect.union_variant_typeid(value.value.variant), 
            value.value.variant 
        )
    }
}

is_numeric_type :: #force_inline proc(t: Type) -> bool {
    return t == .Int || t == .Float
}

try_promote_identifier_to_float :: proc(expr: Expr, scope: ^Scope(VarDeclrStmt)) -> bool {
    if scope == nil do return false
    if _, ok := expr.variant.(Identifier); !ok do return false

    declr := scope_fetch(scope, expr.id)
    if declr == nil do return false
    if declr.type == .Int && declr.inferred {
        declr.type = .Float
        return true
    }
    return false
}

infer_binary_numeric :: proc(left: Expr, right: Expr, scope: ^Scope(VarDeclrStmt)) -> Type {
    left_type := infer(left, scope)
    right_type := infer(right, scope)
    if !is_numeric_type(left_type) || !is_numeric_type(right_type) do return .Invalid

    if left_type == .Float && right_type == .Int {
        if try_promote_identifier_to_float(right, scope) do return .Float
        return .Invalid
    }
    if right_type == .Float && left_type == .Int {
        if try_promote_identifier_to_float(left, scope) do return .Float
        return .Invalid
    }
    return left_type
}

infer :: proc(expr: Expr, scope: ^Scope(VarDeclrStmt)) -> Type {
    #partial switch e in expr.variant {
        case None: return .None
        case Int: return .Int
        case Float: return .Float
        case Bool: return .Bool
        case Char: return .Char
        case Identifier:
            declr := scope_fetch(scope, expr.id)
            if declr == nil do checker_error(
                expr.pos,
                "Undeclared identifier %w",
                symbol_name(expr.id),
            )
            if declr == nil do return .Invalid
            return declr.type
        case ^UnaryExpr:
            #partial switch e.op {
                case .Not:
                    if infer(e.expr, scope) == .Bool do return .Bool
                    return .Invalid
                case .Sub:
                    t := infer(e.expr, scope)
                    if is_numeric_type(t) do return t
                    return .Invalid
                case:
                    return .Invalid
            }
        case ^BinaryExpr:
            #partial switch e.op {
                case .Add, .Sub, .Mul, .Div, .Mod:
                    return infer_binary_numeric(e.left, e.right, scope)
                case .CmpEq, .NotEq, .Lt, .Gt, .Lt_Eq, .Gt_Eq:
                    if infer_binary_numeric(e.left, e.right, scope) != .Invalid do return .Bool
                    return .Invalid
                case .And, .Or:
                    if infer(e.left, scope) == .Bool && infer(e.right, scope) == .Bool do return .Bool
                    return .Invalid
                case:
                    return .Invalid
            }
        case ^CallExpr:
            return .Invalid
    }
    return .Invalid
}

check :: proc(expr: Expr, type: Type, scope: ^Scope(VarDeclrStmt)) -> bool {
    inferred := infer(expr, scope)
    if inferred == type do return true
    if type == .Float && inferred == .Int {
        _ = try_promote_identifier_to_float(expr, scope)
        return true
    }
    return false
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
    scope: ^Scope(VarDeclrStmt) = nil
    check_block(program, scope, .Global)
}