package wot

import "core:unicode/utf8"
import "core:unicode"
import "core:fmt"

Lexer :: struct {
    source:         string,
    path:           string,
	ch:             rune,
    offset:         int,
    read_offset:    int,
    line_offset:    int,
    line_count:     int,
    error_count:    int
}


default_error_handler :: proc(pos: Pos, msg: string, args: ..any) {
	fmt.eprintf("%s(%d:%d) ", pos.file, pos.line, pos.column)
	fmt.eprintf(msg, ..args)
	fmt.eprintf("\n")
}

lex_error :: proc(l: ^Lexer, offset: int, msg: string, args: ..any) {
    pos := offset_to_pos(l, offset)
    default_error_handler(pos, msg, ..args)
    l.error_count += 1
}

init_lexer :: proc(l: ^Lexer, src: string, path: string){
    l.source = src
    l.ch = ' '
    l.path = path
    l.line_count = len(src) > 0 ? 1 : 0
    advance_rune(l)
    if l.ch == utf8.RUNE_BOM do advance_rune(l) // Skip byte order mark
}


scan_token :: proc(l: ^Lexer) -> (token: Token) {
    using token
    skip_whitespace(l)
    offset := l.offset
    pos = offset_to_pos(l, offset)
    ch := l.ch

    if is_letter(ch) {
        kind = .Id
        text = scan_identifier(l)
        if keyword := keywords[text]; keyword != .Invalid do kind = keyword
    } else if is_digit(ch) {
        kind, text = scan_number(l)
    } else if ch == '"' {
        kind = .String
        text = scan_string(l)
    } else if ch == '\'' {
        kind = .Char
        if l.offset+2 >= len(l.source) || l.source[l.offset+2] != '\'' do lex_error(l, l.offset, "Char not terminated")
        text = l.source[l.offset+1:l.offset+2]
        for _ in 0..<3 do advance_rune(l)
    } else {
        advance_rune(l)
        switch ch {
            case -1:  
                kind = .EOF
                text = "EOF"
                return

            case '(': kind = .OpenParen
            case ')': kind = .CloseParen
            case '[': kind = .OpenBracket
            case ']': kind = .CloseBracket
            case '{': kind = .OpenBrace
            case '}': kind = .CloseBrace
            case '.': kind = .Period
            case ',': kind = .Comma
            case ':': kind = .Colon
            case ';': kind = .Semicolon
            case '|':
                if l.ch == '|' {
                    advance_rune(l)
                    kind = .Or
                }
            case '&':
                if l.ch == '&' {
                    advance_rune(l)
                    kind = .And
                }
            case '\n':
                    kind = .Newline
                    text = "\n"
                    return

            case '=':
                kind = .Eq
                if l.ch == '=' {
                    advance_rune(l)
                    kind = .CmpEq
                }
            case '!':
                kind = .Not
                if l.ch == '=' {
                    advance_rune(l)
                    kind = .NotEq
                }
            case '+':
                kind = .Add
                if l.ch == '=' {
                    advance_rune(l)
                    kind = .AddEq
                }
            case '-':
                kind = .Sub
                if l.ch == '=' {
                    advance_rune(l)
                    kind = .SubEq
                }
            case '*':
                kind = .Mul
                if l.ch == '=' {
                    advance_rune(l)
                    kind = .MulEq
                }
            case '/':
                kind = .Div
                if l.ch == '=' {
                    advance_rune(l)
                    kind = .DivEq
                }
            case '%':
                kind = .Mod
                if l.ch == '=' {
                    advance_rune(l)
                    kind = .ModEq
                }
            case '<':
                kind = .Lt
                if l.ch == '=' {
                    advance_rune(l)
                    kind = .Lt_Eq
                }
            case '>':
                kind = .Gt
                if l.ch == '=' {
                    advance_rune(l)
                    kind = .Gt_Eq
                }
        }
        text = string(l.source[offset : l.offset])
        
    }

    return
}

scan_string :: proc(l: ^Lexer) -> string {
    advance_rune(l)
	offset := l.offset
    for {
        ch := l.ch
        if ch < 0 {
            lex_error(l, l.offset, "String not terminated")
            break
        }
        advance_rune(l)
        if ch == '"' {
            break
        }
    }
	return string(l.source[offset : l.offset-1])
}


scan_identifier :: proc(l: ^Lexer) -> string {
	offset := l.offset

	for is_letter(l.ch) || is_digit(l.ch) {
		advance_rune(l)
	}

	return string(l.source[offset : l.offset])
}

scan_number :: proc(l: ^Lexer) -> (TokenKind, string) {
    offset := l.offset
    kind: TokenKind
    for is_digit(l.ch) {
        advance_rune(l)
    }
    if l.ch == '.' {
        advance_rune(l)
        for is_digit(l.ch) {
            advance_rune(l)
        }
        kind = .Float
    } else {
        kind = .Int
    }

    return kind, string(l.source[offset : l.offset])
}

is_letter :: proc(r: rune) -> bool {
	if r < utf8.RUNE_SELF {
		switch r {
		case '_':
			return true
		case 'A'..='Z', 'a'..='z':
			return true
		}
	}
	return unicode.is_letter(r)
}

is_digit :: proc(r: rune) -> bool {
	if '0' <= r && r <= '9' {
		return true
	}
	return unicode.is_digit(r)
}

skip_whitespace :: proc(l: ^Lexer) {
    for {
        switch l.ch {
            case ' ', '\t', '\r':
                advance_rune(l)
            case:
                return
        }
    }
}

advance_rune :: proc(l: ^Lexer) {
    if l.read_offset < len(l.source) {
        l.offset = l.read_offset
        if l.ch == '\n' {
            l.line_offset = l.offset
            l.line_count += 1
        }
		r, w := rune(l.source[l.read_offset]), 1
        switch {
            case r == 0:
                lex_error(l, l.offset, "Illegal NUL character")
            case r >= utf8.RUNE_SELF:
                r, w = utf8.decode_last_rune_in_string(l.source[l.read_offset:])
                if r == utf8.RUNE_ERROR && w == 1 {
                    lex_error(l, l.offset, "Illegal UTF-8 encoding")
                } else if r == utf8.RUNE_BOM && l.offset > 0 {
                    lex_error(l, l.offset, "Illegal byte order mark")
                }
        }
        l.read_offset += w
        l.ch = r
    } else {
        l.offset = len(l.source)
        if l.ch == '\n' {
            l.line_offset = l.offset
            l.line_count += 1
        }
        l.ch = -1
    }
}

offset_to_pos :: proc(l: ^Lexer, offset: int) -> Pos {
	line := l.line_count
	column := offset - l.line_offset + 1

	return Pos {
        file = l.path,
		offset = offset,
		line = line,
		column = column,
	}
}