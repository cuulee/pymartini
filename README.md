# pymartini

A Cython port of [Martini][martini] for fast terrain mesh generation.

It passes the (only) test case included in the original Martini JS library. More
tests are forthcoming. The only dependency is Numpy.

## Install

Currently only source builds are provided, so you'll need to have Cython and a C
compiler available during installation. Pull requests are welcome to package as
platform-specific wheels.

```
pip install pymartini
```

## Example

```py
# set up mesh generator for a certain 2^k+1 grid size
martini = Martini(257)

# generate RTIN hierarchy from terrain data (an array of size^2 length)
tile = martini.create_tile(terrain)

# get a mesh (vertices and triangles indices) for a 10m error
vertices, triangles = tile.get_mesh(10)
```

## License

This library is ported from Mapbox's [Martini][martini], which is licensed under
the ISC License. My additions are licensed under the MIT license.

ISC License

Copyright (c) 2019, Mapbox

Permission to use, copy, modify, and/or distribute this software for any purpose
with or without fee is hereby granted, provided that the above copyright notice
and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
THIS SOFTWARE.

[martini]: https://github.com/mapbox/martini
