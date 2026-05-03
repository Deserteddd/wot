package wot

import "core:fmt"
import "core:strings"
import "core:bufio"
import "core:os"
import "core:strconv"
import "base:runtime"

@(private = "file")
Frame :: struct {
    chunk: ^Chunk,
    pc: int,
    stack_base: int,
    locals: []Value,
}

@(private = "file")
VM :: struct {
    stack: [dynamic; 1024]Value,
    frames: [dynamic; 128]Frame,
    globals: map[SymbolId]Value,
    functions: []FunctionIR,
    function_idx: map[SymbolId]u32,
    builtin_print: SymbolId,
    builtin_println: SymbolId,
    writer: bufio.Writer,
    flush: bool,
}

@(private = "file")
vm: VM


@(private = "file")
vm_pop :: #force_inline proc() -> Value #no_bounds_check {
    return pop(&vm.stack) 
}

@(private = "file")
vm_push :: #force_inline proc(val: Value) #no_bounds_check { append(&vm.stack, val) }

@(private = "file")
current_frame :: #force_inline proc() -> ^Frame #no_bounds_check {
    return &vm.frames[len(vm.frames)-1]
}

@(private = "file")
call_builtin :: proc(sym: SymbolId, argc: int) -> (handled: bool) {
    if sym != vm.builtin_print && sym != vm.builtin_println do return false
    args: [dynamic; 64]Value
    for _ in 0..<argc {
        append(&args, vm_pop())
    }
    #reverse for arg, i in args {
        if i < len(args) - 1 do bufio.writer_write_byte(&vm.writer, ' ')
        switch a in arg {
            case Float: 
                bufio.writer_write_string(&vm.writer, fmt.tprintf("%v", a))
            case Int:   
                bufio.writer_write_string(&vm.writer, fmt.tprintf("%v", a))
            case Bool:  
                bufio.writer_write_string(&vm.writer, a ? "true" : "false")
            case Char:  
                bufio.writer_write_byte(&vm.writer, byte(a))
                if a == '\n' do vm.flush = true
            case String:
                bufio.writer_write_string(&vm.writer, string(a))
            case None:  bufio.writer_write_string(&vm.writer, "None")
        }
    }

    if sym == vm.builtin_println {
        bufio.writer_write_byte(&vm.writer, '\n')
        vm.flush = true
    }
    return true
}

@(private = "file")
call_function :: proc(sym: SymbolId, argc: int) #no_bounds_check {
    fn_idx := vm.function_idx[sym]
    fn := vm.functions[int(fn_idx)]

    locals := make([]Value, len(fn.body.locals), context.allocator)
    for i := argc - 1; i >= 0; i -= 1 {
        locals[i] = vm_pop()
    }

    frame := Frame {
        chunk = &vm.functions[int(fn_idx)].body,
        pc = 0,
        stack_base = len(vm.stack),
        locals = locals
    }
    append(&vm.frames, frame)
}

@(private = "file")
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

@(private = "file")
tprint_instruction :: proc(chunk: Chunk, ins: Instruction, i: int) -> string {
    #partial switch ins.opcode {
        case .Const:
            idx := int(bx_of(ins))
            return fmt.tprintfln("Const (%v)", chunk.constants[idx])
        case .LoadLocal, .StoreLocal:
            idx := int(bx_of(ins))
            name := "<oob>"
            if idx >= 0 && idx < len(chunk.locals) {
                name = symbol_name(chunk.locals[idx])
            }
            return fmt.tprintfln("%v %s", ins.opcode, name)
        case .LoadGlobal, .StoreGlobal:
            idx := int(bx_of(ins))
            name := "<oob>"
            if idx >= 0 && idx < len(chunk.symbols) {
                name = symbol_name(chunk.symbols[idx])
            }
            return fmt.tprintfln("%v \'%s\'", ins.opcode, name)
        case .Jump, .JumpIfFalse:
            off := int(sbx_of(ins))
            target := i + 1 + off
            return fmt.tprintfln("%v -> [%03d]", ins.opcode, target)
        case .Call:
            idx := int(bx_of(ins))
            argc := int(ins.a)
            name := "<oob>"
            if idx >= 0 && idx < len(chunk.symbols) {
                name = symbol_name(chunk.symbols[idx])
            }
            return fmt.tprintfln("Call \"%s\" (%d args)", name, argc)
        case:
            return fmt.tprintfln("%v", ins.opcode)
    }
}

fmt_ir :: proc(ir: ProgramIR) -> string {
    b: strings.Builder
    strings.builder_init(&b)
    strings.write_string(&b, fmt.tprintfln("== entry =="))

    for ins, i in ir.entry.code {
        strings.write_string(&b, fmt.tprintf("[%03d] ",  i))
        strings.write_string(&b, tprint_instruction(ir.entry, ins, i))

    }

    for fn in ir.functions {
        strings.write_rune(&b, '\n')
        strings.write_string(&b, fmt.tprintf("== fn %v(", symbol_name(fn.name)))
        for param, i in fn.params {
            strings.write_string(&b, fmt.tprintf("%v: %v", symbol_name(param.id.sym), param.type))
            if i != len(fn.params) - 1 {
                strings.write_string(&b, ", ")
            }
        }

        strings.write_rune(&b, ')')
        if fn.return_type != "" do strings.write_string(&b, fmt.tprintf(" -> %s", fn.return_type))
        strings.write_string(&b, " ==\n")
        for ins, i in fn.body.code {
            strings.write_string(&b, fmt.tprintf("[%03d] ",  i))
            strings.write_string(&b, tprint_instruction(fn.body, ins, i))
        }
    }

    return strings.to_string(b)
}

execute :: proc() -> (halt: bool) #no_bounds_check #no_type_assert {
    if len(vm.frames) == 0 do return true

    frame := current_frame()
    if frame == nil do return true

    ins := frame.chunk.code[frame.pc]
    frame.pc += 1

    #partial switch ins.opcode {
        case .Const:
            idx := int(bx_of(ins))
            vm_push(frame.chunk.constants[idx])

        case .LoadLocal:
            idx := int(bx_of(ins))
            vm_push(frame.locals[idx])

        case .StoreLocal:
            idx := int(bx_of(ins))
            value := vm_pop()
            frame.locals[idx] = value

        case .LoadGlobal:
            idx := int(bx_of(ins))
            sym := frame.chunk.symbols[idx]
            value := vm.globals[sym]
            vm_push(value)

        case .StoreGlobal:
            idx := int(bx_of(ins))
            sym := frame.chunk.symbols[idx]
            vm.globals[sym] = vm_pop()

        case .Call:
            idx := int(bx_of(ins))
            argc := int(ins.a)
            sym := frame.chunk.symbols[idx]

            if call_builtin(sym, argc) do break
            call_function(sym, argc)

        case .Return:
            ret := Value(None{})
            if len(vm.stack) > frame.stack_base {
                ret = vm_pop()
            }

            resize(&vm.stack, frame.stack_base)
            old_frame := pop(&vm.frames)
            delete(old_frame.locals)
            if len(vm.frames) == 0 {
                halt = true
            } else {
                vm_push(ret)
            }

        case .Add, .Sub, .Mul, .Div, .Mod, .CmpEq, .NotEq, .Lt, .Gt, .LtEq, .GtEq:
            lhs := vm_pop()
            rhs := vm_pop()
            op := binary_op_from_opcode(ins.opcode)
            res, _ := apply_op(op, rhs, lhs)
            vm_push(res)
        case .And:
            lhs := vm_pop()
            rhs := vm_pop()
            vm_push(lhs.(Bool) && rhs.(Bool))
        case .Or:
            lhs := vm_pop()
            rhs := vm_pop()
            vm_push(lhs.(Bool) || rhs.(Bool))

        case .Jump:
            frame.pc += int(sbx_of(ins))
        case .JumpIfFalse:
            value := vm_pop().(Bool)
            if !value do frame.pc += int(sbx_of(ins))
        case .Neg:
            operand := vm_pop()
            res, ok := apply_unary_op(.Sub, operand)
            _ = ok
            vm_push(res)
        case .Not:
            operand := vm_pop()
            res, ok := apply_unary_op(.Not, operand)
            _ = ok
            vm_push(res)

        case .Halt:
            _ = pop(&vm.frames)
            halt = len(vm.frames) == 0

        
    }
    return
}

run_ir :: proc(ir: ^ProgramIR) #no_bounds_check {
    vm.builtin_print   = symbol_intern("print")
    vm.builtin_println = symbol_intern("println")

    buf: [1024]byte
    bufio.writer_init_with_buf(&vm.writer, os.to_writer(os.stdout), buf[:])
    defer bufio.writer_flush(&vm.writer)
    vm.functions = ir.functions[:]
    vm.function_idx = ir.function_idx

    append(&vm.frames, Frame {
        chunk = &ir.entry,
        pc = 0,
        stack_base = 0,
        locals = nil,
    })

    for !execute() {
        if vm.flush {
            bufio.writer_flush(&vm.writer)
            vm.flush = false
            free_all(context.temp_allocator)
        }
    }
}