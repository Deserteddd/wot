package wot

import "core:reflect"
import "core:fmt"

Instruction :: struct {
}



create_interp_tree :: proc(program: BlockStmt) {
    instructions: [dynamic]Instruction
}