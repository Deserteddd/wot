import time


def a_function(zx: float, zy: float, x: float) -> float:
	return zx*zx - zy*zy + x


start = time.perf_counter()

y = -1
iterations = 0
while y <= 1:
	x = -2.0
	while x <= 1:
		zx = 0.0
		zy = 0.0
		iter = 0
		max_iter = 100

		while (zx*zx + zy*zy <= 4) and (iter < max_iter):
			xtemp = a_function(zx, zy, x)
			zy = 2*zx*zy + y
			zx = xtemp
			iter += 1
			iterations += 1
		

		# if iter == max_iter:
			# print('#', end='')
		# else:
			# print(' ', end='')

		x += 0.0315

	# print()
	y += 0.05



print(iterations)
elapsed_ms = (time.perf_counter() - start) * 1000.0
print(f"{elapsed_ms:.3f} ms")