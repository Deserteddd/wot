#+feature dynamic-literals
package wot

import "core:fmt"
import "core:os"

SymbolId :: distinct u16

symbol_ids_by_name: map[string]SymbolId
symbol_names_by_id: [dynamic]string

symbol_intern :: proc(name: string) -> SymbolId {
    id, found := symbol_ids_by_name[name]
    if found do return id

    if symbol_ids_by_name == nil {
        symbol_ids_by_name = make_map(map[string]SymbolId)
    }

    // Reserve 0 as an invalid/unset symbol id.
    id = SymbolId(len(symbol_names_by_id) + 1)
    append(&symbol_names_by_id, name)
    symbol_ids_by_name[name] = id
    return id
}

symbol_name :: proc(id: SymbolId) -> string {
    i := int(id)
    if i <= 0 || i > len(symbol_names_by_id) {
        // fmt.eprintfln("Symbol id: %v doesn't exist", id)
        return ""
        // os.exit(1)
    }
    return symbol_names_by_id[i - 1]
}

Token :: struct {
	kind:   TokenKind,
    text:   string,
    sym:    SymbolId,
    pos:    Pos
}

Pos :: struct {
	file:   string,
    offset,
    column: int,
    line: u32
}

TokenKind :: enum u32 {
    Invalid,
    EOF,

    Id,
    Int,
    Float,
    Char,
    String,
    Fn,

    Ampersand,
    Asterisk,
    OpenParen,
    CloseParen,
    OpenBracket,
    CloseBracket,
    OpenBrace,
    CloseBrace,
    Period,
    Comma,
    Colon,
    Semicolon,
    Newline,

    Eq,
    Not,
    Add,
    Sub,
    Div,
    Mod,

    AddEq,
    SubEq,
    MulEq,
    DivEq,
    ModEq,

    CmpEq,
    NotEq,
    Lt,
    Gt,
    Lt_Eq,
    Gt_Eq,

    And,
    Or,
    
    If,
    Else,
    While,
    Return,
    True,
    False,
    Print,
}


keywords: map[string]TokenKind = {
    "return"  = .Return,
    "if"      = .If,
    "true"    = .True,
    "false"   = .False,
    "else"    = .Else,
    "while"   = .While,
    "fn"      = .Fn
}

