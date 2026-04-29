package wot

import "core:fmt"
import "core:strconv"
import "core:os"
import "core:strings"


Parser :: struct {
    lexer: ^Lexer,
    current: Token,
}

Stmt :: union {
    DeclrStmt,
    AssignStmt,
    ReturnStmt,
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
    type: Type,
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
    value: Expr,
    deref: bool
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


IfStmt :: struct {
    pos: Pos,
    condition: Expr,
    main_body,
    else_body: BlockStmt
}

WhileStmt :: struct {
    pos: Pos,
    condition: Expr,
    body: BlockStmt
}

BlockStmt :: distinct []Stmt

CallStmt :: struct {
    id: Token,
    args: []Expr
}


Expr :: struct {
    id: SymbolId,
    pos: Pos,

    variant: union {
        None,
        Int,
        Float,
        Bool,
        Char,
        Identifier,
        RefExpr,
        DerefExpr,
        ^CallExpr,
        ^BinaryExpr,
        ^UnaryExpr,
    }
}


DerefExpr :: struct {
    id: SymbolId,
    expr: ^Expr,
}
RefExpr :: struct {
    id: SymbolId,
    expr: ^Expr,
}

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

skip_newline :: proc(p: ^Parser) {
    for p.current.kind == .Newline {
        advance(p)
    }
}

advance :: proc(p: ^Parser) {
    p.current = scan_token(p.lexer)
}

parse_error :: proc{parse_error_std, parse_error_custom}

parse_error_std :: proc(p: ^Parser, msg: string, loc := #caller_location) {
    pos := p.current.pos
    if ODIN_DEBUG {
        fmt.eprintf("%v ", loc)
    }
	fmt.printf("Parse error at %s(%d:%d): ", pos.file, pos.line, pos.column)
	fmt.eprint(msg)
    if p.current.text != "" {
        fmt.eprintf(" %w (%v)", p.current.text, p.current.kind)
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
                keyword.sym,
                keyword.pos,
                None {},
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
    pos := p.current.pos
    advance(p) // Consume keyword
    condition := parse_expression(p)
    skip_stmt_separator(p)
    if p.current.kind != .OpenBrace {
        parse_error(p, "Unexpected token:")
        fmt.eprintln("Did you mean: While <condition> {")
    }
    body := parse_block_stmt(p)

    stmt := WhileStmt {
        pos       = pos,
        condition = condition,
        body      = BlockStmt(body)
    }
    return stmt
}

parse_block_stmt :: proc(p: ^Parser) -> BlockStmt {
    assert(p.current.kind == .OpenBrace)
    advance(p) // Consume {
    skip_stmt_separator(p)
    if p.current.kind == .CloseBrace {
        advance(p) // Consume }
        return nil
    }

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
    case .Asterisk:
        advance(p)
        #partial switch p.current.kind {
        case .Eq, .AddEq, .SubEq, .MulEq, .DivEq, .ModEq:
            stmt = parse_assignment(p, id)
        case: parse_error(p, "Unexptected token")
        }
        assig_stmt, _ := &stmt.(AssignStmt)
        assig_stmt.deref = true

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
            if value.variant == nil do return nil
            stmt.variant = VarDeclrStmt {
                const = false,
                type  = .None,
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
                    if value.variant == nil do return nil
                    stmt.variant = VarDeclrStmt {
                        const = true,
                        value = value,
                        type = .None
                    }
            }
        case .Id:
            type_token := p.current
            type := type_from_string(p.current.text)
            // Note: This will not work for user declared types
            if type == .Invalid do parse_error(
                p.current.pos,
                "Invalid type declaration: %w",
                p.current.text
            )
            
            advance(p)
            #partial switch p.current.kind {
                case .Eq:
                    advance(p)
                    value := parse_expression(p)
                    if value.variant == nil do return nil
                    stmt.variant = VarDeclrStmt {
                        const = false,
                        type = type,
                        value = value
                    }
                case .Colon:
                    advance(p)
                    value := parse_expression(p)
                    if value.variant == nil do return nil
                    stmt.variant = VarDeclrStmt {
                        const = true,
                        type = type,
                        value = value
                    }
                case .Newline:
                    expr: Expr
                    #partial switch type {
                        case .Bool:  expr.variant = Bool(false)
                        case .Int:   expr.variant = Int(0)
                        case .Float: expr.variant = Float(0)
                        case .Char:  expr.variant = Char(0)
                        case:
                            parse_error_custom(type_token.pos, "!Undeclared type: %v", type_token.text)
                    }
                    stmt.variant = VarDeclrStmt {
                        const = false,
                        type = type,
                        value = expr
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
        skip_newline(p)
        defer skip_newline(p)
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
        } else {
            parse_error(p.current.pos, "Parameters must be separated by a comma")
            return {}, false
        }
        
    }
    return params[:], true
}

parse_call :: proc(p: ^Parser, id: Token) -> Stmt {
    args, ok := parse_call_args(p, id.sym)
    if !ok do return nil
    stmt := CallStmt {
        id   = id,
        args = args
    }
    return stmt
}

parse_call_args :: proc(p: ^Parser, callee: SymbolId) -> ([]Expr, bool) {
    args: [dynamic]Expr

    assert(p.current.kind == .OpenParen)
    advance(p) // consume '('

    if p.current.kind != .CloseParen {
        for {
            expr := parse_expression(p)
            if expr.variant == nil {
                parse_error(p, "Invalid argument in call to")
                fmt.eprintfln("%v()", symbol_name(callee))
                return nil, false
            }
            append(&args, expr)

            if p.current.kind == .CloseParen do break
            if p.current.kind != .Comma {
                parse_error(p.current.pos, "Expected ',' or ')', got: %w", p.current.text)
                return nil, false
            }

            advance(p) // consume ','
            if p.current.kind == .CloseParen {
                parse_error(p, "Trailing comma is not allowed in call to")
                fmt.eprintfln("%v()", symbol_name(callee))
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

        left = Expr{left.id, left.pos, node}
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

        left = Expr{left.id, left.pos, node}
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

        left = Expr{left.id, left.pos, node}
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

        left = Expr{left.id, left.pos, node}
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

        left = Expr{left.id, left.pos, node}
    }

    return left
}

parse_multiplicative :: proc(p: ^Parser) -> Expr {
    left := parse_unary(p)
    for p.current.kind == .Asterisk || p.current.kind == .Div || p.current.kind == .Mod {
        op_token := p.current
        advance(p)

        right := parse_unary(p)
        node := new(BinaryExpr)
        node^ = BinaryExpr{
            op = op_token_kind(op_token.kind),
            left = left,
            right = right
        }

        left = Expr{left.id, left.pos, node}
    }

    return left
}

parse_unary :: proc(p: ^Parser) -> Expr {
    if p.current.kind == .Sub ||   // -x
       p.current.kind == .Not ||   // !x
       p.current.kind == .Ampersand// &x
    { 

        op_token := p.current
        advance(p)

        operand := parse_unary(p) // recursion = right associative

        if op_token.kind == .Ampersand {
            operand_ptr := new(Expr)
            operand_ptr^ = operand
            return Expr {operand.id, op_token.pos, RefExpr{id = operand.id, expr = operand_ptr}}
        }

        if op_token.kind == .Asterisk {
            operand_ptr := new(Expr)
            operand_ptr^ = operand
            return Expr {operand.id, op_token.pos, DerefExpr{id = operand.id, expr = operand_ptr}}
        }

        node := new(UnaryExpr)
        node^ = UnaryExpr{
            op = unary_op_token_kind(op_token.kind),
            expr = operand,
        }
        return Expr {op_token.sym, op_token.pos, node}
    }

    return parse_postfix(p)
}

parse_postfix :: proc(p: ^Parser, loc := #caller_location) -> Expr {
    expr := parse_factor(p)

    for {
        #partial switch p.current.kind {
        case .OpenParen:
            args, ok := parse_call_args(p, expr.id)
            if !ok do return {}

            node := new(CallExpr)
            node^ = CallExpr {
                callee = expr,
                args = args,
            }
            expr = Expr{expr.id, expr.pos, node}

        case .Asterisk:
            next := peek_token(p.lexer^)
            if next.kind == .Int || next.kind == .Float || next.kind == .True || next.kind == .False ||
               next.kind == .Id || next.kind == .Char || next.kind == .OpenParen || next.kind == .Ampersand ||
               next.kind == .Sub || next.kind == .Not {
                return expr
            }

            advance(p) // consume postfix '*'
            operand_ptr := new(Expr)
            operand_ptr^ = expr
            expr = Expr{expr.id, expr.pos, DerefExpr{id = expr.id, expr = operand_ptr}}

        case: return expr
        }
    }

    return expr
}


parse_factor :: proc(p: ^Parser) -> Expr {
    token := p.current
    #partial switch p.current.kind {
    case .Int:
        val, ok := strconv.parse_int(p.current.text); assert(ok)
        node := Int(val)
        advance(p)
        return Expr{token.sym, token.pos, node}

    case .Float:
        val, ok := strconv.parse_f64(p.current.text); assert(ok)
        node := Float(val)
        advance(p)
        return Expr{token.sym, token.pos, node}
    
    case .True, .False:
        node := Bool(p.current.kind == .True ? true : false)
        advance(p)
        return Expr{token.sym, token.pos, node}

    case .Id:
        node := Identifier(p.current.sym)
        advance(p)
        return Expr{token.sym, token.pos, node}

    case .Char:
        node := Char(p.current.text[0])
        advance(p)
        return Expr{token.sym, token.pos, node}

    case .OpenParen:
        advance(p) // consume '('
        expr := parse_expression(p)

        if p.current.kind != .CloseParen {
            parse_error(p, "Expected '('', got:")
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
    print_expression :: proc(e: Expr) {
        bin_expr, bin_expr_ok := e.variant.(^BinaryExpr)
        if bin_expr_ok {
            fmt.printf("(")
            print_expression(bin_expr.left)
            fmt.printf(" %v ", to_string_binary_op(bin_expr.op))
            print_expression(bin_expr.right)
            fmt.printf(")")
        } else if call_expr, call_expr_ok := e.variant.(^CallExpr); call_expr_ok {
            print_expression(call_expr.callee)
            fmt.printf("(")
            for arg, i in call_expr.args {
                if i > 0 do fmt.printf(", ")
                print_expression(arg)
            }
            fmt.printf(")")
        } else {
            fmt.printf("%v", e)
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
            for sub_stmt in stmt.main_body do println_statement(sub_stmt)
            if stmt.else_body != nil {
                fmt.printf("Else:\n")
                for sub_stmt in stmt.else_body do println_statement(sub_stmt)
            }
            fmt.println("END")
        case ReturnStmt:
            fmt.print("RETURN ")
            print_expression(auto_cast stmt)
        case DeclrStmt:
            switch d in stmt.variant {
                case VarDeclrStmt:
                    fmt.printf("Var:\t%vid: %w\t, typename: %w,\t value: %v ", 
                        d.const                ? "const\t" : "\t", stmt.id.text, 
                        d.type == .None        ? "None"    : fmt.tprint(d.type), 
                        d.value.variant
                    )
                case FnDeclrStmt:
                    fmt.printf("Fn:\t%v", d)
            }
        case CallStmt:
            fmt.printf("Called %w with args: ", stmt.id.text)
            for arg in stmt.args do print_expression(arg)
    }
    fmt.println()
}

type_from_string :: #force_inline proc(typename: string) -> Type {
    switch typename {
        case "int":     return .Int
        case "float":   return .Float
        case "bool":    return .Bool
        case "char":    return .Char
        case "":        return .None 
        case:           return .Invalid
    }
}

op_token_kind :: proc(t: TokenKind) -> BinaryOp {
    #partial switch t {
        case .Add: return .Add
        case .Sub: return .Sub
        case .Div: return .Div
        case .Mod: return .Mod
        case .Or:  return .Or
        case .And: return .And
        case .Asterisk: return .Mul
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

parse_program :: proc(p: ^Parser) -> BlockStmt {
    stmts: [dynamic]Stmt

    for p.current.kind != .EOF {
        stmt := parse_statement(p)
        if stmt == nil {
            fmt.eprintfln("Failed to parse file %w", p.lexer.path)
            os.exit(1)
        }
        // fmt.println(stmt)
        append(&stmts, stmt)
        skip_stmt_separator(p)
        if p.current.kind == .CloseBrace do break
            
    }

    return BlockStmt(stmts[:])
}