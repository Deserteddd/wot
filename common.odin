package wot


Int :: i32
Uint :: u32
Float :: f32
String :: string

Type :: enum {
    None,
    Float,
    Int,
    String,
    Bool,
}

Var :: struct {
    value: Value,
    type: Type,
    const: bool,
}

Value :: union {
    None,
    Float,
    Int,
    String,
    bool
}