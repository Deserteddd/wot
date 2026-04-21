package wot

import "core:fmt"

float :: f64

TypeInfo :: struct {

}

BaseType :: union {
    int,
    float,
    bool,
    string
}

check :: proc(program: ^Program) {
}