package wot

import "core:fmt"
import "core:strconv"
import os "core:os/os2"
import "core:strings"


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

    id: Token,
    variant: union {
        VarDeclrStmt,
        FnDeclrStmt
    }
}

VarDeclrStmt :: struct {
    const: bool,
    type: string,
    value: Expr
}

FnDeclrStmt :: struct {
    params: []ParamInfo,
    return_type: string,
    body: BlockStmt
}

ParamInfo :: struct {
    id: Token,
    type: string
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
    NoneExpr,
    IntExpr,
    FloatExpr,
    StringExpr,
    BoolExpr,
    IdentifierExpr,
    ^CallExpr,
    ^BinaryExpr,
    ^UnaryExpr,
}


NoneExpr        :: distinct byte
IntExpr         :: distinct i64
FloatExpr       :: distinct f64
StringExpr      :: strings.Builder
BoolExpr        :: distinct bool
IdentifierExpr  :: distinct string

CallExpr :: struct {
    callee: Expr,
    args: []Expr,
}

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
        advance(p)
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

parse_error :: proc{parse_error_std, parse_error_custom}

parse_error_std :: proc(p: ^Parser, msg: string, loc := #caller_location) {
    pos := p.current.pos
    if ODIN_DEBUG {
        fmt.eprintf("%v ", loc)
    }
	fmt.eprintf("Parse error at %s(%d:%d): ", pos.file, pos.line, pos.column)
	fmt.eprint(msg)
    if p.current.text != "" {
        fmt.eprintf(" %w", p.current.text)
    }
	fmt.eprintf("\n")
}

parse_error_custom :: proc(pos: Pos, msg: string, args: ..any, hint := "", loc := #caller_location) {
    if ODIN_DEBUG {
        fmt.eprintf("%v ", loc)
    }
	fmt.eprintf("Parse error at %s(%d:%d): ", pos.file, pos.line, pos.column)
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
            parse_error(p, "Unexpected token:")
            return nil
    }
}


parse_keyword_stmt :: proc(p: ^Parser) -> Stmt {
    keyword := p.current
    stmt: Stmt
    advance(p) // Consume keyword
    #partial switch keyword.kind {
        case .Return:
            if p.current.kind == .Newline do stmt = ReturnStmt {
                pos = keyword.pos,
                inner = NoneExpr(0),
            }; else do stmt = ReturnStmt(parse_expression(p))
        case:
            parse_error(p, "Not implemented:")
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
        parse_error(p, "Unexpected token:")
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
        parse_error(p, "Invalid token:")
    }
    return stmt
}

parse_declaration :: proc(p: ^Parser, id: Token) -> Stmt {
    stmt: DeclrStmt
    stmt.id = id
    advance(p)
    #partial switch p.current.kind { // after 1st colon
        case .Eq:
            advance(p)
            if p.current.kind == .Fn {
                parse_error(id.pos, "Functions must be declared as constant: \033[1m%v :: fn(..\033[0m", id.text)
                return nil
            }
            value := parse_expression(p)
            if value.inner == nil do return nil
            stmt.variant = VarDeclrStmt {
                const = false,
                value = value
            }
            return stmt
        case .Colon:
            advance(p)
            #partial switch p.current.kind {
                case .Fn:
                    fn_declr_stmt, ok := parse_fn(p, id)
                    if !ok do return nil
                    stmt.variant = fn_declr_stmt
                case:
                    value := parse_expression(p)
                    if value.inner == nil do return nil
                    stmt.variant = VarDeclrStmt {
                        const = true,
                        value = value
                    }
            }
        case .Id:
            type := p.current
            advance(p)
            #partial switch p.current.kind {
                case .Eq:
                    advance(p)
                    value := parse_expression(p)
                    if value.inner == nil do return nil
                    stmt.variant = VarDeclrStmt {
                        const = false,
                        type = type.text,
                        value = value
                    }
                case .Colon:
                    advance(p)
                    value := parse_expression(p)
                    if value.inner == nil do return nil
                    stmt.variant = VarDeclrStmt {
                        const = true,
                        type = type.text,
                        value = value
                    }
                case .Newline:
                    value: ExprVal
                    #partial switch type_from_string(type.text) {
                        case .Bool:  value = BoolExpr(false)
                        case .Int:   value = IntExpr(0)
                        case .Float: value = FloatExpr(0)
                        case .String:
                            b: strings.Builder
                            strings.builder_init(&b)
                            value = StringExpr(b)
                        case:
                            parse_error_custom(type.pos, "Undeclared type: %v", type.text)
                    }
                    stmt.variant = VarDeclrStmt {
                        const = false,
                        type = type.text,
                        value = Expr {
                            pos = stmt.id.pos,
                            inner = ExprVal(value)
                        }
                    }
                case:
                    parse_error(p, "Unexpected token:")
            }
        case .Newline:
            parse_error_custom(stmt.id.pos, "Incomplete declaration of %w", stmt.id.text)
            return nil
        case:
            parse_error(p, "Unexpected token:")
    }
    return stmt
}

parse_fn :: proc(p: ^Parser, id: Token) -> (FnDeclrStmt, bool) {
    stmt: FnDeclrStmt
    assert(p.current.kind == .Fn)

    advance(p)
    if p.current.kind != .OpenParen {
        parse_error(p, "Expected \"(\", got:")
        return {}, false
    }

    advance(p)
    params: []ParamInfo
    ok: bool
    if p.current.kind != .CloseParen {
        params, ok = parse_params(p)
        if !ok do return {}, false

    } else do advance(p)
    stmt.params = params

    #partial switch p.current.kind {
        case .Sub:
            advance(p)
            if p.current.kind != .Gt {
                parse_error(p, "Expected \">\", got:")
                return {}, false
            } else {
                advance(p)
                if p.current.kind != .Id {
                    parse_error(p, "Expected a type name, got:")
                    return {}, false
                }
                stmt.return_type = p.current.text
                advance(p)
                if p.current.kind != .OpenBrace {
                    parse_error(p, "Expected {, got:")
                    return {}, false
                }
                stmt.body = parse_block_stmt(p)
            }
        case .OpenBrace:
            stmt.body = parse_block_stmt(p)

        case:
            parse_error(p, "Invalid token:")
            return {}, false
    }

    return stmt, true
}

parse_params :: proc(p: ^Parser) -> ([]ParamInfo, bool) {
    parse_param :: proc(p: ^Parser) -> (ParamInfo, bool) {
        info: ParamInfo
        
        if p.current.kind != .Id {
            parse_error(p, "Expected an identifier, got:")
            return {}, false
        }
        info.id = p.current

        advance(p)
        if p.current.kind != .Colon {
            parse_error(p, "Expected a colon, got:")
            return {}, false
        }

        advance(p)
        if p.current.kind != .Id {
            parse_error(p, "Expected a type name, got:")
            return {}, false
        }
        info.type = p.current.text
        advance(p)

        return info, true
    }

    params: [dynamic]ParamInfo
    for {
        param, ok := parse_param(p)
        if !ok do return nil, false; else do append(&params, param)

        if p.current.kind == .CloseParen {
            advance(p)
            return params[:], true
        } else if p.current.kind == .Comma {
            advance(p)
        }
        
    }
    return params[:], true
}

parse_call :: proc(p: ^Parser, id: Token) -> Stmt {
    args, ok := parse_call_args(p, id.text)
    if !ok do return nil
    stmt := CallStmt {
        id   = id,
        args = args
    }
    return stmt
}

parse_call_args :: proc(p: ^Parser, callee_name: string) -> ([]Expr, bool) {
    args: [dynamic]Expr

    assert(p.current.kind == .OpenParen)
    advance(p) // consume '('

    if p.current.kind != .CloseParen {
        for {
            expr := parse_expression(p)
            if expr.inner == nil {
                parse_error(p, "Invalid argument in call to")
                fmt.eprintfln("%v()", callee_name)
                return nil, false
            }
            append(&args, expr)

            if p.current.kind == .CloseParen do break
            if p.current.kind != .Comma {
                parse_error(p, "Expected ',' or ')' after argument in call to")
                fmt.eprintfln("%v()", callee_name)
                return nil, false
            }

            advance(p) // consume ','
            if p.current.kind == .CloseParen {
                parse_error(p, "Trailing comma is not allowed in call to")
                fmt.eprintfln("%v()", callee_name)
                return nil, false
            }
        }
    }

    advance(p) // consume ')'
    return args[:], true
}

parse_assignment :: proc(p: ^Parser, id: Token) -> Stmt {
    op_token := p.current
    if !is_assign_token(op_token.kind) {
        parse_error(p, "Invalid assignment token:")
    }
    op := get_assign_op(p, op_token)
    advance(p) // consume assignment operator
    value := parse_expression(p)
    stmt := AssignStmt {
        op = op,
        id = id,
        value = value
    }


    return stmt
}

get_assign_op :: proc(p: ^Parser, token: Token) -> AssignOp{
    #partial switch token.kind {
        case .Eq:       return .Assign
        case .AddEq:    return .AddEq
        case .SubEq:    return .SubEq
        case .MulEq:    return .MulEq
        case .DivEq:    return .DivEq
        case .ModEq:    return .ModEq
        case:
            parse_error(p, "Invalid assignment:")
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

    return parse_call_expr(p)
}

parse_call_expr :: proc(p: ^Parser) -> Expr {
    expr := parse_factor(p)

    for p.current.kind == .OpenParen {
        args, ok := parse_call_args(p, "expression")
        if !ok do return {}

        node := new(CallExpr)
        node^ = CallExpr {
            callee = expr,
            args = args,
        }

        expr = Expr{expr.pos, node}
    }

    return expr
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
        b: strings.Builder
        strings.builder_init(&b)
        strings.write_string(&b, p.current.text)
        node := StringExpr(b)
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
        parse_error(p, "Invalid Token:")
        return {}
    }
}

println_statement :: proc(s: Stmt) {
    print_expression :: proc(e: ExprVal) {
        bin_expr, bin_expr_ok := e.(^BinaryExpr)
        if bin_expr_ok {
            fmt.printf("(")
            print_expression(bin_expr.left.inner)
            fmt.printf(" %v ", to_string_binary_op(bin_expr.op))
            print_expression(bin_expr.right.inner)
            fmt.printf(")")
        } else if call_expr, call_expr_ok := e.(^CallExpr); call_expr_ok {
            print_expression(call_expr.callee.inner)
            fmt.printf("(")
            for arg, i in call_expr.args {
                if i > 0 do fmt.printf(", ")
                print_expression(arg.inner)
            }
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
            print_expression(stmt.inner)
        case DeclrStmt:
            switch d in stmt.variant {
                case VarDeclrStmt:
                    fmt.printf("Var:\t%vid: %w\t, typename: %w,\t value: %v ", 
                        d.const              ? "const\t" : "\t", stmt.id.text, 
                        d.type == ""         ? "None"    : d.type, 
                        d.value.inner == nil ? "none"    : fmt.aprint(eval(d.value), allocator = context.temp_allocator)
                    )
                case FnDeclrStmt:
                    fmt.printf("Fn:\t%v", d)
            }
        case CallStmt:
            fmt.printf("Called %w with args: ", stmt.id.text)
            for arg in stmt.args do print_expression(arg.inner)
    }
    fmt.println()
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