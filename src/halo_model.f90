PROGRAM halo_model

  USE cosmology_functions
  USE HMx

  IMPLICIT NONE
  REAL :: kmin, kmax, amin, amax
  REAL, ALLOCATABLE :: k(:), a(:)
  REAL, ALLOCATABLE :: pow_li(:,:), pow_2h(:,:,:,:), pow_1h(:,:,:,:), pow_hm(:,:,:,:)
  INTEGER :: icosmo, ihm, field(1)
  INTEGER :: nk, na, nf
  CHARACTER(len=256) :: base
  TYPE(halomod) :: hmod
  TYPE(cosmology) :: cosm

  REAL, PARAMETER :: mmin=1e7
  REAL, PARAMETER :: mmax=1e17
  LOGICAL, PARAMETER :: verbose=.TRUE.

  ! Assigns the cosmological model
  icosmo=-1
  CALL assign_cosmology(icosmo,cosm,verbose)
  CALL init_cosmology(cosm)
  CALL print_cosmology(cosm)

  ! Assign the halo model
  ihm=-1
  CALL assign_halomod(ihm,hmod,verbose)

  ! Set number of k points and k range (log spaced)
  nk=128
  kmin=1e-3
  kmax=1e2
  CALL fill_array(log(kmin),log(kmax),k,nk)
  k=exp(k)

  ! Set the number of redshifts and range (linearly spaced) and convert z -> a
  amin=0.1
  amax=1.0
  na=10
  CALL fill_array(amin,amax,a,na)

  ! Allocate arrays for power spectra
  ALLOCATE(pow_li(nk,na),pow_2h(1,1,nk,na),pow_1h(1,1,nk,na),pow_hm(1,1,nk,na))

  ! Calculate halo model
  field=field_dmonly
  nf=1
  CALL calculate_HMx(field,nf,mmin,mmax,k,nk,a,na,pow_li,pow_2h,pow_1h,pow_hm,hmod,cosm,verbose,response=.FALSE.)

  ! Write data file to disk
  base='data/power'
  CALL write_power_a_multiple(k,a,pow_li,pow_2h,pow_1h,pow_hm,nk,na,base,verbose)

CONTAINS

  SUBROUTINE write_power_a_multiple(k,a,pow_lin,pow_2h,pow_1h,pow_full,nk,na,base,verbose)

    IMPLICIT NONE
    CHARACTER(len=*), INTENT(IN) :: base
    INTEGER, INTENT(IN) :: nk, na
    REAL, INTENT(IN) :: k(nk), a(na), pow_lin(nk,na), pow_2h(nk,na), pow_1h(nk,na), pow_full(nk,na)
    LOGICAL, INTENT(IN) :: verbose
    REAL :: pow(nk,na)
    INTEGER :: i
    CHARACTER(len=512) :: output
    LOGICAL :: verbose2

    DO i=1,4
       IF(i==1) THEN
          output=TRIM(base)//'_linear.dat'
          pow=pow_lin
       ELSE IF(i==2) THEN
          output=TRIM(base)//'_2h.dat'
          pow=pow_2h
       ELSE IF(i==3) THEN
          output=TRIM(base)//'_1h.dat'
          pow=pow_1h
       ELSE IF(i==4) THEN
          output=TRIM(base)//'_hm.dat'
          pow=pow_full
       ELSE
          STOP 'WRITE_POWER_A_MULTIPLE: Error, something went FUBAR'
       END IF
       IF(i==1) THEN
          verbose2=verbose
       ELSE
          verbose2=.FALSE.
       END IF
       CALL write_power_a(k,a,pow,nk,na,output,verbose2)
    END DO

  END SUBROUTINE write_power_a_multiple

  SUBROUTINE write_power_a(k,a,pow,nk,na,output,verbose)

    IMPLICIT NONE
    CHARACTER(len=*), INTENT(IN) :: output
    INTEGER, INTENT(IN) :: nk, na
    REAL, INTENT(IN) :: k(nk), a(na), pow(nk,na)
    LOGICAL, INTENT(IN) :: verbose
    INTEGER :: i, j

    ! Print to screen
    IF(verbose) THEN
       WRITE(*,*) 'WRITE_POWER_A: The first entry of the file is hashes - #####'
       WRITE(*,*) 'WRITE_POWER_A: The remainder of the first row are the scale factors - a'
       WRITE(*,*) 'WRITE_POWER_A: The remainder of the first column are the wave numbers - k'
       WRITE(*,*) 'WRITE_POWER_A: Each row then gives the power at that k and a'
       WRITE(*,*) 'WRITE_POWER_A: Output:', TRIM(output)
    END IF

    ! Write out data to files
    OPEN(7,file=output)
    DO i=0,nk
       IF(i==0) THEN
          WRITE(7,fmt='(A20,40F20.10)') '#####', (a(j), j=1,na)
       ELSE
          WRITE(7,fmt='(F20.10,40E20.10)') k(i), (pow(i,j), j=1,na)
       END IF
    END DO
    CLOSE(7)

    ! Print to screen
    IF(verbose) THEN
       WRITE(*,*) 'WRITE_POWER_A: Done'
       WRITE(*,*)
    END IF

  END SUBROUTINE write_power_a

END PROGRAM
