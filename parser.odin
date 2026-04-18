package wot

import "core:fmt"
import "core:strconv"
import os "core:os/os2"

Parser :: struct {
    lexer: ^Lexer,
    current: Token,
}

Program :: distinct BlockStmt

Stmt :: union {
    DeclrStmt,
    AssignStmt,
    ReturnStmt,
    PrintStmt,
    IfStmt,
    WhileStmt,
    BlockStmt,
    CallStmt
}

DeclrStmt :: struct {
    const: bool,
    id: Token,
    typename: string,
    value: Expr
}

AssignStmt :: struct {
    op: AssignOp,
    id: Token,
    value: Expr
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

ReturnStmt :: distinct Expr

PrintStmt :: distinct Expr

IfStmt :: struct {
    pos: Pos,
    condition: Expr,
    main_body,
    else_body: BlockStmt
}

WhileStmt :: struct {
    condition: Expr,
    body: BlockStmt
}

BlockStmt :: distinct []Stmt

CallStmt :: struct {
    id: Token,
    args: []Expr
}

Expr :: struct {
    pos: Pos,
    inner: ExprVal
}

ExprVal :: union {
    IntExpr,
    FloatExpr,
    StringExpr,
    BoolExpr,
    IdentifierExpr,
    ^BinaryExpr,
    ^UnaryExpr,
}

IntExpr         :: distinct i64
FloatExpr       :: distinct f64
StringExpr      :: distinct string
BoolExpr        :: distinct bool
IdentifierExpr  :: distinct string

BinaryExpr :: struct {
    op: BinaryOp,
    left:  Expr,
    right: Expr,
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

UnaryExpr :: struct {
    op: UnaryOp,
    expr: Expr
}

UnaryOp :: enum {
    Invalid,
    Not,
    Sub
}


init_parser :: proc(l: ^Lexer, p: ^Parser) {
    p.lexer = l
    p.current = scan_token(p.lexer)
    skip_stmt_separator(p)
}

skip_stmt_separator :: proc(p: ^Parser) {
    for p.current.kind == .Newline || p.current.kind == .Semicolon {
        p.current = scan_token(p.lexer)
    }
}

advance :: proc(p: ^Parser) {
    p.current = scan_token(p.lexer)
}

parse_program :: proc(p: ^Parser) -> Program {
    stmts: [dynamic]Stmt

    for p.current.kind != .EOF {
        stmt := parse_statement(p)
        if stmt == nil {
            fmt.eprintfln("Failed to parse file %w", p.lexer.path)
            os.exit(1)
        }
        // println_statement(stmt)
        append(&stmts, stmt)
        skip_stmt_separator(p)
        if p.current.kind == .CloseBrace do break
            
    }

    return cast(Program)stmts[:]
}

parse_error :: proc(pos: Pos, msg: string, args: ..any, hint := "", loc := #caller_location) {
	fmt.eprintf("%v Parse error: %s(%d:%d) ", loc, pos.file, pos.line, pos.column)
	fmt.eprintf(msg, ..args)
	fmt.eprintf("\n")
    if hint != "" {
        fmt.eprintfln("Hint: %v", hint)
    }
}

parse_statement :: proc(p: ^Parser, loc := #caller_location) -> Stmt {
    #partial switch p.current.kind {
        case .Id:
            return parse_identifier_stmt(p)
        case .Return:
            return parse_keyword_stmt(p)
        case .If:
            return parse_if_stmt(p)
        case .While:
            return parse_while_stmt(p)
        case .OpenBrace:
            return parse_block_stmt(p)
        case:
            parse_error(p.current.pos, "Unexpected token: %w", p.current.text, loc = loc)
            return nil
    }
}


parse_keyword_stmt :: proc(p: ^Parser) -> Stmt {
    keyword := p.current
    stmt: Stmt
    advance(p) // Consume keyword
    #partial switch keyword.kind {
        case .Return:
            stmt = ReturnStmt(parse_expression(p))
        case:
            parse_error(p.current.pos, "Not implemented: %v", keyword)
            return nil
    }
    return stmt
}

parse_if_stmt :: proc(p: ^Parser) -> Stmt {
    pos := p.current.pos
    advance(p)
    condition := parse_expression(p)
    skip_stmt_separator(p)

    body := parse_block_stmt(p)
    else_body: BlockStmt
    if p.current.kind == .Else {
        advance(p) // Consume ELSE
        else_body = parse_block_stmt(p)
    }
    stmt := IfStmt {
        pos = pos,
        condition = condition,
        main_body = BlockStmt(body),
        else_body = BlockStmt(else_body)
    }
    return stmt
}

parse_while_stmt :: proc(p: ^Parser) -> Stmt {
    advance(p) // Consume keyword
    condition := parse_expression(p)
    skip_stmt_separator(p)
    if p.current.kind != .OpenBrace {
        parse_error(p.current.pos, "Unexpected token: %v", p.current.text)
        fmt.eprintln("Did you mean: While <condition> {")
    }
    body := parse_block_stmt(p)

    stmt := WhileStmt {
        condition = condition,
        body      = BlockStmt(body)
    }
    return stmt
}

parse_block_stmt :: proc(p: ^Parser) -> BlockStmt {
    assert(p.current.kind == .OpenBrace)
    advance(p) // Consume {
    skip_stmt_separator(p)
    if p.current.kind == .CloseBrace do return nil

    stmts := parse_program(p)
    advance(p)

    assert(p.current.kind != .CloseBrace)
    return BlockStmt(stmts)
}

parse_identifier_stmt :: proc(p: ^Parser) -> Stmt {
    id := p.current
    advance(p)
    stmt: Stmt
    #partial switch p.current.kind {
    case .OpenParen:
        stmt = parse_call(p, id)
    case .Colon:
        stmt = parse_declaration(p, id)
    case .Eq, .AddEq, .SubEq, .MulEq, .DivEq, .ModEq:
        stmt = parse_assignment(p, id)
    case:
        parse_error(p.current.pos, "Invalid token: %v", p.current.text)
    }
    return stmt
}

parse_declaration :: proc(p: ^Parser, id: Token) -> Stmt {
    stmt: DeclrStmt
    stmt.id = id
    advance(p)
    #partial switch p.current.kind { // What happens after 1st colon
        case .Eq:
            advance(p)
            stmt.value = parse_expression(p)
            return stmt
        case .Colon:
            advance(p)
            stmt.const = true
            stmt.value = parse_expression(p)
        case .Id:
            stmt.typename = p.current.text
            advance(p)
            #partial switch p.current.kind {
                case .Eq:
                    advance(p)
                    stmt.value = parse_expression(p)
                case .Colon:
                    advance(p)
                    stmt.const = true
                    stmt.value = parse_expression(p)
                case .Newline:
                    break
                case:
                    parse_error(p.current.pos, "Unexpected token: %w", p.current.text)
            }
        case .Newline:
            parse_error(id.pos, "Incomplete declaration of %w", id.text)
            return nil
        case:
            parse_error(p.current.pos, "Unexpected token: %w", p.current.text)
    }
    return stmt
}

parse_call :: proc(p: ^Parser, id: Token) -> Stmt {
    args: [dynamic]Expr
    advance(p)
    if p.current.kind != .CloseParen {
        for {
            expr := parse_expression(p)
            if expr.inner == nil {
                parse_error(p.current.pos, "Invalid argument in call to '%v'", id.text)
                return nil
            }
            append(&args, expr)

            if p.current.kind == .CloseParen do break
            if p.current.kind != .Comma {
                parse_error(p.current.pos, "Expected ',' or ')' after argument in call to '%v'", id.text)
                return nil
            }

            advance(p) // consume ','
            if p.current.kind == .CloseParen {
                parse_error(p.current.pos, "Trailing comma is not allowed in call to '%v'", id.text)
                return nil
            }
        }
    }
    advance(p)
    stmt := CallStmt {
        id   = id,
        args = args[:]
    }
    return stmt
}

parse_assignment :: proc(p: ^Parser, id: Token) -> Stmt {
    op_token := p.current
    if !is_assign_token(op_token.kind) {
        parse_error(p.current.pos, "Invalid assignment token: %v", p.current.text)
    }
    advance(p) // consume assignment operator
    value := parse_expression(p)
    stmt := AssignStmt {
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


parse_expression :: proc(p: ^Parser) -> Expr {
    left := parse_and(p)
    for p.current.kind == .Or {
        op_token := p.current
        advance(p)

        right := parse_and(p)
        node := new(BinaryExpr)
        node^ = BinaryExpr{
            op = op_token_kind(op_token.kind),
            left = left,
            right = right
        }

        left = Expr{left.pos, node}
    }

    return left
}

parse_and :: proc(p: ^Parser) -> Expr {
    left := parse_eq(p)
    for p.current.kind == .And {
        op_token := p.current
        advance(p)

        right := parse_eq(p)
        node := new(BinaryExpr)
        node^ = BinaryExpr{
            op = op_token_kind(op_token.kind),
            left = left,
            right = right
        }

        left = Expr{left.pos, node}
    }

    return left
}

parse_eq :: proc(p: ^Parser) -> Expr {
    left := parse_cmp(p)
    for p.current.kind == .CmpEq || p.current.kind == .NotEq {
        op_token := p.current
        advance(p)

        right := parse_cmp(p)
        node := new(BinaryExpr)
        node^ = BinaryExpr{
            op = op_token_kind(op_token.kind),
            left = left,
            right = right
        }

        left = Expr{left.pos, node}
    }

    return left
}

parse_cmp :: proc(p: ^Parser) -> Expr {
    left := parse_additive(p)
    for p.current.kind == .Lt || p.current.kind == .Gt || 
        p.current.kind == .Gt_Eq || p.current.kind == .Lt_Eq {
        op_token := p.current
        advance(p)

        right := parse_additive(p)
        node := new(BinaryExpr)
        node^ = BinaryExpr{
            op = op_token_kind(op_token.kind),
            left = left,
            right = right
        }

        left = Expr{left.pos, node}
    }

    return left
}

parse_additive :: proc(p: ^Parser) -> Expr {
    left := parse_multiplicative(p)
    for p.current.kind == .Add || p.current.kind == .Sub {
        op_token := p.current
        advance(p)

        right := parse_multiplicative(p)
        node := new(BinaryExpr)
        node^ = BinaryExpr{
            op = op_token_kind(op_token.kind),
            left = left,
            right = right
        }

        left = Expr{left.pos, node}
    }

    return left
}

parse_multiplicative :: proc(p: ^Parser) -> Expr {
    left := parse_unary(p)
    for p.current.kind == .Mul || p.current.kind == .Div || p.current.kind == .Mod {
        op_token := p.current
        advance(p)

        right := parse_unary(p)
        node := new(BinaryExpr)
        node^ = BinaryExpr{
            op = op_token_kind(op_token.kind),
            left = left,
            right = right
        }

        left = Expr{left.pos, node}
    }

    return left
}

parse_unary :: proc(p: ^Parser) -> Expr {
    if p.current.kind == .Sub ||   // -x
       p.current.kind == .Not {   // !x

        op_token := p.current
        advance(p)

        operand := parse_unary(p) // recursion = right associative

        node := new(UnaryExpr)
        node^ = UnaryExpr{
            op = unary_op_token_kind(op_token.kind),
            expr = operand,
        }
        return Expr {op_token.pos, node}
    }

    return parse_factor(p)
}

parse_factor :: proc(p: ^Parser) -> Expr {
    pos := p.current.pos
    #partial switch p.current.kind {
    case .Int:
        val, ok := strconv.parse_int(p.current.text); assert(ok)
        node := IntExpr(val)
        advance(p)
        return Expr{pos, node}

    case .Float:
        val, ok := strconv.parse_f64(p.current.text); assert(ok)
        node := FloatExpr(val)
        advance(p)
        return Expr{pos, node}


    case .String:
        node := StringExpr(p.current.text)
        advance(p)
        return Expr{pos, node}
    
    case .True, .False:
        node := BoolExpr(p.current.kind == .True ? true : false)
        advance(p)
        return Expr{pos, node}

    case .Id:
        node := IdentifierExpr(p.current.text)
        advance(p)
        return Expr{pos, node}

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
        return {}
    }
}

println_statement :: proc(s: Stmt) {
    print_statement(s)
    fmt.println()
}

print_statement :: proc(s: Stmt) {
    print_expression :: proc(e: ExprVal) {
        bin_expr, bin_expr_ok := e.(^BinaryExpr)
        if bin_expr_ok {
            fmt.printf("(")
            print_expression(bin_expr.left.inner)
            fmt.printf(" %v ", to_string_binary_op(bin_expr.op))
            print_expression(bin_expr.right.inner)
            fmt.printf(")")
        } else {
            fmt.printf("%v", e)
        }
        
    }
    #partial switch stmt in s {
        case AssignStmt:
            fmt.print(stmt.id.text, stmt.op, "")
            print_expression(stmt.value.inner)
        case IfStmt:
            fmt.printf("If: ")
            print_expression(stmt.condition.inner)
            fmt.println()
            for sub_stmt in stmt.main_body do println_statement(sub_stmt)
            if stmt.else_body != nil {
                fmt.printf("Else:\n")
                for sub_stmt in stmt.else_body do println_statement(sub_stmt)
            }
            fmt.println("END")
        case ReturnStmt:
            fmt.print("RETURN ")
            print_expression(cast(ExprVal)stmt.inner)
        case DeclrStmt:
            fmt.printf("Declaration:\t%vid: %w\t, typename: %w,\t value: %v ", 
                stmt.const              ? "const\t" : "\t", stmt.id.text, 
                stmt.typename == ""     ? "None"   : stmt.typename, 
                stmt.value.inner == nil ? "none"   : fmt.aprint(eval(stmt.value), allocator = context.temp_allocator)
            )
        case CallStmt:
            fmt.printf("Called %w with args: ", stmt.id.text)
            for arg in stmt.args do print_expression(arg.inner)
    }
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

to_string_unary_op :: proc(op: UnaryOp) -> string {
    switch op {
        case .Invalid: return "INVALID"
        case .Not: return "!"
        case .Sub: return "-"

    }
    return ""
}