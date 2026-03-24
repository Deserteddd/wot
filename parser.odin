package wot

import "core:fmt"

Parser :: struct {
    lexer: ^Lexer,
    current,
    previous: Token
}

init_parser :: proc(p: ^Parser, lexer: ^Lexer) {
    p.lexer = lexer
    p.current = scan_token(p.lexer)
}

parse_program :: proc(p: ^Parser) {
    fmt.println(p.current)
    fmt.println(peek_token(p.lexer^))
}