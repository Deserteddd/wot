package wot

import "core:fmt"
import "core:reflect"

check_program :: proc(program: []Stmt) -> bool {
    for stmt in program {
        stmt_type := reflect.union_variant_type_info(stmt)
        fmt.println(stmt_type)
    }
    return true
}