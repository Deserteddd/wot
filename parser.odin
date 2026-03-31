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
        // print_statement(stmt)
        append(&stmts, stmt)
    }

    return stmts[:]
}

print_statement :: proc(s: ^Stmt) {
    indent :: proc(n: int) -> string {
        b := strings.builder_make(context.temp_allocator)
        for i in 0..<n {
            strings.write_rune(&b, '\t')
        }
        return strings.to_string(b)
    }
    print_expression :: proc(e: ^Expr) {
        fmt.println(e)
    }
    #partial switch &v in s {
    case AssignStmt:
        fmt.printf("Assign: %w = ", v.name)
        print_expression(v.value)
    }
}

parse_statement :: proc(p: ^Parser) -> ^Stmt {
    defer advance(p) //Consume newline or semicolon
    #partial switch p.current.kind {
        case .Id:
            return parse_identifier_statement(p)
        case:
            error(p.lexer, p.lexer.offset, "asd token")
            return nil
    }
}

parse_identifier_statement :: proc(p: ^Parser) -> ^Stmt {
    name := p.current.text
    advance(p)
    assert(p.current.text == "=")
    #partial switch p.current.kind {
        case .Eq:
            stmt := parse_assignment(p, name)
            return stmt
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
    stmt^ = AssignStmt{
        name = name, value = value
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
            op = op_token.kind == .Add ? .Add : .Sub,
            left = left,
            right = right
        }

        left = node
    }

    return left
}

parse_term :: proc(p: ^Parser) -> ^Expr {
    left := parse_factor(p)
    for p.current.kind == .Mul || p.current.kind == .Div {
        op_token := p.current
        advance(p)

        right := parse_factor(p)

        node := new(Expr)

        node^ = BinaryExpr{
            op = op_token.kind == .Mul ? .Mul : .Div,
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