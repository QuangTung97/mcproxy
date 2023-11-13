# type: ignore
import setuptools
from Cython.Build import cythonize

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="mcproxy",
    version="0.1.0rc3",
    license="MIT",
    keywords=["Memcached", "key-value store", "caching"],

    ext_modules=cythonize('mcproxy/cmodule/cmem.pyx'),

    author="quangtung97",
    author_email="quangtung29121997@gmail.com",

    description="A high performance library for strong consistent caching",
    long_description=long_description,
    long_description_content_type="text/markdown",

    url="https://github.com/QuangTung97/mcproxy",
    project_urls={
        "Changes": "https://github.com/QuangTung97/mcproxy/releases",
        "Code": "https://github.com/QuangTung97/mcproxy",
        "Issue Tracker": "https://github.com/QuangTung97/mcproxy/issues",
    },
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
    ],
    packages=['mcproxy'],
    python_requires=">=3.8"
)
