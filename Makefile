# Makefile for ikOS. Compiles the kernel with the ik8b toolchain from the
# vendored submodule (tools/ikide).
#
#   make toolchain # build the ik8b compiler binary in the submodule (once)
#   make build     # compile the kernel to build/boot.hex
#   make run       # compile and simulate (LIMIT overrides the instruction cap)
#   make test      # run the Rhai test suite (tests/*.rhai) via the IDE runner
#   make docs      # build the HTML manual
#   make clean     # remove the compiled kernel images

.PHONY: all toolchain build run test docs clean

# Toolchain from the submodule.
IK8B                 = tools/ikide/tools/ik8b/ik8b
IKIDE                = tools/ikide
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

# Run tests/*.rhai through the IDE's headless test runner, built from the
# vendored submodule, in the same rust:latest Docker as the rest of the project.
# The suite compiles boot.ik in-process, so no prior `make build` is needed.
test:
	docker run --rm -v "$(CURDIR):/ikos" -w /ikos rust:latest \
	  bash -c "export PATH=/usr/local/cargo/bin:\$$PATH; \
	    cargo build --release --manifest-path $(IKIDE)/Cargo.toml --bin ikide; rc=\$$?; \
	    if [ \$$rc -eq 0 ]; then $(IKIDE)/target/release/ikide test . ; rc=\$$?; fi; \
	    chown -R \$$(id -u):\$$(id -g) $(IKIDE)/target 2>/dev/null || true; \
	    exit \$$rc"

docs:
	@$(MAKE) -C docs html

clean:
	rm -rf build
