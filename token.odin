#+feature dynamic-literals
package wot

Token :: struct {
	kind:   TokenKind,
    text:   string,
    pos:    Pos
}

Pos :: struct {
    offset, line, column: int
}

TokenKind :: enum u32 {
    Invalid,
    EOF,

    Id,
    Int,
    Float,
    Char,
    String,

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
    Mul,
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
    
    Return,
}


keywords: map[string]TokenKind = {
    "return"  = .Return,
}