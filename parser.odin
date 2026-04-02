package wot

import "core:fmt"
import "core:strconv"
import "core:strings"

Program :: struct {
    statements: []Stmt
}


Stmt :: union {
    AssignStmt,
    AddEqStmt,
    SubEqStmt,
    MulEqStmt,
    DivEqStmt,
    ModEqStmt
}

AssignStmt :: distinct IdentifierStmt
AddEqStmt :: distinct IdentifierStmt
SubEqStmt :: distinct IdentifierStmt
MulEqStmt :: distinct IdentifierStmt
DivEqStmt :: distinct IdentifierStmt
ModEqStmt :: distinct IdentifierStmt

IdentifierStmt :: struct {
    id: string,
    value: ^Expr
}

Binary_Op :: enum {
    Invalid,
    Add,
    Sub,
    Mul,
    Div,
    Mod,
}

IntExpr :: distinct int


FloatExpr :: distinct f64


StringExpr :: distinct string

IdentifierExpr :: distinct string

BinaryExpr :: struct {
    op: Binary_Op,
    left:  ^Expr,
    right: ^Expr,
}

Expr :: union {
    IntExpr,
    FloatExpr,
    StringExpr,
    IdentifierExpr,
    BinaryExpr,
}

Parser :: struct {
    lexer: ^Lexer,
    current, previous: Token
}

init_parser :: proc(l: ^Lexer, p: ^Parser) {
    p.lexer = l
    p.current = scan_token(p.lexer)
}

advance :: proc(p: ^Parser) {
    p.previous = p.current
    p.current = scan_token(p.lexer)
}


parse_program :: proc(p: ^Parser) -> []^Stmt {
    stmts: [dynamic]^Stmt

    for p.current.kind != .EOF {
        stmt := parse_statement(p)
        print("%v", stmt^)
        append(&stmts, stmt)
    }

    return stmts[:]
}

parse_statement :: proc(p: ^Parser) -> ^Stmt {
    defer advance(p) //Consume newline or semicolon
    #partial switch p.current.kind {
        case .Id:
            return parse_identifier_statement(p)
        case:
            error(p.lexer, p.previous.pos.offset, "asd token")
            return nil
    }
}

parse_identifier_statement :: proc(p: ^Parser) -> ^Stmt {
    id := p.current.text
    advance(p)
    stmt := parse_assignment(p, id)
    return stmt
}

parse_assignment :: proc(p: ^Parser, id: string) -> ^Stmt {
    assign_type := p.current.kind
    if !is_assign_token(assign_type) {
        error(p.lexer, p.current.pos.offset, "Invalid token")
    }
    advance(p) // consume assignment operator
    value := parse_expression(p)
    stmt := new(Stmt)
    #partial switch assign_type {
        case .Eq: stmt^    = AssignStmt { id, value }
        case .AddEq: stmt^ = AddEqStmt  { id, value }
        case .SubEq: stmt^ = SubEqStmt  { id, value }
        case .MulEq: stmt^ = MulEqStmt  { id, value }
        case .DivEq: stmt^ = DivEqStmt  { id, value }
        case .ModEq: stmt^ = ModEqStmt  { id, value }
    }

    return stmt
}

parse_expression :: proc(p: ^Parser) -> ^Expr {
    left := parse_term(p)
    for p.current.kind == .Add || p.current.kind == .Sub {
        op_token := p.current
        advance(p)

        right := parse_term(p)
        node := new(Expr)
        node^ = BinaryExpr{
            op = op_token_kind(op_token.kind),
            left = left,
            right = right
        }

        left = node
    }

    return left
}

parse_term :: proc(p: ^Parser) -> ^Expr {
    left := parse_factor(p)
    for p.current.kind == .Mul || p.current.kind == .Div || p.current.kind == .Mod {
        op_token := p.current
        advance(p)

        right := parse_factor(p)

        node := new(Expr)

        node^ = BinaryExpr{
            op = op_token_kind(op_token.kind),
            left = left,
            right = right
        }

        left = node
    }

    return left
}

parse_factor :: proc(p: ^Parser) -> ^Expr {
    #partial switch p.current.kind {

    case .Int:
        node := new(Expr)
        val, ok := strconv.parse_int(p.current.text); assert(ok)
        node^ = IntExpr(val)
        advance(p)
        return node

    case .Float:
        node := new(Expr)
        val, ok := strconv.parse_f64(p.current.text); assert(ok)
        node^ = FloatExpr(val)
        advance(p)
        return node

    case .String:
        node := new(Expr)
        node^ = StringExpr(p.current.text)
        advance(p)
        return node

    case .Id:
        node := new(Expr)
        node^ = IdentifierExpr(p.current.text)
        advance(p)
        return node

    case .OpenParen:
        advance(p) // consume '('

        expr := parse_expression(p)

        if p.current.kind != .CloseParen {
            panic("expected ')'")
        }

        advance(p)
        return expr

    case:
        panic("unexpected token in expression")
    }
}

op_token_kind :: proc(t: TokenKind) -> Binary_Op {
    #partial switch t {
        case .Add: return .Add
        case .Sub: return .Sub
        case .Mul: return .Mul
        case .Div: return .Div
        case .Mod: return .Mod
        case:      return .Invalid
    }
}

is_assign_token :: proc(t: TokenKind) -> bool {
    return t == .Eq || t == .AddEq || t == .SubEq || 
    t == .MulEq || t == .DivEq || t == .ModEq
}

to_string_binary_op :: proc(op: Binary_Op) -> string {
    switch op {
        case .Invalid: return "INVALID"
        case .Add: return "+"
        case .Sub: return "-"
        case .Mul: return "*"
        case .Div: return "/"
        case .Mod: return "%"
    }
    return ""
}