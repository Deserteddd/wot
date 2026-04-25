package wot

import "core:fmt"


Frame :: struct {
    chunk: ^Chunk,
    pc: int,
    stack_base: int,
    locals: []Value,
}

VM :: struct {
    stack: [dynamic]Value,
    frames: [dynamic]Frame,
    globals: map[SymbolId]Value,
    functions: []FunctionIR,
    function_idx: map[SymbolId]u32,
}



vm: VM

run_ir :: proc(ir: ^ProgramIR) {
    vm.functions = ir.functions[:]
    vm.function_idx = ir.function_idx

    append(&vm.frames, Frame {
        chunk = &ir.entry,
        pc = 0,
        stack_base = 0,
        locals = nil,
    })

    for !execute() {}
}

vm_pop :: #force_inline proc(loc := #caller_location) -> Value {
    if len(vm.stack) == 0 {
        fmt.eprintln(loc, "popped from empty stack")
        return None{}
    }
    return pop(&vm.stack) 
}

vm_push :: #force_inline proc(val: Value) { append(&vm.stack, val) }

current_frame :: proc() -> ^Frame {
    if len(vm.frames) == 0 do return nil
    return &vm.frames[len(vm.frames)-1]
}

call_builtin :: proc(name: string, argc: int) -> (handled: bool) {
    if name != "print" && name != "println" do return false

    args := make([]Value, argc, context.temp_allocator)
    for i := argc - 1; i >= 0; i -= 1 {
        args[i] = vm_pop()
    }

    print_values(args, name == "println")
    vm_push(None{})
    return true
}

call_function :: proc(sym: SymbolId, argc: int) {
    fn_idx, found := vm.function_idx[sym]
    assert(found)
    fn := vm.functions[int(fn_idx)]

    locals := make([]Value, len(fn.body.locals), context.allocator)
    for i := argc - 1; i >= 0; i -= 1 {
        if i < len(locals) {
            locals[i] = vm_pop()
        } else {
            _ = vm_pop()
        }
    }

    append(&vm.frames, Frame {
        chunk = &vm.functions[int(fn_idx)].body,
        pc = 0,
        stack_base = len(vm.stack),
        locals = locals,
    })
}

binary_op_from_opcode :: #force_inline proc(code: OpCode) -> BinaryOp {
    #partial switch code {
        case .Add: return .Add
        case .Sub: return .Sub
        case .Mul: return .Mul
        case .Div: return .Div
        case .Mod: return .Mod
        case .CmpEq: return .CmpEq
        case .NotEq: return .NotEq
        case .Lt:    return .Lt
        case .Gt:    return .Gt
        case .LtEq:  return .Lt_Eq
        case .GtEq:  return .Gt_Eq
        case .And:   return .And
        case .Or:    return .Or
    }
    panic("Invalid opcode to binary op conversion")
}



execute :: proc() -> (halt: bool) {
    if len(vm.frames) == 0 do return true

    frame := current_frame()
    if frame == nil do return true
    if frame.pc < 0 || frame.pc >= len(frame.chunk.code) {
        _ = pop(&vm.frames)
        return len(vm.frames) == 0
    }

    ins := frame.chunk.code[frame.pc]
    frame.pc += 1

    #partial switch ins.opcode {
        case .Const:
            idx := int(bx_of(ins))
            vm_push(frame.chunk.constants[idx])

        case .LoadLocal:
            idx := int(bx_of(ins))
            if idx < 0 || idx >= len(frame.locals) {
                vm_push(None{})
            } else {
                vm_push(frame.locals[idx])
            }

        case .StoreLocal:
            idx := int(bx_of(ins))
            value := vm_pop()
            if idx >= 0 && idx < len(frame.locals) {
                frame.locals[idx] = value
            }

        case .LoadGlobal:
            idx := int(bx_of(ins))
            if idx < 0 || idx >= len(frame.chunk.symbols) {
                vm_push(None{})
                break
            }
            sym := frame.chunk.symbols[idx]
            value, found := vm.globals[sym]
            if found {
                vm_push(value)
            } else {
                vm_push(None{})
            }

        case .StoreGlobal:
            idx := int(bx_of(ins))
            if idx < 0 || idx >= len(frame.chunk.symbols) do break
            sym := frame.chunk.symbols[idx]
            vm.globals[sym] = vm_pop()

        case .Call:
            idx := int(bx_of(ins))
            argc := int(ins.a)
            name := "<oob>"
            if idx >= 0 && idx < len(frame.chunk.symbols) {
                sym := frame.chunk.symbols[idx]
                name = symbol_name(sym)

                if call_builtin(name, argc) {
                    break
                }

                call_function(sym, argc)
            }

        case .Return:
            ret := Value(None{})
            if len(vm.stack) > frame.stack_base {
                ret = vm_pop()
            }

            resize(&vm.stack, frame.stack_base)
            _ = pop(&vm.frames)
            if len(vm.frames) == 0 {
                halt = true
            } else {
                vm_push(ret)
            }

        case .Add, .Sub, .Mul, .Div, .Mod, .CmpEq, .NotEq, .Lt, .Gt, .LtEq, .GtEq, .And, .Or:
            lhs := vm_pop()
            rhs := vm_pop()
            op := binary_op_from_opcode(ins.opcode)
            res, ok := apply_op(op, rhs, lhs); assert(ok)
            vm_push(res)
        case .Jump:
            frame.pc += int(sbx_of(ins))
        case .JumpIfFalse:
            value := vm_pop().(Bool)
            if !value do frame.pc += int(sbx_of(ins))
        case .Neg:
            operand := vm_pop()
            res, ok := apply_unary_op(.Sub, operand); assert(ok)
            vm_push(res)
        case .Not:
            operand := vm_pop()
            res, ok := apply_unary_op(.Not, operand); assert(ok)
            vm_push(res)

        case .Halt:
            _ = pop(&vm.frames)
            halt = len(vm.frames) == 0

        
    }
    return
}



print_ir :: proc(ir: ProgramIR) {
    fmt.printfln("== entry ==")
    for ins, i in ir.entry.code {
        print_instruction(ir.entry, ins, i)

    }

    for fn in ir.functions {
        fmt.printfln("== fn %s(%d) -> %s ==", symbol_name(fn.name), len(fn.params), fn.return_type)
        for ins, i in fn.body.code {
            print_instruction(fn.body, ins, i)
        }

    }
}

print_instruction :: proc(chunk: Chunk, ins: Instruction, i: int) {
    #partial switch ins.opcode {
        case .Const:
            idx := int(bx_of(ins))
            fmt.printfln("Const (%v)", chunk.constants[idx])
        case .LoadLocal, .StoreLocal:
            idx := int(bx_of(ins))
            name := "<oob>"
            if idx >= 0 && idx < len(chunk.locals) {
                name = symbol_name(chunk.locals[idx])
            }
            fmt.printfln("%v %s", ins.opcode, name)
        case .LoadGlobal, .StoreGlobal:
            idx := int(bx_of(ins))
            name := "<oob>"
            if idx >= 0 && idx < len(chunk.symbols) {
                name = symbol_name(chunk.symbols[idx])
            }
            fmt.printfln("%v %s", ins.opcode, name)
        case .Jump, .JumpIfFalse:
            off := int(sbx_of(ins))
            target := i + 1 + off
            fmt.printfln("%v -> [%03d]", ins.opcode, target)
        case .Call:
            idx := int(bx_of(ins))
            argc := int(ins.a)
            name := "<oob>"
            if idx >= 0 && idx < len(chunk.symbols) {
                name = symbol_name(chunk.symbols[idx])
            }
            fmt.printfln("Call %s (%d args)", name, argc)
        case:
            fmt.printfln("%v", ins.opcode)
    }
}