class_name GridAStar
extends RefCounted
## Deterministic 4-directional A* over a rectangular grid.
## 0 = walkable, 1 = blocked. No diagonals, so paths never cut corners.

var _w: int = 0
var _h: int = 0
var _blocked: PackedByteArray = PackedByteArray()

const _DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]


func _init(width: int, height: int, blocked: PackedByteArray) -> void:
	_w = width
	_h = height
	_blocked = blocked


func _idx(cell: Vector2i) -> int:
	return cell.y * _w + cell.x


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _w and cell.y < _h


func is_walkable(cell: Vector2i) -> bool:
	return is_inside(cell) and _blocked[_idx(cell)] == 0


func find_path(from: Vector2i, to: Vector2i, max_expansions: int = 20000) -> Array[Vector2i]:
	"""Shortest 4-dir path from->to inclusive. Empty array if unreachable."""
	var result: Array[Vector2i] = []
	if not is_walkable(from) or not is_walkable(to):
		return result
	if from == to:
		result.append(from)
		return result
	var total: int = _w * _h
	var g := PackedFloat32Array()
	g.resize(total)
	g.fill(INF)
	var came_from := PackedInt32Array()
	came_from.resize(total)
	came_from.fill(-1)
	var closed := PackedByteArray()
	closed.resize(total)
	var start: int = _idx(from)
	var goal: int = _idx(to)
	g[start] = 0.0
	# Binary min-heap of cell indices, ordered by f = g + h.
	var heap: PackedInt32Array = PackedInt32Array([start])
	var in_heap := PackedByteArray()
	in_heap.resize(total)
	in_heap[start] = 1
	var expansions: int = 0
	var found: bool = false
	while heap.size() > 0 and expansions < max_expansions:
		var current: int = _heap_pop(heap, g, to)
		in_heap[current] = 0
		if closed[current] == 1:
			continue
		closed[current] = 1
		expansions += 1
		if current == goal:
			found = true
			break
		var cc := Vector2i(current % _w, current / _w)
		for d: Vector2i in _DIRS:
			var nc: Vector2i = cc + d
			if not is_walkable(nc):
				continue
			var ni: int = _idx(nc)
			if closed[ni] == 1:
				continue
			var tentative: float = g[current] + 1.0
			if tentative < g[ni]:
				g[ni] = tentative
				came_from[ni] = current
				if in_heap[ni] == 0:
					_heap_push(heap, ni, g, to)
					in_heap[ni] = 1
				else:
					_heap_push(heap, ni, g, to)  # duplicate entry; stale one skipped via closed[]
	if not found:
		return result
	var trace: int = goal
	while trace != -1:
		result.append(Vector2i(trace % _w, trace / _w))
		trace = came_from[trace]
	# Reverse in place.
	var i: int = 0
	var j: int = result.size() - 1
	while i < j:
		var tmp: Vector2i = result[i]
		result[i] = result[j]
		result[j] = tmp
		i += 1
		j -= 1
	return result


func _heuristic(a_idx: int, goal: Vector2i) -> float:
	var ax: int = a_idx % _w
	var ay: int = a_idx / _w
	return float(absi(ax - goal.x) + absi(ay - goal.y))


func _heap_push(heap: PackedInt32Array, value: int, g: PackedFloat32Array, goal: Vector2i) -> void:
	heap.append(value)
	var i: int = heap.size() - 1
	while i > 0:
		var parent: int = (i - 1) / 2
		var f_i: float = g[heap[i]] + _heuristic(heap[i], goal)
		var f_p: float = g[heap[parent]] + _heuristic(heap[parent], goal)
		if f_i < f_p:
			var tmp: int = heap[i]
			heap[i] = heap[parent]
			heap[parent] = tmp
			i = parent
		else:
			break


func _heap_pop(heap: PackedInt32Array, g: PackedFloat32Array, goal: Vector2i) -> int:
	var top: int = heap[0]
	var last: int = heap[heap.size() - 1]
	heap.remove_at(heap.size() - 1)
	if heap.size() > 0:
		heap[0] = last
		var i: int = 0
		while true:
			var left: int = i * 2 + 1
			var right: int = i * 2 + 2
			var smallest: int = i
			var f_s: float = g[heap[smallest]] + _heuristic(heap[smallest], goal)
			if left < heap.size():
				var f_l: float = g[heap[left]] + _heuristic(heap[left], goal)
				if f_l < f_s:
					smallest = left
					f_s = f_l
			if right < heap.size():
				var f_r: float = g[heap[right]] + _heuristic(heap[right], goal)
				if f_r < f_s:
					smallest = right
			if smallest == i:
				break
			var tmp: int = heap[i]
			heap[i] = heap[smallest]
			heap[smallest] = tmp
			i = smallest
	return top
