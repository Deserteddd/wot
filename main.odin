package wot

import "core:os"
import filepath "core:path/filepath"
import "core:fmt"
import "core:time"
import vmem "core:mem/virtual"
import "base:runtime"
import "core:slice"

main :: proc() {
    arena: vmem.Arena
    err := vmem.arena_init_growing(&arena)
    assert(err == .None)
    arena_allocator := vmem.arena_allocator(&arena)
    defer vmem.arena_destroy(&arena)
    context.allocator = arena_allocator

    if len(os.args) < 2 {
        fmt.eprintln("Missing input file")
        os.exit(1)
    }
    input, alloc_err := os.read_entire_file_from_path(os.args[1], context.allocator)
	if alloc_err != nil {
		fmt.eprintln("Failed to read source:", err)
		return
	}

    build_run(
        string(input),
        slice.contains(os.args, "-dump")
    )

}

build_run :: proc(source: string, dump: bool) {
    start := time.now()
    lexer: Lexer
    init_lexer(&lexer, source, os.args[1])
    parser: Parser
    init_parser(&lexer, &parser)
    program := parse_program(&parser)
    run_ast(program)
    ir := generate_program_ir(program)
    free_all(context.temp_allocator)
    print_compiler_stage_time(&start, "Compiled")

    if dump {
        dump_name := fmt.tprintf("%s_dump.txt", filepath.stem(os.args[1]))
        dump_path := fmt.tprintf("%s%c%s", filepath.dir(os.args[1]), filepath.SEPARATOR, dump_name)
        dump_err := os.write_entire_file_from_string(dump_path, fmt_ir(ir))
        if dump_err != nil {
            fmt.eprintfln("Failed to write IR dump to %v: %v", dump_path, dump_err)
            return
        }
        fmt.printfln("Wrote IR dump to: %v", dump_path)
    }
    start = time.now()
    run_ir(&ir)
    print_compiler_stage_time(&start, "VM ran")
}

print_compiler_stage_time :: proc(start: ^time.Time, stage: string) {
    elapsed := time.since(start^)
    fmt.println("--------------------------------------")
    fmt.printfln("%v in: %v", stage, elapsed)
    fmt.println("--------------------------------------")
    start^ = time.now()
}