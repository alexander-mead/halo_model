PROGRAM halo_model

   USE array_operations
   USE cosmology_functions
   USE HMx

   IMPLICIT NONE

   CALL example()

CONTAINS

   SUBROUTINE example()

      REAL, ALLOCATABLE :: k(:), a(:)
      REAL, ALLOCATABLE :: pow_li(:, :), pow_2h(:, :), pow_1h(:, :), pow_hm(:, :)
      INTEGER :: icosmo, ihm
      CHARACTER(len=256) :: base
      TYPE(cosmology) :: cosm

      REAL, PARAMETER :: kmin = 1e-3
      REAL, PARAMETER :: kmax = 1e2
      INTEGER, PARAMETER :: nk = 128
      REAL, PARAMETER :: amin = 0.2
      REAL, PARAMETER :: amax = 1.0
      INTEGER, PARAMETER :: na = 9
      INTEGER, PARAMETER :: icosmo_default = 1
      INTEGER, PARAMETER :: ihm_default = 3
      LOGICAL, PARAMETER :: verbose = .TRUE.

      ! Set number of k points (log spaced) and a range
      CALL fill_array_log(kmin, kmax, k, nk)
      CALL fill_array(amin, amax, a, na)

      ! Assigns the cosmological model
      icosmo = icosmo_default
      CALL assign_cosmology(icosmo, cosm, verbose)
      CALL init_cosmology(cosm)
      CALL print_cosmology(cosm)

      ! Do the halo model calculation
      ihm = ihm_default
      CALL calculate_halomod_full(k, a, pow_li, pow_2h, pow_1h, pow_hm, nk, na, cosm, ihm)

      ! Write data file to disk
      base = 'data/power'
      CALL write_power_a_multiple(k, a, pow_li, pow_2h, pow_1h, pow_hm, nk, na, base, verbose)

   END SUBROUTINE example

END PROGRAM halo_model
