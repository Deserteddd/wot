package wot

import "core:testing"

code := `
add :: fn(n1: int, n2: int) -> int {
    return n1 + n2
}
a := add(4, 3)
`


@(test)
test_lexer :: proc(t: ^testing.T) {
    lexer: Lexer
    init_lexer(&lexer, code, "test_path")
    parser: Parser
    init_parser(&lexer, &parser)
    program := parse_program(&parser)
}