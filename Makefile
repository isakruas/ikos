# Makefile for ikOS. Compiles the kernel with the ik8b toolchain from the
# vendored submodule (tools/ikide).
#
#   make toolchain # build the ik8b compiler binary in the submodule (once)
#   make build     # compile the kernel to build/boot.hex
#   make run       # compile and simulate (LIMIT overrides the instruction cap)
#   make test      # run the end-to-end shell test harness
#   make docs      # build the HTML manual
#   make clean     # remove the compiled kernel images

.PHONY: all toolchain build run test docs clean

# Toolchain from the submodule.
IK8B                 = tools/ikide/tools/ik8b/ik8b
export IK8B_STD_PATH = tools/ikide/tools/ik8b/std
LIMIT               ?= 4000000

all: build

# Build the compiler binary inside the submodule (Docker; run once after clone).
toolchain:
	@$(MAKE) -C tools/ikide/tools/ik8b build

build:
	@mkdir -p build
	$(IK8B) build boot.ik -o build/boot.hex --report

run:
	@mkdir -p build
	$(IK8B) run boot.ik -o build/boot.hex --limit $(LIMIT)

test:
	@$(MAKE) -C test test

docs:
	@$(MAKE) -C docs html

clean:
	rm -rf build
