package wot

import os "core:os/os2"
import "core:fmt"
import "core:time"
import vmem "core:mem/virtual"

main :: proc() {
    start := time.now()
    arena: vmem.Arena
    err := vmem.arena_init_growing(&arena)
    assert(err == .None)
    arena_allocator := vmem.arena_allocator(&arena)
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
    compile_time := time.since(start)
    fmt.println("--------------------------------------")
    fmt.printfln("Compiled in: %v", compile_time)
    fmt.println("--------------------------------------")
    start = time.now()
    run(program)
    run_time := time.since(start)
    fmt.println("--------------------------------------")
    fmt.printfln("Executed in: %v", run_time)
    fmt.println("--------------------------------------")
}