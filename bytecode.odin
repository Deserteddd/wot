package wot

import "core:reflect"
import "core:fmt"

Instruction :: enum {
    ADD,
    SUB,
    MUL,
    STORE,
}



generate_wordcode :: proc(program: BlockStmt) -> []Instruction {
    instructions: [dynamic]Instruction
    for stmt in program {

    }
    return instructions[:]
}