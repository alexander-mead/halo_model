# Makefile to compile halo model

# Standard flags
HMX_FFLAGS = \
	-Warray-bounds \
	-fmax-errors=4 \
	-ffpe-trap=invalid,zero,overflow \
	-fimplicit-none \
	-O3 \
	-fdefault-real-8 \
	-fdefault-double-8 \
	-fopenmp \
	-lgfortran \
	-lm

# Extra debugging flags
DEBUG_FLAGS = \
	-Wall \
	-fcheck=all \
	-fbounds-check \
	-fbacktrace \
	-Og

# No cosmosis
FC = gfortran
FFLAGS = $(HMX_FFLAGS) -std=gnu -ffree-line-length-none 
all: bin lib

# Source-code directory
SRC_DIR = src

# Build directory
BUILD_DIR = build

# Debug build directory
DEBUG_BUILD_DIR = debug_build

# Library directory
LIB_DIR = lib

# Executable directory
BIN_DIR = bin

# Objects
_OBJ = \
	constants.o \
	physics.o \
	logical_operations.o \
	random_numbers.o \
	file_info.o \
	fix_polynomial.o \
	array_operations.o \
	table_integer.o \
	special_functions.o \
	interpolate.o \
	solve_equations.o \
	string_operations.o \
	calculus_table.o \
	cosmology_functions.o \
	HMx.o \
	Limber.o \
	cosmic_emu_stuff.o \
	owls.o \
	owls_extras.o

# Add prefixes of build directory to objects
OBJ = $(addprefix $(BUILD_DIR)/,$(_OBJ))
DEBUG_OBJ = $(addprefix $(DEBUG_BUILD_DIR)/,$(_OBJ))

# ?
make_dirs = @mkdir -p $(@D)

# Standard rules
lib: $(LIB_DIR)/libhmx.a
bin: $(BIN_DIR)/halo_model

# Debugging rules
debug: FFLAGS += $(DEBUG_FLAGS)
debug: $(BIN_DIR)/HMx_debug

# Fitting debugging
fitting_debug: FFLAGS += $(DEBUG_FLAGS)
fitting_debug: $(BIN_DIR)/HMx_fitting_debug

# Rule to make object files
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.f90
	$(make_dirs)
	$(FC) -c -o $@ $< -J$(BUILD_DIR) $(LDFLAGS) $(FFLAGS)

# Rule to make HMx executable
$(BIN_DIR)/halo_model: $(OBJ) $(SRC_DIR)/halo_model.f90
	@echo "\nBuilding executable.\n"
	$(make_dirs)
	$(FC) -o $@ $^ -J$(BUILD_DIR) $(LDFLAGS) $(FFLAGS)

# Rule to make debugging objects
$(DEBUG_BUILD_DIR)/%.o: $(SRC_DIR)/%.f90
	$(make_dirs)
	$(FC) -c -o $@ $< -J$(DEBUG_BUILD_DIR) $(LDFLAGS) $(FFLAGS)

# Rule to make debugging executable
$(BIN_DIR)/halo_model_debug: $(DEBUG_OBJ) $(SRC_DIR)/halo_model.f90
	@echo "\nBuilding debugging executable.\n"
	$(FC) -o $@ $^ -J$(DEBUG_BUILD_DIR) $(LDFLAGS) $(FFLAGS)

# Rule to make HMx static library
$(LIB_DIR)/libhmx.a: $(OBJ)
	@echo "\nBuilding static library.\n"
	$(make_dirs)
	$(AR) rc $@ $^

# Clean up
.PHONY: clean
clean:
	rm -f $(BIN_DIR)/HMx
	rm -f $(BIN_DIR)/HMx_debug
	rm -f $(BIN_DIR)/HMx_fitting
	rm -f $(BIN_DIR)/HMx_fitting_debug
	rm -f $(LIB_DIR)/libhmx.a
	rm -f $(LIB_DIR)/HMx_cosmosis_interface.so
	rm -f $(BUILD_DIR)/*.o
	rm -f $(BUILD_DIR)/*.mod
	rm -f $(SRC_DIR)/*.mod
	rm -f $(DEBUG_BUILD_DIR)/*.o
	rm -f $(DEBUG_BUILD_DIR)/*.mod
	test -n "$(LIB_DIR)" && rm -rf $(LIB_DIR)/HMx_cosmosis_interface.so.dSYM/
	test -n "$(BIN_DIR)" && rm -rf $(BIN_DIR)/HMx.dSYM/
	test -n "$(BIN_DIR)" && rm -rf $(BIN_DIR)/HMx_debug.dSYM/
