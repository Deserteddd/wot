package wot

import "core:fmt"
import "core:strconv"

Program :: struct {
    statements: []StatementNode
}

StatementNode :: struct {
    this: Statement,
    lhs, rhs: ^StatementNode
}

Statement :: union {
    AssigStmt,
    AddEQStmt,
}

AssigStmt :: struct {
    identifier: string,
    expression: Expression,
}

AddEQStmt :: struct {
    identifier: string,
    expression: Expression,
}

Expression :: union {
    Term,
    AddExpr,
    SubExpr
}

BinaryExpr :: struct {
    expr: ^Expression,
    term: Term
}

AddExpr :: distinct BinaryExpr

SubExpr :: distinct BinaryExpr

Term :: union {
    Factor,
    MulTerm,
    DivTerm,
}

Factor :: union {
    int,
    f64,
    string,
    ^Expression
}

BinaryTerm :: struct {
    term:   ^Term,
    factor: Factor,

}

MulTerm :: distinct BinaryTerm

DivTerm :: distinct BinaryTerm



parse_program :: proc(l: ^Lexer) {
    for cur := scan_token(l); cur.kind != .EOF; cur = scan_token(l) {
        current_stmt: Statement
        if cur.kind == .Invalid do panic("Invalid token")
        #partial switch cur.kind {
        case .Id:
            literal := cur.text
            #partial switch scan_token(l).kind {
            case .Eq:
                current_stmt = AssigStmt {
                    identifier = cur.text,
                    expression = parse_expression(l)
                }
            }
            case .AddEq:
                current_stmt = AddEQStmt {
                    identifier = cur.text,
                    expression = parse_expression(l)
                }
        }
        fmt.println(current_stmt)
    }
}

parse_expression :: proc(l: ^Lexer) -> Expression {
    term := scan_token(l)
    next := peek_token(l^)
    return {}
}
