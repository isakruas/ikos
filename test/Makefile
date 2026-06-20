# Run the ikOS end-to-end shell test harness against the kernel
# image, in the same rust:latest Docker the rest of the project uses.
#
#   make test      # build the kernel image, then compile and run the harness
#   make build     # just (re)build the kernel image
#   make clean     # remove the harness build artifacts

.PHONY: test build clean

# Kernel image the harness boots.
HEX ?= ../build/boot.hex

build:
	@$(MAKE) -C .. build

# Mount the whole ikOS tree so the submodule path deps (tools/ikide) resolve,
# then chown the build artifacts back from root.
test: build
	docker run --rm -v "$(CURDIR)/..:/ikos" -w /ikos/test rust:latest \
	  bash -c "cargo run --release -- $(HEX); chown -R $$(id -u):$$(id -g) target 2>/dev/null || true"

clean:
	rm -rf target
