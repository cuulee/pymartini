import numpy as np
cimport numpy as np


cdef class Martini:
    # Define class attributes
    cdef readonly unsigned short grid_size
    cdef readonly unsigned int num_triangles
    cdef readonly unsigned int num_parent_triangles

    # Can't store Numpy arrays as class attributes, but you _can_ store the
    # associated memoryviews
    # https://stackoverflow.com/a/23840186
    cdef public np.uint32_t[:] indices_view
    cdef public np.uint16_t[:] coords_view

    def __init__(self, int grid_size=257):
        self.grid_size = grid_size
        tile_size = grid_size - 1
        if tile_size & (tile_size - 1):
            raise ValueError(
                f'Expected grid size to be 2^n+1, got {grid_size}.')

        self.num_triangles = tile_size * tile_size * 2 - 2
        self.num_parent_triangles = self.num_triangles - tile_size * tile_size

        cdef np.ndarray[np.uint32_t, ndim=1] indices = np.zeros(grid_size * grid_size, dtype=np.uint32)

        # coordinates for all possible triangles in an RTIN tile
        cdef np.ndarray[np.uint16_t, ndim=1] coords = np.zeros(self.num_triangles * 4, dtype=np.uint16)

        # Py_ssize_t is the proper C type for Python array indices.
        cdef Py_ssize_t i, _id
        # TODO: Do you need to redeclare these? Already declared in class
        cdef np.uint32_t[:] indices_view = indices
        cdef np.uint16_t[:] coords_view = coords
        cdef int k
        cdef unsigned short ax, ay, bx, by, mx, my, cx, cy

        # get triangle coordinates from its index in an implicit binary tree
        for i in range(self.num_triangles):
            # id is a reserved name in Python
            _id = i + 2

            ax = ay = bx = by = cx = cy = 0
            if _id & 1:
                # bottom-left triangle
                bx = by = cx = tile_size
            else:
                # top-right triangle
                ax = ay = cy = tile_size

            while (_id >> 1) > 1:
                # Since Python doesn't have a >>= operator
                _id = _id >> 1

                mx = (ax + bx) >> 1
                my = (ay + by) >> 1

                if _id & 1:
                    # Left half
                    bx, by = ax, ay
                    ax, ay = cx, cy
                else:
                    # Right half
                    ax, ay = bx, by
                    bx, by = cx, cy

                cx, cy = mx, my

            k = i * 4
            coords_view[k + 0] = ax
            coords_view[k + 1] = ay
            coords_view[k + 2] = bx
            coords_view[k + 3] = by

        self.indices_view = indices_view
        self.coords_view = coords_view

    def create_tile(self, terrain):
        return Tile(terrain, self)


cdef class Tile:
    # Define class attributes
    cdef readonly unsigned short grid_size
    cdef readonly unsigned int num_triangles
    cdef readonly unsigned int num_parent_triangles

    # Can't store Numpy arrays as class attributes, but you _can_ store the
    # associated memoryviews
    # https://stackoverflow.com/a/23840186
    cdef public np.uint32_t[:] indices_view
    cdef public np.uint16_t[:] coords_view

    cdef public np.float32_t[:] terrain_view
    cdef public np.float32_t[:] errors_view

    def __init__(self, terrain, martini):
        size = martini.grid_size

        if len(terrain) != (size * size):
            raise ValueError(
                f'Expected terrain data of length {size * size} ({size} x {size}), got {len(terrain)}.'
            )

        self.terrain_view = terrain
        self.errors_view = np.zeros(len(terrain), dtype=np.float32)

        # Expand Martini instance, since I can't cdef a class
        self.grid_size = martini.grid_size
        self.num_triangles = martini.num_triangles
        self.num_parent_triangles = martini.num_parent_triangles
        self.indices_view = martini.indices_view
        self.coords_view = martini.coords_view

        self.update()

    def update(self):
        cdef unsigned short size
        size = self.grid_size

        # Py_ssize_t is the proper C type for Python array indices.
        cdef Py_ssize_t i
        cdef int k
        cdef unsigned short ax, ay, bx, by, mx, my, cx, cy

        # iterate over all possible triangles, starting from the smallest level
        for i in range(self.num_triangles - 1, -1, -1):
            k = i * 4
            ax = self.coords_view[k + 0]
            ay = self.coords_view[k + 1]
            bx = self.coords_view[k + 2]
            by = self.coords_view[k + 3]
            mx = (ax + bx) >> 1
            my = (ay + by) >> 1
            cx = mx + my - ay
            cy = my + ax - mx

            # calculate error in the middle of the long edge of the triangle
            interpolated_height = (
                self.terrain_view[ay * size + ax] + self.terrain_view[by * size + bx]) / 2
            middle_index = my * size + mx
            middle_error = abs(interpolated_height - self.terrain_view[middle_index])

            self.errors_view[middle_index] = max(self.errors_view[middle_index], middle_error)

            if i < self.num_parent_triangles:
                # bigger triangles; accumulate error with children
                left_child_index = ((ay + cy) >> 1) * size + ((ax + cx) >> 1)
                right_child_index = ((by + cy) >> 1) * size + ((bx + cx) >> 1)
                self.errors_view[middle_index] = max(
                    self.errors_view[middle_index], self.errors_view[left_child_index],
                    self.errors_view[right_child_index])

    def get_mesh(self, max_error=0):
        indices = np.asarray(self.indices_view, dtype=np.uint32)
        errors = np.asarray(self.errors_view, dtype=np.float32)

        return get_mesh(
          errors=errors,
          indices=indices,
          size=self.grid_size,
          max_error=max_error
        )


def get_mesh(
      np.ndarray[np.float32_t, ndim=1] errors,
      np.ndarray[np.uint32_t, ndim=1] indices,
      unsigned short size,
      float max_error,
    ):

    cdef unsigned int num_vertices = 0
    cdef unsigned int num_triangles = 0
    # max is a reserved keyword in Python
    cdef unsigned short _max = size - 1

    # use an index grid to keep track of vertices that were already used to
    # avoid duplication
    # I already initialized array with zeros
    # indices.fill(0)

    # retrieve mesh in two stages that both traverse the error map:
    # - countElements: find used vertices (and assign each an index), and count triangles (for minimum allocation)
    # - processTriangle: fill the allocated vertices & triangles typed arrays

    num_vertices, num_triangles, errors, indices = countElements(
        0, 0, _max, _max, _max, 0, num_vertices, num_triangles, errors, indices, max_error, size)
    num_vertices, num_triangles, errors, indices = countElements(
        _max, _max, 0, 0, 0, _max, num_vertices, num_triangles, errors, indices, max_error, size)

    cdef np.ndarray[np.uint16_t, ndim=1] vertices = np.zeros(num_vertices * 2, dtype=np.uint16)
    cdef np.ndarray[np.uint32_t, ndim=1] triangles = np.zeros(num_triangles * 3, dtype=np.uint32)
    cdef unsigned int tri_index = 0

    triangles, vertices, tri_index = processTriangle(0, 0, _max, _max, _max, 0, tri_index, errors, indices, triangles, vertices, max_error, size)
    triangles, vertices, tri_index = processTriangle(_max, _max, 0, 0, 0, _max, tri_index, errors, indices, triangles, vertices, max_error, size)

    return vertices, triangles

cdef countElements(
    unsigned short ax,
    unsigned short ay,
    unsigned short bx,
    unsigned short by,
    unsigned short cx,
    unsigned short cy,
    unsigned int num_vertices,
    unsigned int num_triangles,
    np.ndarray[np.float32_t, ndim=1] errors,
    np.ndarray[np.uint32_t, ndim=1] indices,
    float max_error,
    unsigned int size):

    cdef unsigned short mx, my
    cdef float [:] errors_view = errors
    cdef unsigned int [:] indices_view = indices

    mx = (ax + bx) >> 1
    my = (ay + by) >> 1

    if (abs(ax - cx) + abs(ay - cy) > 1) and (errors_view[my * size + mx] >
                                              max_error):
        num_vertices, num_triangles, errors, indices = countElements(
            cx, cy, ax, ay, mx, my, num_vertices, num_triangles, errors, indices, max_error, size)
        num_vertices, num_triangles, errors, indices = countElements(
            bx, by, cx, cy, mx, my, num_vertices, num_triangles, errors, indices, max_error, size)
    else:
        if not indices_view[ay * size + ax]:
            num_vertices += 1
            indices_view[ay * size + ax] = num_vertices
        if not indices_view[by * size + bx]:
            num_vertices += 1
            indices_view[by * size + bx] = num_vertices
        if not indices_view[cy * size + cx]:
            num_vertices += 1
            indices_view[cy * size + cx] = num_vertices

        num_triangles += 1

    return num_vertices, num_triangles, errors, indices


cdef processTriangle(
    unsigned short ax,
    unsigned short ay,
    unsigned short bx,
    unsigned short by,
    unsigned short cx,
    unsigned short cy,
    unsigned int tri_index,
    np.ndarray[np.float32_t, ndim=1] errors,
    np.ndarray[np.uint32_t, ndim=1] indices,
    np.ndarray[np.uint32_t, ndim=1] triangles,
    np.ndarray[np.uint16_t, ndim=1] vertices,
    float max_error,
    unsigned int size
    ):

    cdef unsigned short mx, my
    cdef float [:] errors_view = errors
    cdef unsigned int [:] indices_view = indices
    cdef unsigned int [:] triangles_view = triangles
    cdef unsigned short [:] vertices_view = vertices

    mx = (ax + bx) >> 1
    my = (ay + by) >> 1

    if (abs(ax - cx) + abs(ay - cy) > 1) and (errors_view[my * size + mx] >
                                              max_error):
        # triangle doesn't approximate the surface well enough; drill down further
        triangles, vertices, tri_index = processTriangle(cx, cy, ax, ay, mx, my, tri_index, errors, indices, triangles, vertices, max_error, size)
        triangles, vertices, tri_index = processTriangle(bx, by, cx, cy, mx, my, tri_index, errors, indices, triangles, vertices, max_error, size)

    else:
        # add a triangle
        a = indices_view[ay * size + ax] - 1
        b = indices_view[by * size + bx] - 1
        c = indices_view[cy * size + cx] - 1

        vertices_view[2 * a] = ax
        vertices_view[2 * a + 1] = ay

        vertices_view[2 * b] = bx
        vertices_view[2 * b + 1] = by

        vertices_view[2 * c] = cx
        vertices_view[2 * c + 1] = cy

        triangles_view[tri_index] = a
        tri_index += 1
        triangles_view[tri_index] = b
        tri_index += 1
        triangles_view[tri_index] = c
        tri_index += 1

    return triangles, vertices, tri_index
