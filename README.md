# Halo model

Example halo model code.

To clone this repositoy
```
git clone --recursive https://github.com/alexander-mead/halo_model
```
the `--recursive` is important in order to automatically clone the required library too.

To compile requires a Fortran compiler and one needs to simply run the `Makefile` by typing `>make` in the terminal. The `Makefile` is configured to use `gfortran`, but you can change this and it should work with other compilers, although you may need to change some of the compile flags.

Run the code via `>./bin/halo_model`. It should print some useful things to the screen and create data files `data/power_linear.dat`, `data/power_2h.dat`, `data/power_1h.dat` and `data/power_hm.dat`. You should be able to plot these using the `gnuplot` script `power.p`, which is also included in the repository. You should be able to make the plot via `>gnuplot power.p`.
