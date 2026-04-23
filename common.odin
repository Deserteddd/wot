package wot

None :: struct {}

Int     :: distinct i32
Uint    :: distinct u32
Float   :: distinct f32
String  :: distinct string
Bool    :: distinct bool
Identifier :: distinct string

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