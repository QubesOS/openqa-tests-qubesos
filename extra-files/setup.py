import setuptools

if __name__ == '__main__':
    setuptools.setup(
            name='qubesteststub',
            version='1.0',
            packages=setuptools.find_packages(),
            entry_points={
                'qubes.ext': [
                    'qubestestdefaultpv = qubesteststub:DefaultPV',
                ],
            })

