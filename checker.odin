package wot

import "core:fmt"

Usage :: struct {
    op: string,
    id: string,
    type: string,
    value: string
}

check_ast :: proc(program: BlockStmt) {
    usages: [dynamic]Usage

    for stmt in program {
        #partial switch &s in stmt {
        case DeclrStmt:
            #partial switch &declr in s.variant {
            case VarDeclrStmt:
                var_declr := Usage {
                    op = "Declare",
                    id = s.id.text,
                    type = declr.type,
                    value = fmt.aprint(declr.value.variant)
                }
                append(&usages, var_declr)
            }
        
        case AssignStmt:
            assignment := Usage {
                op = fmt.aprint(s.op),
                id = s.id.text,
                type = "<unknown>",
                value = fmt.aprint(s.value.variant)
            }
            append(&usages, assignment)
        }
    }

    for u in usages {
        switch u.op {
        case "Declare":
            fmt.printfln(
                "%v %v: %v = %v",
                u.op,
                u.id,
                u.type == "" ? "<unknown>" : u.type,
                u.value == "" ? "None"     : u.value
            )
        case:
            fmt.printfln(
                "%v %v %v",
                u.id,
                u.op,
                u.value == "" ? "None"     : u.value
            )
        }
    }
}