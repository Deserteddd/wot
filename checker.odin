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

check_block :: proc(block: BlockStmt, scope: ^Scope(^VarDeclrStmt), block_type: Scope_Kind) {
    frame := scope_push(scope, block_type)
    defer scope_pop(&frame)

    for &stmt in block {
        #partial switch &s in stmt {
        case DeclrStmt:
            switch &declr_stmt in s.variant {
                case VarDeclrStmt:
                    if scope_add(&frame, s.id.sym, &declr_stmt) do checker_error(
                        s.id.pos,
                        "Redeclaration of %w in current scope",
                        s.id.text
                    )
                    fmt.println(declr_stmt.type)
                    
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

infer :: proc(expr: Expr, scope: ^Scope(VarDeclrStmt))


check_ast :: proc(program: BlockStmt) {
    fmt.println("Checking AST")
    for stmt in program {
        if declr, declr_ok := stmt.(DeclrStmt); declr_ok {
            if fn_declr, fn_declr_ok := declr.variant.(FnDeclrStmt); fn_declr_ok {
                funcs[declr.id.sym] = Func(fn_declr)
            }
        }
    }
    scope: ^Scope(^VarDeclrStmt) = nil
    check_block(program, scope, .Global)
}