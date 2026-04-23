package wot

import "core:reflect"
import "core:fmt"

Instruction :: struct {
}



create_interp_tree :: proc(program: BlockStmt) {
    instructions: [dynamic]Instruction
    for stmt in program {
        fmt.println(reflect.union_variant_typeid(stmt))
    }
}