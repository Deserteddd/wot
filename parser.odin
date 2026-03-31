package wot

import "core:fmt"
import "core:strconv"

Program :: struct {
    statements: []Stmt
}


Stmt :: union {
    AssignStmt,
    AddEqStmt,
}

AssignStmt :: struct {
    name: string,
    value: ^Expr,
}

AddEqStmt :: struct {
    name: string,
    value: ^Expr,
}

Expr_Kind :: enum {
    Int,
    Float,
    String,
    Identifier,
    Binary,
}

Binary_Op :: enum {
    Add,
    Sub,
    Mul,
    Div,
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
    current: Token,
}

init_parser :: proc(l: ^Lexer, p: ^Parser) {
    p.lexer = l
    p.current = scan_token(p.lexer)
}

advance :: proc(p: ^Parser) {
    p.current = scan_token(p.lexer)
}


parse_program :: proc(p: ^Parser) -> []^Stmt {
    stmts: [dynamic]^Stmt

    for p.current.kind != .EOF {
        stmt := parse_statement(p)
        append(&stmts, stmt)
    }

    return stmts[:]
}

parse_statement :: proc(p: ^Parser) -> ^Stmt {
    #partial switch p.current.kind {
        case .Id:
            return parse_identifier_statement(p)
        case:
            error(p.lexer, p.lexer.offset, "Unexpected token")
            return nil
    }
}

parse_identifier_statement :: proc(p: ^Parser) -> ^Stmt {
    name := p.current.text
    advance(p)
    fmt.println(name)
    #partial switch p.current.kind {
        case .Eq:
            return parse_assignment(p, name)
        case:
            panic("Only assign statements are supported")
    }
    return nil
}

parse_assignment :: proc(p: ^Parser, name: string) -> ^Stmt {
    assert(p.current.kind == .Eq)
    advance(p) // consume "="
    value := parse_expression(p)

    stmt := new(Stmt)
    stmt^ = Stmt(AssignStmt{
        name = name, value = value
    })

    return stmt
}

parse_expression :: proc(p: ^Parser) -> ^Expr {
    left := parse_term(p)
    for p.current.kind == .Add || p.current.kind == .Sub {
        op_token := p.current
        advance(p)

        right := parse_term(p)

        node := new(BinaryExpr)
        node.op = op_token.kind == .Add ? .Add : .Sub
        node.left = left
        node.right = right

        left = cast(^Expr)node
    }

    return left
}

parse_term :: proc(p: ^Parser) -> ^Expr {
    left := parse_factor(p)

    for p.current.kind == .Mul || p.current.kind == .Div {
        op_token := p.current
        advance(p)

        right := parse_factor(p)

        node := new(BinaryExpr)
        node.op = op_token.kind == .Mul ? .Mul : .Div
        node.left = left
        node.right = right

        left = cast(^Expr)node
    }

    return left
}

parse_factor :: proc(p: ^Parser) -> ^Expr {
    #partial switch p.current.kind {

    case .Int:
        node := new(IntExpr)
        val, ok := strconv.parse_int(p.current.text); assert(ok)
        node^ = IntExpr(val)
        advance(p)
        return cast(^Expr)node

    case .Float:
        node := new(FloatExpr)
        val, ok := strconv.parse_f64(p.current.text); assert(ok)
        node^ = FloatExpr(val)
        advance(p)
        return cast(^Expr)node

    case .String:
        node := new(StringExpr)
        node^ = StringExpr(p.current.text)
        advance(p)
        return cast(^Expr)node

    case .Id:
        node := new(IdentifierExpr)
        node^ = IdentifierExpr(p.current.text)
        advance(p)
        return cast(^Expr)node

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