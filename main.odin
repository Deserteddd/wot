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
    init_lexer(&lexer, string(input))
    tokens: int
    for token := scan_token(&lexer); true; token = scan_token(&lexer) {
        fmt.printfln("Token: %v = %w\t\t Ln %v, Col %v\n", 
            token.kind, token.text, token.pos.line, token.pos.column
        )
        tokens += 1
        if token.kind == .EOF do break
    }
    fmt.println("Tokens: ", tokens)
}






