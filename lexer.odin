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
}


default_error_handler :: proc(pos: Pos, msg: string, args: ..any) {
	fmt.eprintf("%s(%d:%d) ", pos.file, pos.line, pos.column)
	fmt.eprintf(msg, ..args)
	fmt.eprintf("\n")
}

lex_error :: proc(l: ^Lexer, offset: int, msg: string, args: ..any) {
    pos := offset_to_pos(l, offset)
    default_error_handler(pos, msg, ..args)
}

init_lexer :: proc(l: ^Lexer, src: string, path: string){
    l.source = src
    l.ch = ' '
    l.path = path
    l.line_count = len(src) > 0 ? 1 : 0
    advance_rune(l)
    if l.ch == utf8.RUNE_BOM do advance_rune(l) // Skip byte order mark
}

peek_token :: proc(l: Lexer) -> (token: Token) {
    l := l
    return scan_token(&l)

}

scan_token :: proc(l: ^Lexer) -> (token: Token) {
    skip_whitespace(l)
    offset := l.offset
    token.pos = offset_to_pos(l, offset)
    ch := l.ch

    if is_letter(ch) {
        token.kind = .Id
        token.text = scan_identifier(l)
        if keyword := keywords[token.text]; keyword != .Invalid {
            token.kind = keyword
        } else {
            token.sym = symbol_intern(token.text)
        }
    } else if is_digit(ch) {
        token.kind, token.text = scan_number(l)
    } else if ch == '"' {
        token.kind = .String
        token.text = scan_string(l)
    } else if ch == '\'' {
        token.kind = .Char
        if l.offset+2 >= len(l.source) || l.source[l.offset+2] != '\'' do lex_error(l, l.offset, "Char not terminated")
        token.text = l.source[l.offset+1:l.offset+2]
        for _ in 0..<3 do advance_rune(l)
    } else {
        advance_rune(l)
        switch ch {
            case -1:  
                token.kind = .EOF
                token.text = "EOF"
                return
            case '(': token.kind = .OpenParen
            case ')': token.kind = .CloseParen
            case '[': token.kind = .OpenBracket
            case ']': token.kind = .CloseBracket
            case '{': token.kind = .OpenBrace
            case '}': token.kind = .CloseBrace
            case '.': token.kind = .Period
            case ',': token.kind = .Comma
            case ':': token.kind = .Colon
            case ';': token.kind = .Semicolon
            case '|':
                if l.ch == '|' {
                    advance_rune(l)
                    token.kind = .Or
                }
            case '&':
                token.kind = .Ampersand
                if l.ch == '&' {
                    advance_rune(l)
                    token.kind = .And
                }
            case '\n':
                    token.kind = .Newline
                    token.text = "\n"
                    return

            case '=':
                token.kind = .Eq
                if l.ch == '=' {
                    advance_rune(l)
                    token.kind = .CmpEq
                }
            case '!':
                token.kind = .Not
                if l.ch == '=' {
                    advance_rune(l)
                    token.kind = .NotEq
                }
            case '+':
                token.kind = .Add
                if l.ch == '=' {
                    advance_rune(l)
                    token.kind = .AddEq
                }
            case '-':
                token.kind = .Sub
                if l.ch == '=' {
                    advance_rune(l)
                    token.kind = .SubEq
                }
            case '*':
                token.kind = .Asterisk
                if l.ch == '=' {
                    advance_rune(l)
                    token.kind = .MulEq
                }
            case '/':
                token.kind = .Div
                if l.ch == '=' {
                    advance_rune(l)
                    token.kind = .DivEq
                } else if l.ch == '/' {
                    advance_rune(l)
                    for l.ch != '\n' && l.ch != -1 {
                        advance_rune(l)
                    }
                    return scan_token(l)
                }
            case '%':
                token.kind = .Mod
                if l.ch == '=' {
                    advance_rune(l)
                    token.kind = .ModEq
                }
            case '<':
                token.kind = .Lt
                if l.ch == '=' {
                    advance_rune(l)
                    token.kind = .Lt_Eq
                }
            case '>':
                token.kind = .Gt
                if l.ch == '=' {
                    advance_rune(l)
                    token.kind = .Gt_Eq
                }
        }
        token.text = string(l.source[offset : l.offset])
        
    }

    return
}


scan_string :: proc(l: ^Lexer) -> string {
    advance_rune(l)
	offset := l.offset
    escaped := false
    for {
        ch := l.ch
        if ch < 0 {
            lex_error(l, l.offset, "String not terminated")
            break
        }

        if !escaped && ch == '"' {
            break
        }

        if !escaped && ch == '\\' {
            escaped = true
        } else {
            escaped = false
        }

        advance_rune(l)
    }

    raw := string(l.source[offset:l.offset])
    if l.ch == '"' {
        advance_rune(l) // consume closing quote
    }

    out: [dynamic]u8
    i := 0
    for i < len(raw) {
        if raw[i] != '\\' {
            append(&out, raw[i])
            i += 1
            continue
        }

        if i+1 >= len(raw) {
            lex_error(l, offset+i, "Invalid escape sequence")
            append(&out, raw[i])
            break
        }

        esc := raw[i+1]
        switch esc {
            case 'n': append(&out, byte('\n'))
            case 't': append(&out, byte('\t'))
            case 'r': append(&out, byte('\r'))
            case '\\': append(&out, byte('\\'))
            case '"': append(&out, byte('"'))
            case '\'': append(&out, byte('\''))
            case:
                lex_error(l, offset+i, "Invalid escape sequence: \\%c", esc)
                append(&out, esc)
        }

        i += 2
    }

	return string(out[:])
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
                r, w = utf8.decode_rune_in_string(l.source[l.read_offset:])
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
    column := 1
    i := l.line_offset
    for i < offset && i < len(l.source) {
        _, w := utf8.decode_rune_in_string(l.source[i:])
        if w <= 0 do break
        i += w
        column += 1
    }

	return Pos {
        file = l.path,
		offset = offset,
		line = u32(line),
		column = column,
	}
}