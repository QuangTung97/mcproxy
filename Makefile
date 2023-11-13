.PHONY: all lint test compile build-dist upload install-tools requirements

all: compile lint test

lint:
	mypy .

test:
	coverage run --omit="*/dist-packages/*" -m unittest

compile:
	@python setup.py build_ext --inplace
	@echo "-------------------------------------------------"

build-dist:
	rm -rf ./dist
	python3 setup.py sdist

upload:
	twine upload -r pypi dist/*

install-tools:
	pip3 install mypy
	pip3 install coverage

requirements:
	pip3 freeze >requirements.txt

