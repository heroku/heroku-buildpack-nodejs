// Copyright Joyent, Inc. and other Node contributors.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.

#ifndef NODE_CONFIG_H
#define NODE_CONFIG_H

#define NODE_CFLAGS "-rdynamic -D_GNU_SOURCE -DHAVE_CONFIG_H=1 -pthread -arch x86_64 -g -O3 -DHAVE_OPENSSL=1 -DEV_FORK_ENABLE=0 -DEV_EMBED_ENABLE=0 -DEV_MULTIPLICITY=0 -DX_STACKSIZE=65536 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64 -DEV_MULTIPLICITY=0 -DHAVE_FDATASYNC=0 -DPLATFORM=\"darwin\" -D__POSIX__=1 -Wno-unused-parameter -D_FORTIFY_SOURCE=2 -DNDEBUG -I/tmp/n47/include/node"
#define NODE_PREFIX "/tmp/n47"

#endif /* NODE_CONFIG_H */
