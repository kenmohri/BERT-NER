#!/usr/bin/env python3

import argparse
import codecs
import contextlib
import gzip
import sys
import io


def output(rets, outf):
    for out in rets:
        outf.write(out)
    outf.write("\n")


def operation(inf, outprefix, max_numdoc: int):
    prevdocid = None
    rets = []

    numdoc = 0
    idx = 0
    outf = None

    for line in inf:
        if outf is None:
            fname = "%s%d" % (outprefix, idx)
            print(fname)
            outf = open(fname, 'w')
            idx += 1

        if line.startswith('# S-ID'):
            sid = line[7:]
            docid = sid.split('-')[0]
            if docid != prevdocid:
                output(rets, outf)
                rets = []  # reset
                numdoc += 1
                if numdoc % max_numdoc == 0:
                    outf.close()
                    outf = None
            prevdocid = docid
        else:
            rets.append(line)
            pass
    output(rets, outf)
    outf.close()
#         outf.write(line)


@contextlib.contextmanager
def _my_open(filename, mode='r', encoding='utf8',
             iterator=False, errors='backslashreplace'):
    if filename == '-':
        if mode is None or mode == '' or 'r' in mode:
            if iterator:
                fh = iter(sys.stdin.readline, "")
            else:
                fh = io.TextIOWrapper(sys.stdin.buffer,
                                      encoding=encoding, errors=errors)
        else:
            fh = io.TextIOWrapper(sys.stdout.buffer,
                                  encoding=encoding, errors=errors)
    elif filename.endswith('.gz'):
        fh = gzip.open(filename, mode=mode + 't', encoding=encoding)
    else:
        fh = codecs.open(filename, mode, encoding, errors=errors)
    try:
        yield fh
    finally:
        if filename != '-':
            fh.close()


def get_opts():
    oparser = argparse.ArgumentParser()
    oparser.add_argument("--input", "-i", default="-", required=False)
    oparser.add_argument("--output", "-o", required=True)
    oparser.add_argument("--maxdoc", "-m", default=50000,
                         required=False, type=int)
    return oparser.parse_args()


def main():
    opts = get_opts()
    with _my_open(opts.input, "r", "utf8") as inf:
        operation(inf, opts.output, opts.maxdoc)


if __name__ == '__main__':
    main()
