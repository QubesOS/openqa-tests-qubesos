#!/usr/bin/python3


import xen.lowlevel.xs


def main():
    xs = xen.lowlevel.xs.xs()

    suppress = set()
    xs.watch('/local/domain', '')
    for path, token in iter(xs.read_watch, None):
        if path in suppress:
            suppress.remove(path)
            continue
        if path.endswith('/state') and 'backend' in path:
            print('got watch {}'.format(path))
            while True:
                t = xs.transaction_start()
                state =xs.read(t, path)
                print('writing or not {} to {}'.format(state, path))
                if state is None:
                    break
                xs.write(t, path, state)
                if xs.transaction_end(t, 0): 
                    break
            suppress.add(path)

main()

