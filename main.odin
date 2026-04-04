package wot

import os "core:os/os2"
import "core:fmt"
import "core:time"

main :: proc() {
    start := time.now(); defer fmt.println("Finished in:", time.since(start))

    if len(os.args) < 2 do panic("Missing input file")
    input, err := os.read_entire_file_from_path(os.args[1], context.allocator)
	if err != nil {
		fmt.eprintln("Failed to read source:", err)
		return
	}
    lexer: Lexer
    init_lexer(&lexer, string(input), os.args[1])
    parser: Parser
    init_parser(&lexer, &parser)
    program := parse_program(&parser)
    run(program)
}






