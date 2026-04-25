package wot

import os "core:os/os2"
import "core:fmt"
import "core:time"
import vmem "core:mem/virtual"
import "base:runtime"
import "core:slice"

main :: proc() {
    start := time.now()
    arena: vmem.Arena
    err := vmem.arena_init_growing(&arena)
    assert(err == .None)
    arena_allocator := vmem.arena_allocator(&arena)
    defer vmem.arena_destroy(&arena)
    context.allocator = arena_allocator


    if len(os.args) < 2 do panic("Missing input file")
    input, alloc_err := os.read_entire_file_from_path(os.args[1], context.allocator)
	if alloc_err != nil {
		fmt.eprintln("Failed to read source:", err)
		return
	}
    lexer: Lexer
    init_lexer(&lexer, string(input), os.args[1])
    parser: Parser
    init_parser(&lexer, &parser)
    program := parse_program(&parser)
    ir := generate_program_ir(program)
    print_compiler_stage_time("Compiled", &start)

    if slice.contains(os.args, "-vm") {
        run_ir(&ir)
        print_compiler_stage_time("VM ran", &start)
    } else {
        run_ast(program)
        print_compiler_stage_time("Ast ran", &start)
    }

}

print_compiler_stage_time :: proc(stage: string, start: ^time.Time) {
    elapsed := time.since(start^)
    fmt.println("--------------------------------------")
    fmt.printfln("%v in: %v", stage, elapsed)
    fmt.println("--------------------------------------")
    start^ = time.now()
}