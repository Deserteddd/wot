package wot

import "core:fmt"
import "core:strings"

float :: f64

str   :: strings.Builder

TypeInfo :: struct {
    id: string
}

Variable :: struct {
    id:   string,
    type: TypeInfo,
    const: bool,
    variant: union {
        Val_Integer,
        Val_Float,
        Val_Bool,
        Val_Str,
        Val_Fn,
    }
}

Val_Integer :: distinct int
Val_Float   :: distinct float
Val_Bool    :: distinct bool
Val_Str     :: distinct str
Val_Fn      :: Function

Function :: struct {
    id:     string,
    params: []^TypeInfo,
    returns: ^TypeInfo
}

Scope_Kind :: enum {
    Global,
    Function,
    Block,
}

Scope :: struct {
    symbols: map[string]Variable,
    parent: ^Scope,
    kind: Scope_Kind,
}


scope_push :: proc(scope: ^Scope, kind: Scope_Kind = .Block) {
    parent := new(Scope)
    parent^ = scope^
    new_scope := Scope {
        symbols = make_map(map[string]Variable),
        parent = parent,
        kind = kind,
    }
    scope^ = new_scope
}

scope_pop :: proc(scope: ^Scope) -> (ok: bool) {
    if scope == nil || scope.parent == nil {
        return false
    }

    popped_symbols := scope.symbols
    parent := scope.parent

    scope^ = parent^
    delete(popped_symbols)
    free(parent)

    return true
}


scope_fetch :: proc(scope: ^Scope, id: string) -> ^Variable {
    if scope == nil do return nil

    s := scope

    // 1) Walk local scope chain up to the nearest function boundary.
    for s != nil {
        var, found := &s.symbols[id]
        if found do return var
        if s.kind == .Function do break
        s = s.parent
    }

    // 2) Continue upward, but only allow globals.
    for s != nil {
        if s.kind == .Global {
            var, found := &s.symbols[id]
            if found do return var
        }
        s = s.parent
    }

    return nil
}

scope_add :: proc(scope: ^Scope, v: Variable) -> (overwrote: bool) {
    val, found := &scope.symbols[v.id]
    overwrote = found
    if overwrote do val^ = v
    else do scope.symbols[v.id] = v

    return
}

check :: proc(program: BlockStmt) {
    scope: Scope
    scope_push(&scope, .Global) //0
    scope_push(&scope, .Block)
    scope_push(&scope, .Function)
    
    for stmt in program do switch &s in stmt {
        case DeclrStmt:
        case ReturnStmt:
        case AssignStmt:
        case CallStmt:
        case IfStmt:
        case WhileStmt:
        case BlockStmt:
    }
}