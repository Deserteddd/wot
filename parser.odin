package wot

import "core:fmt"
import "core:strconv"
import os "core:os/os2"

Program :: struct {
    statements: []Stmt
}


Stmt :: union {
    AssignStmt,
    ReturnStmt,
    PrintStmt,
    IfStmt,
    WhileStmt,
    BlockStmt,
}

AssignStmt :: struct {
    op: AssignOp,
    id: Token,
    value: ^Expr
}

ReturnStmt :: distinct ^Expr

PrintStmt :: distinct ^Expr

IfStmt :: struct {
    condition: ^Expr,
    main_body,
    else_body: BlockStmt
}

BlockStmt :: distinct []^Stmt

WhileStmt :: struct {
    condition: ^Expr,
    body: BlockStmt
}


AssignOp :: enum {
    Invalid,
    Assign,
    AddEq,
    SubEq,
    MulEq,
    DivEq,
    ModEq,
}

Expr :: union {
    IntExpr,
    FloatExpr,
    StringExpr,
    BoolExpr,
    IdentifierExpr,
    BinaryExpr,
    UnaryExpr,
}

BinaryOp :: enum {
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

UnaryOp :: enum {
    Invalid,
    Not,
    Sub
}

IntExpr         :: distinct i64
FloatExpr       :: distinct f64
BoolExpr        :: distinct bool
StringExpr      :: distinct string
IdentifierExpr  :: distinct string

BinaryExpr :: struct {
    op: BinaryOp,
    left:  ^Expr,
    right: ^Expr,
}

UnaryExpr :: struct {
    op: UnaryOp,
    expr: ^Expr
}

Parser :: struct {
    lexer: ^Lexer,
    current: Token,
    names: [dynamic]string
}

init_parser :: proc(l: ^Lexer, p: ^Parser) {
    p.lexer = l
    p.current = scan_token(p.lexer)
    skip_newline(p)
}

skip_newline :: proc(p: ^Parser) {
    for p.current.kind == .Newline {
        p.current = scan_token(p.lexer)
    }
}

advance :: proc(p: ^Parser) {
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
        skip_newline(p)
        if p.current.kind == .CloseBrace do return stmts[:]
    }

    return stmts[:]
}

parse_error :: proc(pos: Pos, msg: string, args: ..any, loc := #caller_location) {
	fmt.eprintf("%v Parse error: %s(%d:%d) ", loc, pos.file, pos.line, pos.column)
	fmt.eprintf(msg, ..args)
	fmt.eprintf("\n")
}

parse_statement :: proc(p: ^Parser, loc := #caller_location) -> ^Stmt {
    defer advance(p) //Consume newline or semicolon
    #partial switch p.current.kind {
        case .Id:
            return parse_identifier_stmt(p)
        case .Return, .Print:
            return parse_keyword_stmt(p)
        case .If:
            return parse_if_stmt(p)
        case .While:
            return parse_while_stmt(p)
        case:
            parse_error(p.current.pos, "Unexpected token: %w", p.current.text, loc = loc)
            return nil
    }
}


parse_keyword_stmt :: proc(p: ^Parser) -> ^Stmt {
    keyword := p.current
    stmt := new(Stmt)
    advance(p) // Consume keyword
    #partial switch keyword.kind {
        case .Return:
            stmt^ = ReturnStmt(parse_expression(p))
        case .Print:
            stmt^ = PrintStmt(parse_expression(p))
        case:
            parse_error(p.current.pos, "Not implemented: %v", keyword)
            return nil
    }
    return stmt
}

parse_if_stmt :: proc(p: ^Parser) -> ^Stmt {
    advance(p)
    condition := parse_expression(p)
    skip_newline(p)
    advance(p) // Consume {
    skip_newline(p)
    body := parse_block_stmt(p)
    else_body: []^Stmt
    if p.current.kind == .Else {
        advance(p) // Consume ELSE
        advance(p) // Consume {
        skip_newline(p)
        else_body = parse_block_stmt(p)
    }
    stmt := new(Stmt)
    stmt^ = IfStmt {
        condition = condition,
        main_body = BlockStmt(body),
        else_body = BlockStmt(else_body)
    }
    return stmt
}

parse_while_stmt :: proc(p: ^Parser) -> ^Stmt {
    advance(p) // Consume keyword
    condition := parse_expression(p)
    skip_newline(p)
    advance(p) // Consume {
    skip_newline(p)
    body := parse_block_stmt(p)
    stmt := new(Stmt)
    stmt^ = WhileStmt {
        condition = condition,
        body      = BlockStmt(body)
    }
    return stmt
}

parse_block_stmt :: proc(p: ^Parser) -> []^Stmt {
    if p.current.kind == .CloseBrace do return nil
    stmts := parse_program(p)
    advance(p) // consume }

    return stmts
}

parse_identifier_stmt :: proc(p: ^Parser) -> ^Stmt {
    id := p.current
    advance(p)
    if p.current.kind == .Eq {
        if !is_declared(p, id.text) {
            append(&p.names, id.text)
        }
    } else if !is_declared(p, id.text) {
        parse_error(p.current.pos, "Undeclared name: %w", id)
        return nil
    }
    stmt := parse_assignment(p, id)
    return stmt
}

parse_assignment :: proc(p: ^Parser, id: Token) -> ^Stmt {
    op_token := p.current
    if !is_assign_token(op_token.kind) {
        parse_error(p.current.pos, "Invalid token: %v", p.current.text)
    }
    advance(p) // consume assignment operator
    value := parse_expression(p)
    stmt := new(Stmt)
    stmt^ = AssignStmt {
        op = get_assign_op(op_token),
        id = id,
        value = value
    }


    return stmt
}

get_assign_op :: proc(token: Token) -> AssignOp{
    #partial switch token.kind {
        case .Eq:       return .Assign
        case .AddEq:    return .AddEq
        case .SubEq:    return .SubEq
        case .MulEq:    return .MulEq
        case .DivEq:    return .DivEq
        case .ModEq:    return .ModEq
        case:
            parse_error(token.pos, "Invalid assignment: %v", token.text)
            return .Invalid
    }
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
    left := parse_unary(p)
    for p.current.kind == .Mul || p.current.kind == .Div || p.current.kind == .Mod {
        op_token := p.current
        advance(p)

        right := parse_unary(p)
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

parse_unary :: proc(p: ^Parser) -> ^Expr {
    if p.current.kind == .Sub ||   // -x
       p.current.kind == .Not {   // !x

        op_token := p.current
        advance(p)

        operand := parse_unary(p) // recursion = right associative

        node := new(Expr)
        node^ = UnaryExpr{
            op = unary_op_token_kind(op_token.kind),
            expr = operand,
        }
        return node
    }

    return parse_factor(p)
}

parse_factor :: proc(p: ^Parser) -> ^Expr {
    // parse_factor_calls += 1
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
            parse_error(p.current.pos, "Undeclared name: %w", p.current.text)
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
        parse_error(p.current.pos, "Invalid Token: %w", p.current.text)
        return nil
    }
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
    #partial switch stmt in s {
        case AssignStmt:
            fmt.print(stmt.id.text, stmt.op, "")
            print_expression(stmt.value)
        case IfStmt:
            fmt.printf("If: ")
            print_expression(stmt.condition)
            fmt.println()
            for sub_stmt in stmt.main_body do println_statement(sub_stmt^)
            if stmt.else_body != nil {
                fmt.printf("Else:\n")
                for sub_stmt in stmt.else_body do println_statement(sub_stmt^)
            }
            fmt.println("END")
        case PrintStmt:
            fmt.println("PRINT:", stmt^)

    }
}



is_declared :: proc(p: ^Parser, name: string) -> bool {
    for n in p.names {
        if n == name do return true
    }
    return false
}

op_token_kind :: proc(t: TokenKind) -> BinaryOp {
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

unary_op_token_kind :: proc(t: TokenKind) -> UnaryOp {
    #partial switch t {
        case .Not: return .Not
        case .Sub: return .Sub
        case: return .Invalid
    }
}

is_assign_token :: proc(t: TokenKind) -> bool {
    return t == .Eq || t == .AddEq || t == .SubEq || 
    t == .MulEq || t == .DivEq || t == .ModEq
}

to_string_binary_op :: proc(op: BinaryOp) -> string {
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