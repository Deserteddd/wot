import time

start_time = time.time()

y = -1
iterations = 0
output = ""

while y <= 1:
    x = -2
    while x <= 1:
        zx = 0.0
        zy = 0.0
        iter_count = 0
        max_iter = 100

        while (zx*zx + zy*zy <= 4) and (iter_count < max_iter):
            xtemp = zx*zx - zy*zy + x
            zy = 2*zx*zy + y
            zx = xtemp
            iter_count += 1
            iterations += 1

        if iter_count == max_iter:
            output += "#"
        else:
            output += " "

        x += 0.0315

    output += "\n"
    y += 0.05

print(output)
print("Total iterations:", iterations)
end_time = time.time()
runtime_ms = (end_time - start_time) * 1000
print(f"Total runtime: {runtime_ms:.3f} ms")