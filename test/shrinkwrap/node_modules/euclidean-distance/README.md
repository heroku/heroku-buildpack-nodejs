# Euclidean Distance

euclidean-distance is a [browserify](https://github.com/substack/node-browserify#browserify)-friendly npm module
for calculating the [Euclidean distance](http://en.wikipedia.org/wiki/Euclidean_distance#Three_dimensions)
been two points in 2D or 3D space.

<img src="http://upload.wikimedia.org/math/a/0/5/a056c1b3e4b1c72be81acf62b9e574ca.png">

## Installation

```
npm install euclidean-distance --save
```

## Usage

```js
var d = require('euclidean-distance');

d([0,0], [1,0]);
// 1

d([0,0], [3,2]);
// 3.605551275463989

d([-7,-4,3], [17, 6, 2.5]);
// 26.004807247892
```

## Test

```
npm test
```

## License

[WTFPL](http://wtfpl.org/)