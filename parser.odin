package wot

import "core:fmt"
import "core:strconv"
import os "core:os/os2"

Program :: struct {
    statements: []Stmt
}

StmtType :: enum {
    Assign,
    AddEq,
    SubEq,
    MulEq,
    DivEq,
    ModEq,
    Return,
    If,
    Print,
}

Stmt :: struct {
    type: StmtType,
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
    Or,
    And,
    CmpEq,
    NotEq,
    Lt,
    Gt,
    Lt_Eq,
    Gt_Eq,
}

IntExpr         :: distinct int
FloatExpr       :: distinct f64
BoolExpr        :: distinct bool
StringExpr      :: distinct string
IdentifierExpr  :: distinct string

BinaryExpr :: struct {
    op: Binary_Op,
    left:  ^Expr,
    right: ^Expr,
}

Expr :: union {
    IntExpr,
    FloatExpr,
    StringExpr,
    BoolExpr,
    IdentifierExpr,
    BinaryExpr,
}

Parser :: struct {
    lexer: ^Lexer,
    current, previous: Token,
    names: [dynamic]string
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
        if stmt == nil {
            fmt.eprintfln("Failed to parse file %w", p.lexer.path)
            os.exit(1)
        }
        // println_statement(stmt^)
        append(&stmts, stmt)
        for p.current.kind == .Newline do advance(p)
    }

    return stmts[:]
}

println_statement :: proc(s: Stmt) {
    print_statement(s)
    fmt.println()
}

print_statement :: proc(s: Stmt) {
    print_expression :: proc(e: ^Expr) {
        bin_expr, bin_expr_ok := e.(BinaryExpr)
        if bin_expr_ok {
            fmt.printf("(")
            print_expression(bin_expr.left)
            fmt.printf(" %v ", to_string_binary_op(bin_expr.op))
            print_expression(bin_expr.right)
            fmt.printf(")")
        } else {
            fmt.printf("%v", e^)
        }
        
    }
    if s.type != .Return do fmt.printf("%v ", s.id)
    fmt.printf("%v ", s.type)
    #partial switch &v in s.value {
        case BinaryExpr:
            print_expression(v.left)
            fmt.printf(" %v ", to_string_binary_op(v.op))
            print_expression(v.right)
        case:
            print_expression(&v)
    }
}

parse_statement :: proc(p: ^Parser) -> ^Stmt {
    defer advance(p) //Consume newline or semicolon
    #partial switch p.current.kind {
        case .Id:
            return parse_identifier_statement(p)
        case .Return, .Print:
            return parse_keyword_stmt(p)
        case:
            return nil
    }
}


parse_keyword_stmt :: proc(p: ^Parser) -> ^Stmt {
    keyword := p.current.kind
    stmt := new(Stmt)
    #partial switch keyword {
        case .Return:
            stmt.id = "return"
            stmt.type = .Return
        case .Print:
            stmt.id = "print"
            stmt.type = .Print
        case:
            error(p.lexer, p.current.pos.offset, "Not implemented: %v", keyword)
    }
    advance(p) // Consume keyword
    stmt.value = parse_expression(p)
    return stmt
}

parse_identifier_statement :: proc(p: ^Parser) -> ^Stmt {
    id := p.current.text
    advance(p)
    if p.current.kind == .Eq {
        if !is_declared(p, id) {
            append(&p.names, id)
        }
    } else if !is_declared(p, id) {
        error(p.lexer, p.current.pos.offset, "Undeclared name: %w", id)
        return nil
    }
    stmt := parse_assignment(p, id)
    return stmt
}

parse_assignment :: proc(p: ^Parser, id: string) -> ^Stmt {
    assign_type := p.current.kind
    if !is_assign_token(assign_type) {
        error(p.lexer, p.current.pos.offset, "Invalid token: %v", p.current.text)
    }
    advance(p) // consume assignment operator
    value := parse_expression(p)
    stmt := new(Stmt)
    stmt.id = id
    stmt.value = value
    #partial switch assign_type {
        case .Eq:    stmt.type = .Assign
        case .AddEq: stmt.type = .AddEq
        case .SubEq: stmt.type = .SubEq
        case .MulEq: stmt.type = .MulEq
        case .DivEq: stmt.type = .DivEq
        case .ModEq: stmt.type = .ModEq
    }

    return stmt
}


parse_expression :: proc(p: ^Parser) -> ^Expr {
    left := parse_and(p)
    for p.current.kind == .Or {
        op_token := p.current
        advance(p)

        right := parse_and(p)
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

parse_and :: proc(p: ^Parser) -> ^Expr {
    left := parse_eq(p)
    for p.current.kind == .And {
        op_token := p.current
        advance(p)

        right := parse_eq(p)
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

parse_eq :: proc(p: ^Parser) -> ^Expr {
    left := parse_cmp(p)
    for p.current.kind == .CmpEq || p.current.kind == .NotEq {
        op_token := p.current
        advance(p)

        right := parse_cmp(p)
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

parse_cmp :: proc(p: ^Parser) -> ^Expr {
    left := parse_additive(p)
    for p.current.kind == .Lt || p.current.kind == .Gt || 
        p.current.kind == .Gt_Eq || p.current.kind == .Lt_Eq {
        op_token := p.current
        advance(p)

        right := parse_additive(p)
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

parse_additive :: proc(p: ^Parser) -> ^Expr {
    left := parse_multiplicative(p)
    for p.current.kind == .Add || p.current.kind == .Sub {
        op_token := p.current
        advance(p)

        right := parse_multiplicative(p)
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

parse_multiplicative :: proc(p: ^Parser) -> ^Expr {
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
    
    case .True, .False:
        node := new(Expr)
        node^ = BoolExpr(p.current.kind == .True ? true : false)
        advance(p)
        return node

    case .Id:
        if !is_declared(p, p.current.text) {
            error(p.lexer, p.current.pos.offset, "Undeclared name: %w", p.current.text)
            return nil
        }
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
        error(p.lexer, p.current.pos.offset, "Invalid Token: %w", p.current.text)
        return nil
    }
}

is_declared :: proc(p: ^Parser, name: string) -> bool {
    for n in p.names {
        if n == name do return true
    }
    return false
}

op_token_kind :: proc(t: TokenKind) -> Binary_Op {
    #partial switch t {
        case .Add: return .Add
        case .Sub: return .Sub
        case .Mul: return .Mul
        case .Div: return .Div
        case .Mod: return .Mod
        case .Or:  return .Or
        case .And: return .And
        case .CmpEq:    return .CmpEq
        case .NotEq:    return .NotEq
        case .Lt:       return .Lt
        case .Gt:       return .Gt
        case .Lt_Eq:    return .Lt_Eq
        case .Gt_Eq:    return .Gt_Eq
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
        case .CmpEq: return "=="
        case .NotEq: return "!="
        case .Lt:    return "<"
        case .Gt:    return ">"
        case .Lt_Eq: return "<="
        case .Gt_Eq: return ">="
        case .Or:    return "||"
        case .And:   return "&&"
    }
    return ""
}