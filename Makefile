.PHONY: all lint test compile

all: compile lint test

lint:
	mypy .

test:
	coverage run --omit="*/dist-packages/*" -m unittest

compile:
	@python setup.py build_ext --inplace
	@echo "-------------------------------------------------"
