package wot

import "core:testing"
import os "core:os/os2"
import "core:strings"

@(test)
test_pipeline :: proc(t: ^testing.T) {
    exec :: proc(cmd: []string) -> (code: int, error: os.Error) {
        process := os.process_start({command = cmd, stdout = os.stdout, stderr = os.stderr}) or_return
        state := os.process_wait(process) or_return
        os.process_close(process) or_return
        return state.exit_code, nil
    }

    examples, err := os.read_directory_by_path("examples", 0, context.allocator)
    testing.expect(t, err == nil, "Failed to open examples folder")

    code, error := exec({"odin", "build", ".", "-debug", "-out:test_compiler.exe"})
    testing.expectf(t, code == 0, "Build failed with code: %v", code)
    testing.expectf(t, error == nil, "Error: %v", error)
    for file in examples {
        _, _, extension := strings.partition(file.name, ".")
        if extension == "wot" {
            code, error = exec({"./test_compiler.exe", file.fullpath})

            testing.expectf(t, code == 0, "Example %v failed with code: %v", file.name, code)
            testing.expectf(t, error == nil, "Error: %v", error)
        }

    }
}