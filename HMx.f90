MODULE cosdef

  TYPE cosmology
     !Contains only things that do not need to be recalculated with each new z
     REAL*8 :: om_m, om_b, om_v, om_c, h, n, sig8, w, wa, om_nu
     REAL*8 :: om, k, z_cmb
     REAL*8 :: A
     REAL*8, ALLOCATABLE :: sigma(:), r_sigma(:)
     REAL*8, ALLOCATABLE :: growth(:), a_growth(:)
     REAL*8, ALLOCATABLE :: r(:), z_r(:)
     INTEGER :: nsig, ng, nr
     CHARACTER(len=256) :: name
  END TYPE cosmology

  TYPE projection
     !Projection quantities that need to be calculated only once
     REAL*8, ALLOCATABLE :: x1(:), r_x1(:), x2(:), r_x2(:)
     REAL*8 :: rs, zs
     INTEGER :: nx1, nx2
  END TYPE projection

  TYPE lensing
     !Quantities that are necessary for lensing specifically
     REAL*8, ALLOCATABLE :: q(:), r_q(:)
     REAL*8, ALLOCATABLE :: nz(:), z_nz(:)
     INTEGER :: nq, nnz
  END TYPE lensing

  TYPE tables
     !Halo-model stuff that needs to be recalculated for each new z
     REAL*8, ALLOCATABLE :: c(:), rv(:), nu(:), sig(:), zc(:), m(:), rr(:), sigf(:)
     REAL*8, ALLOCATABLE :: r500(:), m500(:), c500(:), r200(:), m200(:), c200(:)
     REAL*8, ALLOCATABLE :: r500c(:), m500c(:), c500c(:), r200c(:), m200c(:), c200c(:)
     REAL*8, ALLOCATABLE :: log_m(:)
     REAL*8 :: sigv, sigv100, c3, knl, rnl, neff, sig8z
     REAL*8 :: gmin, gmax, gbmin, gbmax
     INTEGER :: n
  END TYPE tables

END MODULE cosdef

PROGRAM HMx

  !Modules
  USE cosdef
  USE nr

  !Standard implicit none statement
  IMPLICIT NONE

  !Standard parameters
  REAL*8 :: p1h, p2h, pfull, plin
  REAL*8, ALLOCATABLE :: k(:), z(:), pow(:,:), powz(:,:,:)
  REAL*8, ALLOCATABLE :: ell(:), Cell(:), theta(:), xi(:,:)
  INTEGER :: i, j, nk, nz, j1, j2, n, nl, nnz, nth
  INTEGER :: ip(2), ik(2), inz(2), ix(2)
  REAL*8 :: kmin, kmax, zmin, zmax, lmin, lmax, thmin, thmax
  REAL*8 :: zv
  REAL*8 :: z1, z2, r1, r2
  TYPE(cosmology) :: cosi
  TYPE(tables) :: lut
  TYPE(projection) :: proj
  TYPE(lensing) :: lens
  CHARACTER(len=256) :: output, base, mid, ext, dir
  CHARACTER(len=256) :: mode
  INTEGER :: imode, icosmo, iproj
  REAL*8 :: sig8min, sig8max
  INTEGER :: ncos
  REAL*8 :: m1, m2

  !Halo-model Parameters
  INTEGER, PARAMETER :: imf=2 !Set mass function (1 - PS, 2 - ST)
  INTEGER :: ihm=1 !Set verbosity
  INTEGER, PARAMETER :: imead=0 !Set to do Mead et al. (2015,2016) accurate calculation
  REAL*8, PARAMETER :: mmin=1d7 !Minimum halo mass for the calculation
  REAL*8, PARAMETER :: mmax=1d17 !Maximum halo mass for the calculation
  INTEGER :: ip2h=2 !Method to 'correct' the 2-halo integral
  INTEGER, PARAMETER :: ibias=1 !Bias order to go to
  INTEGER, PARAMETER :: ibox=0 !Consider the simulation volume
  REAL, PARAMETER :: Lbox=400. !Simulation box size
  INTEGER, PARAMETER :: icumulative=1 !Do cumlative distributions for breakdown
  INTEGER, PARAMETER :: ixi=1 !Do correlation functions from C(l)
  INTEGER, PARAMETER :: ifull=0 !Do only full halo model C(l), xi(theta) calculations
  REAL*8, PARAMETER :: acc=1d-4 !Global integration-accuracy parameter

  !Physical constants
  REAL*8, PARAMETER :: yfac=8.125561e-16 !sigma_T/m_e*c^2 in SI
  REAL*8, PARAMETER :: kb=1.38065d-23 !Boltzmann constant in SI
  !REAL*8, PARAMETER :: epn=0.875 !1/mu_e electron per nucleon (~8/7 for x=0.25 He mass frac)
  !REAL*8, PARAMETER :: mue=1.14 !mu_e nucleons per electron (~7/8 for x=0.25 He mass frac)
  REAL*8, PARAMETER :: fh=0.76 !Hydrogen mass fraction
  REAL*8, PARAMETER :: mue=2.d0/(1.d0+fh) !Nucleons per electron (~1.143 if fh=0.75)
  REAL*8, PARAMETER :: pfac=(5.*fh+3.)/(2.*(fh+1.)) !Pressure factor (Hill & Pajer 2013; I do not understand; ~1.929 if fh=0.75)
  REAL*8, PARAMETER :: conH0=2998. !(c/H0) in Mpc/h
  REAL*8, PARAMETER :: mp=1.6726219d-27 !Proton mass in kg
  REAL*8, PARAMETER :: msun=1.989d30 ! kg/Msun
  REAL*8, PARAMETER :: mpc=3.086d22 ! m/Mpc
  REAL*8, PARAMETER :: bigG=6.67408d-11 !Gravitational constant in kg^-1 m^3 s^-2
  REAL*8, PARAMETER :: eV=1.60218e-19 !Joules per electronvolt

  !Mathematical constants
  REAL*8, PARAMETER :: pi=3.141592654
  REAL*8, PARAMETER :: onethird=0.3333333333

  !Name parameters (cannot do PARAMETER with mixed length strings)
  !CHARACTER, PARAMETER :: halo_type(-1:6)!=(/'DMONLY','Matter','CDM','Gas','Star','Bound gas','Free gas','Pressure'/)
  CHARACTER(len=256) :: halo_type(-1:6), kernel_type(3)
  
  !Name halo types
  halo_type(-1)='DMONLY'
  halo_type(0)='Matter'
  halo_type(1)='CDM'
  halo_type(2)='Gas'
  halo_type(3)='Star'
  halo_type(4)='Bound gas'
  halo_type(5)='Free gas'
  halo_type(6)='Pressure'

  !Name kernel types
  kernel_type(1)='Lensing'
  kernel_type(2)='Compton-y'
  kernel_type(3)='CMB lensing'

  CALL get_command_argument(1,mode)
  IF(mode=='') THEN
     imode=-1
  ELSE
     READ(mode,*) imode
  END IF

  !HMx developed by Alexander Mead
  WRITE(*,*)
  WRITE(*,*) 'HMx: Welcome to HMx'
  IF(imead==-1) THEN
     WRITE(*,*) 'HMx: Doing basic halo-model calculation (Two-halo term is linear)'
  ELSE IF(imead==0) THEN
     WRITE(*,*) 'HMx: Doing standard halo-model calculation (Seljak 2000)'
  ELSE IF(imead==1) THEN
     WRITE(*,*) 'HMx: Doing accurate halo-model calculation (Mead et al. 2015)'
  ELSE
     STOP 'HMx: imead specified incorrectly'
  END IF
  WRITE(*,*)

  IF(imode==-1) THEN
     WRITE(*,*) 'HMx: Choose what to do'
     WRITE(*,*) '======================'
     WRITE(*,*) ' 0 - Matter power spectrum at z = 0'
     WRITE(*,*) ' 1 - Matter power spectrum over multiple z'
     WRITE(*,*) ' 2 - Comparison with cosmo-OWLS'
     WRITE(*,*) ' 3 - Run diagnostics'
     WRITE(*,*) ' 4 - Do random cosmologies for bug testing'
     WRITE(*,*) ' 5 - Pressure field comparison'
     WRITE(*,*) ' 6 - n(z) check'
     WRITE(*,*) ' 7 - Do cross correlation'
     WRITE(*,*) ' 8 - Cross correlation as a function of cosmology'
     WRITE(*,*) ' 9 - Breakdown correlations in halo mass'
     WRITE(*,*) '10 - Breakdown correlations in redshift'
     WRITE(*,*) '11 - Breakdown correlations in halo radius'
     READ(*,*) imode
     WRITE(*,*) '======================'
     WRITE(*,*)
  END IF

  IF(imode==0) THEN

     !Set number of k points and k range (log spaced)
     nk=200
     kmin=0.001
     kmax=1.e2
     CALL fill_table(log(kmin),log(kmax),k,nk)
     k=exp(k)
     ALLOCATE(pow(4,nk))

     !Assigns the cosmological model
     icosmo=0
     CALL assign_cosmology(icosmo,cosi)

     !Normalises power spectrum (via sigma_8) and fills sigma(R) look-up tables
     CALL initialise_cosmology(cosi)

     !Write the cosmological parameters to the screen
     CALL write_cosmology(cosi)

     !Sets the redshift
     zv=0.

     !Initiliasation for the halomodel calcualtion
     CALL halomod_init(mmin,mmax,zv,lut,cosi)

     !Do the halo-model calculation
     CALL calculate_halomod(-1,-1,k,nk,zv,pow,lut,cosi)

     !Write out the answer
     output='data/power.dat'
     CALL write_power(k,zv,pow,nk,output)

  ELSE IF(imode==1) THEN

     !Set number of k points and k range (log spaced)
     nk=200
     kmin=0.001
     kmax=1.e2
     CALL fill_table(log(kmin),log(kmax),k,nk)
     k=exp(k)

     !Set the number of redshifts and range (linearly spaced)
     nz=16
     zmin=0.
     zmax=4.
     CALL fill_table(zmin,zmax,z,nz)

     !Allocate power array
     ALLOCATE(powz(4,nk,nz))

     !Fill tables for the output power spectra
     !ALLOCATE(pfull_tab(nk,nz),p1h_tab(nk,nz),p2h_tab(nk,nz))

     !Assigns the cosmological model
     icosmo=0
     CALL assign_cosmology(icosmo,cosi)

     !Normalises power spectrum (via sigma_8) and fills sigma(R) look-up tables
     CALL initialise_cosmology(cosi)

     !Write the cosmological parameters to the screen
     CALL write_cosmology(cosi)

     !Do the halo-model calculation
     DO j=1,nz     
        CALL halomod_init(mmin,mmax,z(j),lut,cosi)
        IF(j==1) WRITE(*,*) 'HMx: Doing calculation'
        WRITE(*,fmt='(A5,I5,F10.2)') 'HMx:', j, REAL(z(j))
        CALL calculate_halomod(-1,-1,k,nk,z(j),powz(:,:,j),lut,cosi)
     END DO
     WRITE(*,*)

     base='data/power'
     CALL write_power_z(k,z,powz,nk,nz,base)

  ELSE IF(imode==2) THEN

     !Compare to cosmo-OWLS models

     !Set number of k points and k range (log spaced)
     nk=100
     kmin=1.e-2
     kmax=1.e1
     CALL fill_table(log(kmin),log(kmax),k,nk)
     k=exp(k)
     ALLOCATE(pow(4,nk))

     !Set the redshift
     zv=0.

     !Assigns the cosmological model
     icosmo=1
     CALL assign_cosmology(icosmo,cosi)

     !Normalises power spectrum (via sigma_8) and fills sigma(R) look-up tables
     CALL initialise_cosmology(cosi)

     !Write the cosmological parameters to the screen
     CALL write_cosmology(cosi)

     !Initiliasation for the halomodel calcualtion
     CALL halomod_init(mmin,mmax,zv,lut,cosi)

     !Runs the diagnostics
     CALL diagnostics(zv,lut,cosi)

     !File base and extension
     base='cosmo-OWLS/data/power_'
     mid=''
     ext='.dat'

     !Dark-matter only
     output='cosmo-OWLS/data/DMONLY.dat'
     WRITE(*,fmt='(2I5,A30)') -1, -1, TRIM(output)
     CALL calculate_halomod(-1,-1,k,nk,zv,pow,lut,cosi)
     CALL write_power(k,zv,pow,nk,output)

     !Loop over matter types and do auto and cross-spectra
     DO j1=0,3
        DO j2=j1,3

           !Fix output file and write to screen
           output=number_file2(base,j1,mid,j2,ext)
           WRITE(*,fmt='(2I5,A30)') j1, j2, TRIM(output)

           CALL calculate_halomod(j1,j2,k,nk,zv,pow,lut,cosi)
           CALL write_power(k,zv,pow,nk,output)

        END DO
     END DO

  ELSE IF(imode==3) THEN

     !Assigns the cosmological model
     icosmo=0
     CALL assign_cosmology(icosmo,cosi)

     !Normalises power spectrum (via sigma_8) and fills sigma(R) look-up tables
     CALL initialise_cosmology(cosi)

     !Write the cosmological parameters to the screen
     CALL write_cosmology(cosi)

     !WRITE(*,*) 'Redshift:'
     !READ(*,*) zv
     !WRITE(*,*)
     zv=0.

     !Initiliasation for the halomodel calcualtion
     CALL halomod_init(mmin,mmax,zv,lut,cosi)

     !Runs the diagnostics
     CALL diagnostics(zv,lut,cosi)

  ELSE IF(imode==4) THEN

     STOP 'Error, random mode not implemented yet'

     !Ignore this, only useful for bug tests
     !CALL RNG_set(0)
     !DO
     !CALL random_cosmology(cosi)

     !Ignore this, only useful for bug tests
     !END DO

  ELSE IF(imode==5) THEN

     !Compare to cosmo-OWLS models for pressure

     !Set number of k points and k range (log spaced)
     nk=100
     kmin=1.e-2
     kmax=1.e1
     CALL fill_table(log(kmin),log(kmax),k,nk)
     k=exp(k)
     ALLOCATE(pow(4,nk))

     !Set the redshift
     zv=0.

     !Assigns the cosmological model
     icosmo=1
     CALL assign_cosmology(icosmo,cosi)

     !Normalises power spectrum (via sigma_8) and fills sigma(R) look-up tables
     CALL initialise_cosmology(cosi)

     !Write the cosmological parameters to the screen
     CALL write_cosmology(cosi)

     !Initiliasation for the halomodel calcualtion
     CALL halomod_init(mmin,mmax,zv,lut,cosi)

     !Runs the diagnostics
     CALL diagnostics(zv,lut,cosi)

     !File base and extension
     base='pressure/data/power_'
     ext='.dat'

     !Number of different spectra
     n=3

     !Do the calculation
     DO j=0,n

        IF(j==0) THEN
           !DMONLY
           j1=-1
           j2=-1
           output='pressure/data/DMONLY.dat'
        ELSE IF(j==1) THEN
           !Matter x matter
           j1=0
           j2=0
           output='dd'
        ELSE IF(j==2) THEN
           !Matter x pressure
           j1=0
           j2=6
           output='dp'
        ELSE IF(j==3) THEN
           !Pressure x pressure
           j1=6
           j2=6
           output='pp'
        END IF

        IF(j .NE. 0) output=TRIM(base)//TRIM(output)//TRIM(ext)

        WRITE(*,fmt='(3I5,A30)') j, j1, j2, TRIM(output)

        CALL calculate_halomod(j1,j2,k,nk,zv,pow,lut,cosi)
        CALL write_power(k,zv,pow,nk,output)

     END DO

  ELSE IF(imode==6) THEN

     !n(z) normalisation check

     WRITE(*,*) 'HMx: Checking n(z) functions'

     inz(1)=-1
     inz(2)=0
     CALL get_nz(inz(1),lens)

     !output='lensing/nz.dat'
     !CALL write_nz(lens,output)

     WRITE(*,*) 'HMx: n(z) integral (linear):', inttab(lens%z_nz,lens%nz,lens%nnz,1)
     WRITE(*,*) 'HMx: n(z) integral (quadratic):', inttab(lens%z_nz,lens%nz,lens%nnz,2)
     WRITE(*,*) 'HMx: n(z) integral (cubic):', inttab(lens%z_nz,lens%nz,lens%nnz,3)
     WRITE(*,*)

  ELSE IF(imode==7 .OR. imode==8 .OR. imode==9 .OR. imode==10 .OR. imode==11) THEN

     !General for all cross-correlations
     
     DO i=1,2
        WRITE(*,fmt='(A20,I1)') 'HMx: Choose field: ', i
        WRITE(*,*) '============================='
        WRITE(*,*) '1 - kappa'
        WRITE(*,*) '2 - y'
        WRITE(*,*) '3 - CMB lensing'
        READ(*,*) ix(i)
        WRITE(*,*) '============================='
        WRITE(*,*)
        IF(ix(i)==1) THEN
           ip(i)=0
           ik(i)=1
           inz(i)=1
        ELSE IF(ix(i)==2) THEN
           ip(i)=6
           ik(i)=2
           inz(i)=-1 !Not used
        ELSE IF(ix(i)==3) THEN
           ip(i)=0
           ik(i)=1
           inz(i)=0
        ELSE
           STOP 'inx specified incorrectly'
        END IF
     END DO

     dir='data/'

     !Set the k range
     kmin=0.001
     kmax=100.
     nk=128
     
     !Set the z range
     zmin=0.
     zmax=4.
     nz=16  

     !Set the ell range
     lmin=1d0
     lmax=1d5
     nl=128

     !Set the angular arrays
     thmin=0.01
     thmax=10.
     nth=128

     !Set number of k points and k range (log spaced)
     !Also z points and z range (linear)
     !Also P(k,z)
     CALL fill_table(log(kmin),log(kmax),k,nk)
     k=exp(k)
     CALL fill_table(zmin,zmax,z,nz)
     ALLOCATE(powz(4,nk,nz))

     !Allocate arrays for l and C(l)
     CALL fill_table(log(lmin),log(lmax),ell,nl)
     ell=exp(ell)
     ALLOCATE(Cell(nl))

     !Allocate arrays for theta and xi(theta)
     CALL fill_table(log(thmin),log(thmax),theta,nth)
     theta=exp(theta)
     ALLOCATE(xi(3,nth))
     
     !Assigns the cosmological model
     icosmo=-1
     CALL assign_cosmology(icosmo,cosi)

     WRITE(*,*) 'HMx: Cross-correlation information'
     WRITE(*,*) 'HMx: output directiory: ', TRIM(dir)
     WRITE(*,*) 'HMx: Profile type 1: ', TRIM(halo_type(ip(1)))
     WRITE(*,*) 'HMx: Profile type 2: ', TRIM(halo_type(ip(2)))
     WRITE(*,*) 'HMx: Kernel type 1: ', TRIM(kernel_type(ik(1)))
     WRITE(*,*) 'HMx: Kernel type 1: ', TRIM(kernel_type(ik(2)))
     WRITE(*,*) 'HMx: P(k) k min [h/Mpc]:', kmin
     WRITE(*,*) 'HMx: P(k) k max [h/Mpc]:', kmax
     WRITE(*,*) 'HMx: z min:', zmin
     WRITE(*,*) 'HMx: z max:', zmax
     WRITE(*,*) 'HMx: ell min:', lmin
     WRITE(*,*) 'HMx: ell max:', lmax
     WRITE(*,*)

     IF(imode==7) THEN

        !Normalises power spectrum (via sigma_8) and fills sigma(R) look-up tables
        CALL initialise_cosmology(cosi)

        !Write the cosmological parameters to the screen
        CALL write_cosmology(cosi)

        !Loop over redshifts
        DO j=1,nz

           !Initiliasation for the halomodel calcualtion
           CALL halomod_init(mmin,mmax,z(j),lut,cosi)
           CALL calculate_halomod(ip(1),ip(2),k,nk,z(j),powz(:,:,j),lut,cosi)

           !Write progress to screen
           IF(j==1) THEN
              WRITE(*,fmt='(A5,A7)') 'i', 'z'
              WRITE(*,fmt='(A13)') '   ============'
           END IF
           WRITE(*,fmt='(I5,F8.3)') j, z(j)

        END DO
        WRITE(*,fmt='(A13)') '   ============'
        WRITE(*,*)

        output=TRIM(dir)//'power'
        CALL write_power_z(k,z,powz,nk,nz,output)

        !Initialise the lensing part of the calculation
        CALL initialise_distances(cosi)

        !Fill out the projection kernels
        CALL fill_projection_kernels(ik,inz,proj,lens,cosi)

        !Write to screen
        WRITE(*,*) 'HMx: Computing C(l)'
        WRITE(*,*) 'HMx: ell min:', ell(1)
        WRITE(*,*) 'HMx: ell max:', ell(nl)
        WRITE(*,*) 'HMx: number of ell:', nl
        WRITE(*,*)

        !Loop over all types of C(l) to create
        DO j=1,4

           IF(ifull==1 .AND. (j==1 .OR. j==2 .OR. j==3)) CYCLE

           !Write information to screen
           IF(j==1) WRITE(*,*) 'HMx: Doing linear'
           IF(j==2) WRITE(*,*) 'HMx: Doing 2-halo'
           IF(j==3) WRITE(*,*) 'HMx: Doing 1-halo'
           IF(j==4) WRITE(*,*) 'HMx: Doing full'

           !Set C(l) output files
           IF(j==1) output=TRIM(dir)//'cl_linear.dat'
           IF(j==2) output=TRIM(dir)//'cl_2halo.dat'
           IF(j==3) output=TRIM(dir)//'cl_1halo.dat'
           IF(j==4) output=TRIM(dir)//'cl_full.dat'

           WRITE(*,*) 'HMx: Output: ', TRIM(output)

           CALL calculate_Cell(0.d0,proj%rs,ell,Cell,nl,k,z,powz(j,:,:),nk,nz,proj,cosi)
           CALL write_Cell(ell,Cell,nl,output)

           IF(ixi==1) THEN
              
              !Set xi output files
              IF(j==1) output=TRIM(dir)//'xi_linear.dat'
              IF(j==2) output=TRIM(dir)//'xi_2halo.dat'
              IF(j==3) output=TRIM(dir)//'xi_1halo.dat'
              IF(j==4) output=TRIM(dir)//'xi_full.dat'

              WRITE(*,*) 'HMx: Output: ', TRIM(output)
           
              CALL calculate_xi(theta,xi,nth,ell,Cell,nl,NINT(lmax))
              CALL write_xi(theta,xi,nth,output)

           END IF

        END DO
        WRITE(*,*) 'HMx: Done'
        WRITE(*,*)

     ELSE IF(imode==8) THEN

        !Assess cross-correlation as a function of cosmology

        !Loop over cosmology
        sig8min=0.7
        sig8max=0.9
        ncos=5
        DO i=1,ncos

           cosi%sig8=sig8min+(sig8max-sig8min)*float(i-1)/float(ncos-1)

           !Normalises power spectrum (via sigma_8) and fills sigma(R) look-up tables
           CALL initialise_cosmology(cosi)

           !Write the cosmological parameters to the screen
           CALL write_cosmology(cosi)

           !Loop over redshifts
           DO j=1,nz

              !Initiliasation for the halomodel calcualtion
              CALL halomod_init(mmin,mmax,z(j),lut,cosi)
              CALL calculate_halomod(ip(1),ip(2),k,nk,z(j),powz(:,:,j),lut,cosi)

              !Write progress to screen
              IF(j==1) THEN
                 WRITE(*,fmt='(A5,A7)') 'i', 'z'
                 WRITE(*,fmt='(A13)') '   ============'
              END IF
              WRITE(*,fmt='(I5,F8.3)') j, z(j)

           END DO
           WRITE(*,fmt='(A13)') '   ============'
           WRITE(*,*)

           !Initialise the lensing part of the calculation
           CALL initialise_distances(cosi)

           !Fill out the projection kernels
           CALL fill_projection_kernels(ik,inz,proj,lens,cosi)

           !Now do the C(l) calculations
           !Set l range, note that using Limber and flat-sky for sensible results lmin to ~10
           CALL fill_table(log(lmin),log(lmax),ell,nl)
           ell=exp(ell)
           IF(ALLOCATED(Cell)) DEALLOCATE(Cell)
           ALLOCATE(Cell(nl))

           !Write to screen
           WRITE(*,*) 'HMx: Computing C(l)'
           WRITE(*,*) 'HMx: ell min:', ell(1)
           WRITE(*,*) 'HMx: ell max:', ell(nl)
           WRITE(*,*) 'HMx: number of ell:', nl
           WRITE(*,*)

           !Loop over all types of C(l) to create
           DO j=1,4

              !Set output files    
              base=TRIM(dir)//'cosmology_'
              mid='_'
              IF(j==1) ext='_cl_linear.dat'
              IF(j==2) ext='_cl_2halo.dat'
              IF(j==3) ext='_cl_1halo.dat'
              IF(j==4) ext='_cl_full.dat'
              output=number_file(base,i,ext)

              !Write information to screen
              IF(j==1) WRITE(*,*) 'HMx: Doing C(l) linear'
              IF(j==2) WRITE(*,*) 'HMx: Doing C(l) 2-halo'
              IF(j==3) WRITE(*,*) 'HMx: Doing C(l) 1-halo'
              IF(j==4) WRITE(*,*) 'HMx: Doing C(l) full'

              CALL calculate_Cell(0.d0,proj%rs,ell,Cell,nl,k,z,powz(j,:,:),nk,nz,proj,cosi)
              CALL write_Cell(ell,Cell,nl,output)

           END DO
           WRITE(*,*) 'HMx: Done'
           WRITE(*,*)

        END DO

     ELSE IF(imode==9) THEN

        !Break down cross-correlation in terms of mass

        !Normalises power spectrum (via sigma_8) and fills sigma(R) look-up tables
        CALL initialise_cosmology(cosi)

        !Write the cosmological parameters to the screen
        CALL write_cosmology(cosi)

        !Initialise the lensing part of the calculation
        CALL initialise_distances(cosi)

        !Fill out the projection kernels
        CALL fill_projection_kernels(ik,inz,proj,lens,cosi)

        DO i=0,6
           IF(icumulative==0) THEN
              !Set the mass intervals
              IF(i==0) THEN
                 m1=mmin
                 m2=mmax
              ELSE IF(i==1) THEN
                 m1=mmin
                 m2=1d11
              ELSE IF(i==2) THEN
                 m1=1d11
                 m2=1d12
              ELSE IF(i==3) THEN
                 m1=1d12
                 m2=1d13
              ELSE IF(i==4) THEN
                 m1=1d13
                 m2=1d14
              ELSE IF(i==5) THEN
                 m1=1d14
                 m2=1d15
              ELSE IF(i==6) THEN
                 m1=1d15
                 m2=1d16
              END IF
           ELSE IF(icumulative==1) THEN
              !Set the mass intervals
              IF(i==0) THEN
                 m1=mmin
                 m2=mmax
              ELSE IF(i==1) THEN
                 m1=mmin
                 m2=1d11
              ELSE IF(i==2) THEN
                 m1=mmin
                 m2=1d12
              ELSE IF(i==3) THEN
                 m1=mmin
                 m2=1d13
              ELSE IF(i==4) THEN
                 m1=mmin
                 m2=1d14
              ELSE IF(i==5) THEN
                 m1=mmin
                 m2=1d15
              ELSE IF(i==6) THEN
                 m1=mmin
                 m2=1d16
              END IF
           ELSE
              STOP 'HMx: Error, icumulative not set correctly.'
           END IF

           !Set the code to not 'correct' the two-halo power for missing
           !mass when doing the calcultion binned in halo mass
           IF(icumulative==0 .AND. i>1) ip2h=0
           !IF(icumulative==1 .AND. i>0) ip2h=0

           WRITE(*,fmt='(A16)') 'HMx: Mass range'
           WRITE(*,fmt='(A16,I5)') 'HMx: Iteration:', i
           WRITE(*,fmt='(A21,2ES15.7)') 'HMx: M_min [Msun/h]:', m1
           WRITE(*,fmt='(A21,2ES15.7)') 'HMx: M_max [Msun/h]:', m2
           WRITE(*,*)

           !Loop over redshifts
           DO j=1,nz

              !Initiliasation for the halomodel calcualtion
              CALL halomod_init(m1,m2,z(j),lut,cosi)
              CALL calculate_halomod(ip(1),ip(2),k,nk,z(j),powz(:,:,j),lut,cosi)

              !Write progress to screen
              IF(j==1) THEN
                 WRITE(*,fmt='(A5,A7)') 'i', 'z'
                 WRITE(*,fmt='(A13)') '   ============'
              END IF
              WRITE(*,fmt='(I5,F8.3)') j, z(j)

           END DO
           WRITE(*,fmt='(A13)') '   ============'
           WRITE(*,*)

           IF(i==0) THEN
              output=TRIM(dir)//'power'
           ELSE
              base=TRIM(dir)//'mass_'
              mid='_'
              ext='_power'
              output=number_file2(base,NINT(log10(m1)),mid,NINT(log10(m2)),ext)
           END IF
           WRITE(*,*) 'HMx: File: ', TRIM(output)
           CALL write_power_z(k,z,powz,nk,nz,output)

           !Loop over all types of C(l) to create
           DO j=1,4

              !Skip the 1-halo C(l) because it takes ages (06/02/16 - is this date correct?)
              IF(j==3) CYCLE

              !Set output files
              IF(i==0) THEN
                 IF(j==1) output=TRIM(dir)//'cl_linear.dat'
                 IF(j==2) output=TRIM(dir)//'cl_2halo.dat'
                 IF(j==3) output=TRIM(dir)//'cl_1halo.dat'
                 IF(j==4) output=TRIM(dir)//'cl_full.dat'
              ELSE
                 base=TRIM(dir)//'mass_'
                 mid='_'        
                 IF(j==1) ext='_cl_linear.dat'
                 IF(j==2) ext='_cl_2halo.dat'
                 IF(j==3) ext='_cl_1halo.dat'
                 IF(j==4) ext='_cl_full.dat'
                 output=number_file2(base,NINT(log10(m1)),mid,NINT(log10(m2)),ext)
              END IF

              WRITE(*,*) 'HMx: File: ', TRIM(output)

              CALL calculate_Cell(0.d0,proj%rs,ell,Cell,nl,k,z,powz(j,:,:),nk,nz,proj,cosi)
              CALL write_Cell(ell,Cell,nl,output)

           END DO
           WRITE(*,*) 'Done'
           WRITE(*,*)

        END DO

     ELSE IF(imode==10) THEN

        !Break down cross-correlation in terms of redshift

        !Normalises power spectrum (via sigma_8) and fills sigma(R) look-up tables
        CALL initialise_cosmology(cosi)

        !Write the cosmological parameters to the screen
        CALL write_cosmology(cosi)

        !Loop over redshifts
        DO j=1,nz

           !Initiliasation for the halomodel calcualtion
           CALL halomod_init(mmin,mmax,z(j),lut,cosi)
           CALL calculate_halomod(ip(1),ip(2),k,nk,z(j),powz(:,:,j),lut,cosi)

           !Write progress to screen
           IF(j==1) THEN
              WRITE(*,fmt='(A5,A7)') 'i', 'z'
              WRITE(*,fmt='(A13)') '   ============'
           END IF
           WRITE(*,fmt='(I5,F8.3)') j, z(j)

        END DO
        WRITE(*,fmt='(A13)') '   ============'
        WRITE(*,*)

        output=TRIM(base)//'power'
        CALL write_power_z(k,z,powz,nk,nz,output)

        !Initialise the lensing part of the calculation
        CALL initialise_distances(cosi)

        !Fill out the projection kernels
        CALL fill_projection_kernels(ik,inz,proj,lens,cosi)

        !Write to screen
        WRITE(*,*) 'HMx: Computing C(l)'
        WRITE(*,*) 'HMx: ell min:', ell(1)
        WRITE(*,*) 'HMx: ell max:', ell(nl)
        WRITE(*,*) 'HMx: number of ell:', nl
        WRITE(*,*)

        zmin=0.d0
        zmax=1.d0
        nnz=8

        DO i=0,nnz

           IF(i==0) THEN
              !z1=0.d0
              !z2=3.99d0 !Just less than z=4 to avoid rounding error
              r1=0.d0
              r2=proj%rs
           ELSE
              IF(icumulative==0) THEN
                 z1=zmin+(zmax-zmin)*float(i-1)/float(nnz)           
              ELSE IF(icumulative==1) THEN
                 z1=zmin
              END IF
              z2=zmin+(zmax-zmin)*float(i)/float(nnz)
              r1=find(z1,cosi%z_r,cosi%r,cosi%nr,3,3,2)
              r2=find(z2,cosi%z_r,cosi%r,cosi%nr,3,3,2)
           END IF

           WRITE(*,*) 'HMx:', i
           IF(i>0) THEN
              WRITE(*,*) 'HMx: z1', REAL(z1)
              WRITE(*,*) 'HMx: z2', REAL(z2)
           END IF
           WRITE(*,*) 'HMx: r1 [Mpc/h]', REAL(r1)
           WRITE(*,*) 'HMx: r2 [Mpc/h]', REAL(r2)

           !Loop over all types of C(l) to create
           DO j=1,4

              !Set output files
              IF(j==1) ext='_cl_linear.dat'
              IF(j==2) ext='_cl_2halo.dat'
              IF(j==3) ext='_cl_1halo.dat'
              IF(j==4) ext='_cl_full.dat'
              base=TRIM(dir)//'redshift_'
              mid='_'
              IF(i==0) THEN
                 IF(j==1) output=TRIM(dir)//'cl_linear.dat'
                 IF(j==2) output=TRIM(dir)//'cl_2halo.dat'
                 IF(j==3) output=TRIM(dir)//'cl_1halo.dat'
                 IF(j==4) output=TRIM(dir)//'cl_full.dat'
              ELSE
                 IF(icumulative==0) THEN
                    output=number_file2(base,i-1,mid,i,ext)
                 ELSE IF(icumulative==1) THEN
                    output=number_file2(base,0,mid,i,ext)
                 END IF
              END IF
              WRITE(*,*) 'HMx: Output: ', TRIM(output)

              CALL calculate_Cell(r1,r2,ell,Cell,nl,k,z,powz(j,:,:),nk,nz,proj,cosi)
              CALL write_Cell(ell,Cell,nl,output)

           END DO
           WRITE(*,*)

        END DO

        WRITE(*,*) 'HMx: Done'
        WRITE(*,*)

     ELSE IF(imode==11) THEN

        !Breakdown the correlation in terms of halo radius

        !Normalises power spectrum (via sigma_8) and fills sigma(R) look-up tables
        CALL initialise_cosmology(cosi)

        !Write the cosmological parameters to the screen
        CALL write_cosmology(cosi)

        !Initialise the lensing part of the calculation
        CALL initialise_distances(cosi)

        !Fill out the projection kernels
        CALL fill_projection_kernels(ik,inz,proj,lens,cosi)

        DO i=0,6
           IF(icumulative==0) THEN
              !Set the mass intervals
              IF(i==0) THEN
                 m1=mmin
                 m2=mmax
              ELSE IF(i==1) THEN
                 m1=mmin
                 m2=1d11
              ELSE IF(i==2) THEN
                 m1=1d11
                 m2=1d12
              ELSE IF(i==3) THEN
                 m1=1d12
                 m2=1d13
              ELSE IF(i==4) THEN
                 m1=1d13
                 m2=1d14
              ELSE IF(i==5) THEN
                 m1=1d14
                 m2=1d15
              ELSE IF(i==6) THEN
                 m1=1d15
                 m2=1d16
              END IF
           ELSE IF(icumulative==1) THEN
              !Set the mass intervals
              IF(i==0) THEN
                 m1=mmin
                 m2=mmax
              ELSE IF(i==1) THEN
                 m1=mmin
                 m2=1d11
              ELSE IF(i==2) THEN
                 m1=mmin
                 m2=1d12
              ELSE IF(i==3) THEN
                 m1=mmin
                 m2=1d13
              ELSE IF(i==4) THEN
                 m1=mmin
                 m2=1d14
              ELSE IF(i==5) THEN
                 m1=mmin
                 m2=1d15
              ELSE IF(i==6) THEN
                 m1=mmin
                 m2=1d16
              END IF
           ELSE
              STOP 'HMx: Error, icumulative not set correctly.'
           END IF

           !Set the code to not 'correct' the two-halo power for missing
           !mass when doing the calcultion binned in halo mass
           IF(icumulative==0 .AND. i>1) ip2h=0

           WRITE(*,fmt='(A16)') 'HMx: Mass range'
           WRITE(*,fmt='(A16,I5)') 'HMx: Iteration:', i
           WRITE(*,fmt='(A21,2ES15.7)') 'HMx: M_min [Msun/h]:', m1
           WRITE(*,fmt='(A21,2ES15.7)') 'HMx: M_max [Msun/h]:', m2
           WRITE(*,*)

           !Loop over redshifts
           DO j=1,nz

              !Initiliasation for the halomodel calcualtion
              CALL halomod_init(m1,m2,z(j),lut,cosi)
              CALL calculate_halomod(ip(1),ip(2),k,nk,z(j),powz(:,:,j),lut,cosi)

              !Write progress to screen
              IF(j==1) THEN
                 WRITE(*,fmt='(A5,A7)') 'i', 'z'
                 WRITE(*,fmt='(A13)') '   ============'
              END IF
              WRITE(*,fmt='(I5,F8.3)') j, z(j)

           END DO
           WRITE(*,fmt='(A13)') '   ============'
           WRITE(*,*)

           IF(i==0) THEN
              output=TRIM(dir)//'power'
           ELSE
              base=TRIM(dir)//'mass_'
              mid='_'
              ext='_power'
              output=number_file2(base,NINT(log10(m1)),mid,NINT(log10(m2)),ext)
           END IF
           WRITE(*,*) 'HMx: File: ', TRIM(output)
           CALL write_power_z(k,z,powz,nk,nz,output)

           !Loop over all types of C(l) to create
           DO j=1,4

              !Skip the 1-halo C(l) because it takes ages (06/02/16)
              IF(j==3) CYCLE

              !Set output files
              IF(i==0) THEN
                 IF(j==1) output=TRIM(dir)//'cl_linear.dat'
                 IF(j==2) output=TRIM(dir)//'cl_2halo.dat'
                 IF(j==3) output=TRIM(dir)//'cl_1halo.dat'
                 IF(j==4) output=TRIM(dir)//'cl_full.dat'
              ELSE
                 base=TRIM(dir)//'mass_'
                 mid='_'        
                 IF(j==1) ext='_cl_linear.dat'
                 IF(j==2) ext='_cl_2halo.dat'
                 IF(j==3) ext='_cl_1halo.dat'
                 IF(j==4) ext='_cl_full.dat'
                 output=number_file2(base,NINT(log10(m1)),mid,NINT(log10(m2)),ext)
              END IF

              WRITE(*,*) 'HMx: File: ', TRIM(output)

              CALL calculate_Cell(0.d0,proj%rs,ell,Cell,nl,k,z,powz(j,:,:),nk,nz,proj,cosi)
              CALL write_Cell(ell,Cell,nl,output)

           END DO
           WRITE(*,*) 'Done'
           WRITE(*,*)

        END DO

     ELSE

        STOP 'Error, you have specified the mode incorrectly'

     END IF

  ELSE

     STOP 'Error, you have specified the mode incorrectly'

  END IF

CONTAINS

  SUBROUTINE write_nz(lens,output)

    IMPLICIT NONE
    TYPE(lensing), INTENT(IN) :: lens
    CHARACTER(len=256), INTENT(IN) :: output
    INTEGER :: i

    OPEN(7,file=output)
    DO i=1,lens%nnz
       WRITE(7,*) lens%z_nz(i), lens%nz(i)
    END DO
    CLOSE(7)

  END SUBROUTINE write_nz

  SUBROUTINE fill_projection_kernels(ik,inz,proj,lens,cosm)

    IMPLICIT NONE
    INTEGER, INTENT(IN) :: ik(2)
    INTEGER, INTENT(INOUT) :: inz(2)
    TYPE(cosmology), INTENT(IN) :: cosm
    TYPE(lensing), INTENT(IN) :: lens
    TYPE(projection) :: proj
    INTEGER :: nk, i

    IF(ik(1)==ik(2) .AND. inz(1)==inz(2)) THEN
       nk=1
    ELSE
       nk=2
    END IF

    !Loop over the two kernels
    DO i=1,nk
       !Fill out the projection kernels
       !Repetition is a bit ugly, but probably cannot be avoided because the size
       !of the projection X and r_X arrays will be different in general
       IF(i==1) THEN        
          IF(ik(i)==1) CALL fill_lensing_kernel(inz(i),proj%r_x1,proj%x1,proj%nx1,lens,cosm)
          IF(ik(i)==2) CALL fill_y_kernel(proj%r_x1,proj%x1,proj%nx1,cosm)
       ELSE IF(i==2) THEN
          IF(ik(i)==1) CALL fill_lensing_kernel(inz(i),proj%r_x2,proj%x2,proj%nx2,lens,cosm)
          IF(ik(i)==2) CALL fill_y_kernel(proj%r_x2,proj%x2,proj%nx2,cosm)
       END IF
    END DO

    !In case the autospectrum is being considered
    IF(nk==1) THEN
       proj%nx2=proj%nx1
       IF(ALLOCATED(proj%r_x2)) DEALLOCATE(proj%r_x2)
       IF(ALLOCATED(proj%x2))   DEALLOCATE(proj%x2)
       ALLOCATE(proj%r_x2(proj%nx2),proj%x2(proj%nx2))
       proj%r_x2=proj%r_x1
       proj%x2=proj%x1
    END IF

    !Get the maximum distance to be considered for the Limber integral
    CALL maxdist(proj,cosi)

  END SUBROUTINE fill_projection_kernels

  SUBROUTINE calculate_Cell(r1,r2,ell,Cell,nl,k,z,pow,nk,nz,proj,cosm)

    !Calculates C(l) using the Limber approximation
    IMPLICIT NONE
    INTEGER, INTENT(IN) :: nl, nk, nz
    REAL*8, INTENT(IN) :: ell(nl)
    REAL*8, INTENT(OUT) :: Cell(nl)
    REAL*8, INTENT(IN) :: k(nk), z(nz), pow(nk,nz)
    REAL*8, INTENT(IN) :: r1, r2
    TYPE(projection), INTENT(IN) :: proj
    TYPE(cosmology), INTENT(IN) :: cosm
    INTEGER :: i
    !REAL*8, PARAMETER :: acc=1d-4

    !Note that using Limber and flat-sky for sensible results lmin to ~10

    IF(ihm==1) THEN
       WRITE(*,*) 'CALCULATE_CELL: lmin', REAL(ell(1))
       WRITE(*,*) 'CALCULATE_CELL: lmax', REAL(ell(nl))
       WRITE(*,*) 'CALCULATE_CELL: nl', nl
       WRITE(*,*) 'CALCULATE_CELL: nk', nk
       WRITE(*,*) 'CALCULATE_CELL: nz', nz
       WRITE(*,*) 'CALCULATE_CELL: Minimum distance [Mpc/h]:', REAL(r1)
       WRITE(*,*) 'CALCULATE_CELL: Maximum distance [Mpc/h]:', REAL(r2)
    END IF

    IF(ihm==1) WRITE(*,*) 'CALCULATE CELL: Doing calculation'
    DO i=1,nl
       Cell(i)=integrate_Limber(ell(i),r1,r2,k,z,pow,nk,nz,acc,3,proj,cosm)
    END DO
    IF(ihm==1) THEN
       WRITE(*,*) 'CALCULATE_CELL: Done'
       WRITE(*,*)
    END IF

  END SUBROUTINE calculate_Cell

  SUBROUTINE write_Cell(ell,Cell,nl,output)

    IMPLICIT NONE
    INTEGER, INTENT(IN) :: nl
    REAL*8, INTENT(IN) :: ell(nl), Cell(nl)
    CHARACTER(len=256) :: output
    INTEGER :: i

    OPEN(7,file=output)
    DO i=1,nl
       WRITE(7,*) ell(i), Cell(i), ell(i)*(1.+ell(i))*Cell(i)/(2.d0*pi)
    END DO
    CLOSE(7)

  END SUBROUTINE write_Cell

  SUBROUTINE calculate_xi(th_tab,xi_tab,nth,l_tab,cl_tab,nl,lmax)

    USE nr
    IMPLICIT NONE
    REAL*8, INTENT(IN) :: l_tab(nl), cl_tab(nl)
    REAL*8, INTENT(OUT) :: th_tab(nth), xi_tab(3,nth)
    INTEGER, INTENT(IN) :: nl, lmax, nth
    INTEGER :: i, j
    REAL*8 :: theta, Cl, l, xi0, xi2, xi4
    REAL*8, PARAMETER :: rad2deg=180.d0/pi

    !WRITE(*,*) 'CALCULATE_XI: Computing correlation functions via sum'
    DO i=1,nth

       !Get theta value and convert from degrees to radians
       theta=th_tab(i)/rad2deg
       
       !Set values to zero before summing
       xi0=0.d0
       xi2=0.d0
       xi4=0.d0

       !Do the conversion from Cl to xi as a summation over integer ell
       DO j=1,lmax

          l=DBLE(j)
          Cl=exp(find(log(l),log(l_tab),log(Cl_tab),nl,3,3,2))
          
          xi0=xi0+(2.d0*l+1.d0)*Cl*Bessel(0,l*theta)
          xi2=xi2+(2.d0*l+1.d0)*Cl*Bessel(2,l*theta)
          xi4=xi4+(2.d0*l+1.d0)*Cl*Bessel(4,l*theta)

       END DO

       !Divide by correct pre-factor
       xi0=xi0/(4.d0*pi)
       xi2=xi2/(4.d0*pi)
       xi4=xi4/(4.d0*pi)

       !Convert theta from radians to degrees
       theta=theta*rad2deg

       !Populate tables
       th_tab(i)=theta
       xi_tab(1,i)=xi0
       xi_tab(2,i)=xi2
       xi_tab(3,i)=xi4

    END DO
    !WRITE(*,*) 'CALCULATE_XI: Done'
    !WRITE(*,*)

  END SUBROUTINE calculate_xi

  SUBROUTINE write_xi(th_tab,xi_tab,nth,output)

    IMPLICIT NONE
    REAL*8, INTENT(IN) :: th_tab(nth), xi_tab(3,nth)
    INTEGER, INTENT(IN) :: nth
    CHARACTER(len=256), INTENT(IN) :: output
    
    OPEN(7,file=output)
    DO i=1,nth
       WRITE(7,*) th_tab(i), xi_tab(1,i), xi_tab(2,i), xi_tab(3,i)
    END DO
    CLOSE(7)
    
  END SUBROUTINE write_xi

  FUNCTION Bessel(n,x)

    USE nr
    IMPLICIT NONE
    REAL*8 :: Bessel
    REAL*8 :: x
    INTEGER :: n
    REAL, PARAMETER :: xlarge=1.d15

    IF(x>xlarge) THEN

       !To stop it going mental for very large values of x
       Bessel=0.d0

    ELSE

       IF(n<0) STOP 'Error: cannot call for negative n'

       IF(n==0) THEN
          Bessel=bessj0(REAL(x))
       ELSE IF(n==1) THEN
          Bessel=bessj1(REAL(x))
       ELSE
          Bessel=bessj(n,REAL(x))      
       END IF

    END IF

  END FUNCTION Bessel

  SUBROUTINE calculate_halomod(itype1,itype2,k,nk,z,pow,lut,cosm)

    IMPLICIT NONE
    INTEGER, INTENT(IN) :: itype1, itype2
    INTEGER, INTENT(IN) :: nk
    REAL*8, INTENT(IN) :: k(nk), z
    REAL*8, INTENT(OUT) :: pow(4,nk)
    TYPE(cosmology), INTENT(IN) :: cosm
    TYPE(tables), INTENT(IN) :: lut
    INTEGER :: i, j

    !Write to screen
    IF(ihm==1) THEN
       WRITE(*,*) 'CALCULATE_HALOMOD: k min:', k(1)
       WRITE(*,*) 'CALCULATE_HALOMOD: k max:', k(nk)
       WRITE(*,*) 'CALCULATE_HALOMOD: number of k:', nk
       WRITE(*,*) 'CALCULATE_HALOMOD: z:', z
    END IF

    IF(ihm==1) WRITE(*,*) 'CALCULATE_HALOMOD: Calculating halo-model power spectrum'

    !Loop over k values
    !ADD OMP support properly. What is private and shared? CHECK THIS!
    !!$OMP PARALLEL DO DEFAULT(SHARED), private(k,plin, pfull,p1h,p2h)
    DO i=1,nk

       !Get the linear power
       plin=p_lin(k(i),z,cosi)
       pow(1,i)=plin

       !Do the halo model calculation
       CALL halomod(itype1,itype2,k(i),z,pow(2,i),pow(3,i),pow(4,i),plin,lut,cosi)

    END DO
    !!$OMP END PARALLEL DO

    IF(ihm==1) THEN
       WRITE(*,*) 'CALCULATE_HALOMOD: Done'
       WRITE(*,*)
    END IF

  END SUBROUTINE calculate_halomod

  SUBROUTINE write_power(k,z,pow,nk,output)

    IMPLICIT NONE
    CHARACTER(len=256), INTENT(IN) :: output
    INTEGER, INTENT(IN) :: nk
    REAL*8, INTENT(IN) :: z, k(nk), pow(4,nk)
    REAL*8 :: plin
    INTEGER :: i

    IF(ihm==1) WRITE(*,*) 'WRITE_POWER: Writing power to ', TRIM(output)

    !Loop over k values
    OPEN(7,file=output)
    DO i=1,nk

       !Fill the tables with one- and two-halo terms as well as total
       WRITE(7,fmt='(5ES20.10)') k(i), pow(1,i), pow(2,i), pow(3,i), pow(4,i)

    END DO
    CLOSE(7)

    IF(ihm==1) THEN
       WRITE(*,*) 'WRITE_POWER: Done'
       WRITE(*,*)
    END IF

  END SUBROUTINE write_power

  SUBROUTINE write_power_z(k,z,pow,nk,nz,base)

    IMPLICIT NONE
    CHARACTER(len=256), INTENT(IN) :: base
    INTEGER, INTENT(IN) :: nk, nz
    REAL*8, INTENT(IN) :: z(nz), k(nk), pow(4,nk,nz)
    REAL*8 :: plin
    INTEGER :: i, o
    CHARACTER(len=256) :: output_2halo, output_1halo, output_full, output_lin, output

    output_lin=TRIM(base)//'_linear.dat'
    output_2halo=TRIM(base)//'_2halo.dat'
    output_1halo=TRIM(base)//'_1halo.dat'
    output_full=TRIM(base)//'_full.dat'

    !Write out data to files
    IF(ihm==1) THEN
       WRITE(*,*) 'WRITE_POWER_Z: Writing 2-halo power to ', TRIM(output_2halo)
       WRITE(*,*) 'WRITE_POWER_Z: Writing 1-halo power to ', TRIM(output_1halo)
       WRITE(*,*) 'WRITE_POWER_Z: Writing full power to ',   TRIM(output_full)
       WRITE(*,*) 'WRITE_POWER_Z: The top row of the file contains the redshifts (the first entry is hashes - #####)'
       WRITE(*,*) 'WRITE_POWER_Z: Subsequent rows contain ''k'' and then the halo-model power for each redshift'
    END IF

    DO o=1,4
       IF(o==1) output=output_lin
       IF(o==2) output=output_2halo
       IF(o==3) output=output_1halo
       IF(o==4) output=output_full
       OPEN(7,file=output)
       DO i=0,nk
          IF(i==0) THEN
             WRITE(7,fmt='(A20,40F20.10)') '#####', (z(j), j=1,nz)
          ELSE
             WRITE(7,fmt='(F20.10,40E20.10)') k(i), (pow(o,i,j), j=1,nz)
          END IF
       END DO
       CLOSE(7)
    END DO

    IF(ihm==1) THEN
       WRITE(*,*) 'WRITE_POWER_Z: Done'
       WRITE(*,*)
    END IF

  END SUBROUTINE write_power_z

  FUNCTION number_file(fbase,i,fext)

    IMPLICIT NONE
    CHARACTER(len=256) ::number_file
    CHARACTER(len=256), INTENT(IN) :: fbase, fext
    INTEGER, INTENT(IN) :: i
    CHARACTER(len=8) :: num

    !IF(i<0) STOP 'NUMBER_FILE: Error: cannot write negative number file names'

    IF(i<10) THEN       
       WRITE(num,fmt='(I1)') i
    ELSE IF(i<100) THEN
       WRITE(num,fmt='(I2)') i
    ELSE IF(i<1000) THEN
       WRITE(num,fmt='(I3)') i
    END IF

    number_file=TRIM(fbase)//TRIM(num)//TRIM(fext)

  END FUNCTION number_file

  FUNCTION number_file2(fbase,i1,mid,i2,fext)

    IMPLICIT NONE
    CHARACTER(len=256) ::number_file2
    CHARACTER(len=256), INTENT(IN) :: fbase, fext, mid
    INTEGER, INTENT(IN) :: i1, i2
    CHARACTER(len=8) :: num1, num2

    !IF(i<0) STOP 'NUMBER_FILE: Error: cannot write negative number file names'

    IF(i1<10) THEN       
       WRITE(num1,fmt='(I1)') i1
    ELSE IF(i1<100) THEN
       WRITE(num1,fmt='(I2)') i1
    ELSE IF(i1<1000) THEN
       WRITE(num1,fmt='(I3)') i1
    END IF

    IF(i2<10) THEN       
       WRITE(num2,fmt='(I1)') i2
    ELSE IF(i2<100) THEN
       WRITE(num2,fmt='(I2)') i2
    ELSE IF(i2<1000) THEN
       WRITE(num2,fmt='(I3)') i2
    END IF

    number_file2=TRIM(fbase)//TRIM(num1)//TRIM(mid)//TRIM(num2)//TRIM(fext)

  END FUNCTION number_file2

  SUBROUTINE diagnostics(z,lut,cosm)

    IMPLICIT NONE
    TYPE(cosmology), INTENT(IN) :: cosm
    TYPE(tables), INTENT(IN) :: lut
    REAL*8, INTENT(IN) :: z
    CHARACTER(len=256) :: outfile    

    !CALL halomod_init(mmin,mmax,z,lut,cosm)

    !WRITE(*,*) 'Diagnostics 1'

    outfile='diagnostics/mass_fractions.dat'
    CALL write_mass_fractions(cosm,outfile)

    !WRITE(*,*) 'Diagnostics 2'

    outfile='diagnostics/halo_profile_m13.dat'
    CALL write_halo_profiles(1d13,z,lut,cosm,outfile)

    !WRITE(*,*) 'Diagnostics 3'

    outfile='diagnostics/halo_profile_m14.dat'
    CALL write_halo_profiles(1d14,z,lut,cosm,outfile)

    !WRITE(*,*) 'Diagnostics 4'

    outfile='diagnostics/halo_profile_m15.dat'
    CALL write_halo_profiles(1d15,z,lut,cosm,outfile)

    !WRITE(*,*) 'Diagnostics 5'

    !outfile='diagnostics/halo_profile_m13noh.dat'
    !CALL write_halo_profiles(cosm%h*1d13,z,lut,cosm,outfile)

    !outfile='diagnostics/halo_profile_m14noh.dat'
    !CALL write_halo_profiles(cosm%h*1d14,z,lut,cosm,outfile)

    !outfile='diagnostics/halo_profile_m15noh.dat'
    !CALL write_halo_profiles(cosm%h*1d15,z,lut,cosm,outfile)

    outfile='diagnostics/halo_window_m13.dat'
    CALL write_halo_transforms(1d13,z,lut,cosm,outfile)

    !WRITE(*,*) 'Diagnostics 6'

    outfile='diagnostics/halo_window_m14.dat'
    CALL write_halo_transforms(1d14,z,lut,cosm,outfile)

    !WRITE(*,*) 'Diagnostics 7'

    outfile='diagnostics/halo_window_m15.dat'
    CALL write_halo_transforms(1d15,z,lut,cosm,outfile)

    OPEN(7,file='definitions/radius.dat')
    OPEN(8,file='definitions/mass.dat')
    OPEN(9,file='definitions/concentration.dat')
    DO i=1,lut%n
       WRITE(7,*) lut%rv(i), lut%r200(i), lut%r500(i), lut%r200c(i), lut%r500c(i)
       WRITE(8,*) lut%m(i),  lut%m200(i), lut%m500(i), lut%m200c(i), lut%m500c(i)
       WRITE(9,*) lut%c(i),  lut%c200(i), lut%c500(i), lut%c200c(i), lut%c500c(i)
    END DO
    CLOSE(7)
    CLOSE(8)
    CLOSE(9)

    !WRITE(*,*) 'Diagnostics 8'

  END SUBROUTINE diagnostics

  SUBROUTINE write_mass_fractions(cosm,outfile)

    IMPLICIT NONE
    CHARACTER(len=256), INTENT(IN) :: outfile
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8 :: m, mmin, mmax
    INTEGER :: i, n

    mmin=1d10
    mmax=1d16
    n=101

    OPEN(7,file=outfile)
    DO i=1,n
       m=exp(log(mmin)+log(mmax/mmin)*float(i-1)/float(n-1))
       WRITE(7,*) m, halo_fraction(1,m,cosm), halo_fraction(2,m,cosm), halo_fraction(3,m,cosm), halo_fraction(4,m,cosm), halo_fraction(5,m,cosm)
    END DO
    CLOSE(7)

  END SUBROUTINE write_mass_fractions

  SUBROUTINE write_halo_profiles(m,z,lut,cosm,outfile)

    IMPLICIT NONE
    CHARACTER(len=256), INTENT(IN) :: outfile
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8, INTENT(IN) :: m, z
    REAL*8 :: x, r, rv, rs, c
    INTEGER :: i
    TYPE(tables), INTENT(IN) :: lut
    REAL*8, PARAMETER :: xmin=1d-3 !Mininum r/rv
    REAL*8, PARAMETER :: xmax=1d1 !Maximum r/rv
    INTEGER, PARAMETER :: n=201 !Number of points

    !Calculate halo attributes
    rv=exp(find(log(m),log(lut%m),log(lut%rv),lut%n,3,3,2))
    c=find(log(m),log(lut%m),lut%c,lut%n,3,3,2)
    !c=2.*c !To mimic baryonic contraction, or some such bullshit
    rs=rv/c

    !Max and min r/rv and number of points
    !xmin=1d-3
    !xmax=1d1
    !n=201

    OPEN(7,file=outfile)
    DO i=1,n
       x=exp(log(xmin)+log(xmax/xmin)*float(i-1)/float(n-1))
       r=x*rv
       WRITE(7,*) r, win_type(0,1,r,m,rv,rs,z,lut,cosm), win_type(0,2,r,m,rv,rs,z,lut,cosm), win_type(0,3,r,m,rv,rs,z,lut,cosm), win_type(0,4,r,m,rv,rs,z,lut,cosm), win_type(0,5,r,m,rv,rs,z,lut,cosm), win_type(0,6,r,m,rv,rs,z,lut,cosm)
    END DO
    CLOSE(7)

  END SUBROUTINE write_halo_profiles

  SUBROUTINE write_halo_transforms(m,z,lut,cosm,outfile)

    IMPLICIT NONE
    CHARACTER(len=256), INTENT(IN) :: outfile
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8, INTENT(IN) :: m, z
    TYPE(tables), INTENT(IN) :: lut
    REAL*8 :: x, rv, c, rs, k, rhobar
    INTEGER :: i  
    REAL*8, PARAMETER :: xmin=1d-1 !Mininum r/rv
    REAL*8, PARAMETER :: xmax=1d2 !Maximum r/rv
    INTEGER, PARAMETER :: n=201 !Number of points

    !Calculate halo attributes
    rv=exp(find(log(m),log(lut%m),log(lut%rv),lut%n,3,3,2))
    c=find(log(m),log(lut%m),lut%c,lut%n,3,3,2)
    !c=2.*c !To mimic baryonic contraction, or some such bullshit
    rs=rv/c

    !Max and min k*rv and number of points
    !xmin=1d-1
    !xmax=1d2
    !n=201

    rhobar=matter_density(cosm)

    OPEN(7,file=outfile)
    DO i=1,n
       x=exp(log(xmin)+log(xmax/xmin)*float(i-1)/float(n-1))
       k=x/rv
       WRITE(7,*) x, win_type(1,1,k,m,rv,rs,z,lut,cosm)*rhobar/m, win_type(1,2,k,m,rv,rs,z,lut,cosm)*rhobar/m, win_type(1,3,k,m,rv,rs,z,lut,cosm)*rhobar/m, win_type(1,4,k,m,rv,rs,z,lut,cosm)*rhobar/m, win_type(1,5,k,m,rv,rs,z,lut,cosm)*rhobar/m
    END DO
    CLOSE(7)

  END SUBROUTINE write_halo_transforms

  FUNCTION Delta_v(z,cosm)

    IMPLICIT NONE
    REAL*8 :: Delta_v
    REAL*8, INTENT(IN) :: z
    TYPE(cosmology), INTENT(IN) :: cosm

    !Virialised overdensity
    IF(imead==0 .OR. imead==-1) THEN
       !Delta_v=200.
       Delta_v=Dv_brynor(z,cosm)
    ELSE IF(imead==1) THEN
       Delta_v=418.*(omega_m(z,cosm)**(-0.352))
    ELSE
       STOP 'Error, imead defined incorrectly'
    END IF

  END FUNCTION Delta_v

  FUNCTION Dv_brynor(z,cosm)

    !Bryan & Norman (1998) spherical over-density calculation
    IMPLICIT NONE
    REAL*8 :: Dv_brynor
    REAL*8 :: x, om_m
    REAL*8, INTENT(IN) :: z
    TYPE(cosmology), INTENT(IN) :: cosm

    om_m=omega_m(z,cosm)
    x=om_m-1.

    IF(cosm%om_v==0.) THEN
       STOP 'Dv_BRYNOR: Should not be in here'
       !Open model results
       Dv_brynor=177.65+60.*x-32.*x**2
       Dv_brynor=dv_brynor/om_m
    ELSE
       !LCDM results
       Dv_brynor=177.65+82.*x-39.*x**2
       Dv_brynor=dv_brynor/om_m
    END IF

  END FUNCTION Dv_brynor

  FUNCTION delta_c(z,cosm)

    IMPLICIT NONE
    REAL*8 :: delta_c
    REAL*8, INTENT(IN) :: z
    TYPE(cosmology), INTENT(IN) :: cosm

    !Linear collapse density
    IF(imead==0 .OR. imead==-1) THEN
       !Nakamura & Suto (1997) fitting formula for LCDM
       delta_c=1.686*(1.+0.0123*log10(omega_m(z,cosm)))
    ELSE IF(imead==1) THEN
       delta_c=1.59+0.0314*log(sigma_cb(8.d0,z,cosm))
       delta_c=delta_c*(1.+0.0123*log10(omega_m(z,cosm)))
    ELSE
       STOP 'Error, imead defined incorrectly'
    END IF

  END FUNCTION delta_c

  FUNCTION eta(z,cosm)

    IMPLICIT NONE
    REAL*8 :: eta
    REAL*8, INTENT(IN) :: z
    TYPE(cosmology), INTENT(IN) :: cosm

    IF(imead==0 .OR. imead==-1) THEN
       eta=0.
    ELSE IF(imead==1) THEN
       !The first parameter here is 'eta_0' in Mead et al. (2015; arXiv 1505.07833)
       eta=0.603-0.3*(sigma_cb(8.d0,z,cosm))
    ELSE
       STOP 'Error, imead defined incorrectly'
    END IF

  END FUNCTION eta

  FUNCTION kstar(lut,cosm)

    IMPLICIT NONE
    REAL*8 :: kstar
    TYPE(cosmology), INTENT(IN) :: cosm
    TYPE(tables), INTENT(IN) :: lut

    IF(imead==0 .OR. imead==-1) THEN
       !Set to zero for the standard Poisson one-halo term
       kstar=0.
    ELSE IF(imead==1) THEN
       !One-halo cut-off wavenumber
       kstar=0.584*(lut%sigv)**(-1)
    ELSE
       STOP 'Error, imead defined incorrectly'
    END IF

  END FUNCTION kstar

  FUNCTION As(cosm)

    IMPLICIT NONE
    REAL*8 :: As
    TYPE(cosmology), INTENT(IN) :: cosm

    !Halo concentration pre-factor
    IF(imead==0 .OR. imead==-1) THEN
       !Set to 4 for the standard Bullock value
       As=4.
    ELSE IF(imead==1) THEN
       !This is the 'A' halo-concentration parameter in Mead et al. (2015; arXiv 1505.07833)
       As=3.13
    ELSE
       STOP 'Error, imead defined incorrectly'
    END IF

  END FUNCTION As

  FUNCTION fdamp(z,cosm)

    IMPLICIT NONE
    REAL*8 ::fdamp
    REAL*8, INTENT(IN) :: z
    TYPE(cosmology), INTENT(IN) :: cosm

    !Linear theory damping factor
    IF(imead==0 .OR. imead==-1) THEN
       !Set to 0 for the standard linear theory two halo term
       fdamp=0.
    ELSE IF(imead==1) THEN
       !fdamp=0.188*sigma_cb(8.,z,cosm)**4.29
       fdamp=0.0095*lut%sigv100**1.37
       !Catches extreme values of fdamp that occur for ridiculous cosmologies
       IF(fdamp<1.e-3) fdamp=0.
       IF(fdamp>0.99)  fdamp=0.99
    ELSE
       STOP 'Error, imead defined incorrectly'
    END IF

  END FUNCTION fdamp

  FUNCTION alpha_trans(lut,cosm)

    IMPLICIT NONE
    REAL*8 :: alpha_trans
    TYPE(tables), INTENT(IN) :: lut
    TYPE(cosmology), INTENT(IN) :: cosm

    IF(imead==0 .OR. imead==-1) THEN
       !Set to 1 for the standard halo model addition of one- and two-halo terms
       alpha_trans=1.
    ELSE IF(imead==1) THEN
       !This uses the top-hat defined neff
       alpha_trans=3.24*1.85**lut%neff
    ELSE
       STOP 'Error, imead defined incorrectly'
    END IF

    !Catches values of alpha that are crazy
    IF(alpha_trans>2.)  alpha_trans=2.
    IF(alpha_trans<0.5) alpha_trans=0.5

  END FUNCTION alpha_trans

  SUBROUTINE write_parameters(z,lut,cosm)

    IMPLICIT NONE
    REAL*8, INTENT(IN) :: z
    TYPE(cosmology), INTENT(IN) :: cosm
    TYPE(tables), INTENT(IN) :: lut

    !This subroutine writes out the physical parameters at some redshift 
    !(e.g. Delta_v) rather than the model parameters

    WRITE(*,*) 'WRITE_PARAMETERS: Writing out halo-model parameters'
    WRITE(*,*) 'WRITE_PARAMETERS: Halo-model parameters at your redshift'
    WRITE(*,*) '==========================='
    WRITE(*,fmt='(A10,F10.5)') 'z:', z
    WRITE(*,fmt='(A10,F10.5)') 'Dv:', Delta_v(z,cosm)
    WRITE(*,fmt='(A10,F10.5)') 'dc:', delta_c(z,cosm)
    WRITE(*,fmt='(A10,F10.5)') 'eta:', eta(z,cosm)
    WRITE(*,fmt='(A10,F10.5)') 'k*:', kstar(lut,cosm)
    WRITE(*,fmt='(A10,F10.5)') 'A:', As(cosm)
    WRITE(*,fmt='(A10,F10.5)') 'fdamp:', fdamp(z,cosm)
    WRITE(*,fmt='(A10,F10.5)') 'alpha:', alpha_trans(lut,cosm)
    WRITE(*,*) '==========================='
    WRITE(*,*) 'WRITE_PARAMETERS: Done'
    WRITE(*,*)

  END SUBROUTINE write_parameters

  FUNCTION r_nl(lut)

    !Calculates k_nl as 1/R where nu(R)=1.
    TYPE(tables), INTENT(IN) :: lut
    REAL*8 :: r_nl  

    IF(lut%nu(1)>1.) THEN
       !This catches some very strange values
       r_nl=lut%rr(1)
    ELSE
       r_nl=exp(find(log(1.d0),log(lut%nu),log(lut%rr),lut%n,3,3,2))
    END IF

  END FUNCTION r_nl

  SUBROUTINE fill_table(min,max,arr,n)

    !Fills array 'arr' in equally spaced intervals
    !I'm not sure if inputting an array like this is okay
    IMPLICIT NONE
    INTEGER :: i
    REAL*8, INTENT(IN) :: min, max
    REAL*8, ALLOCATABLE :: arr(:)
    INTEGER, INTENT(IN) :: n

    !Allocate the array, and deallocate it if it is full
    IF(ALLOCATED(arr)) DEALLOCATE(arr)
    ALLOCATE(arr(n))
    arr=0.

    IF(n==1) THEN
       arr(1)=min
    ELSE IF(n>1) THEN
       DO i=1,n
          arr(i)=min+(max-min)*DBLE(i-1)/DBLE(n-1)
       END DO
    END IF

  END SUBROUTINE fill_table

  SUBROUTINE write_cosmology(cosm)

    IMPLICIT NONE
    TYPE(cosmology) :: cosm

    IF(ihm==1) WRITE(*,*) 'COSMOLOGY: ', TRIM(cosm%name)
    IF(ihm==1) WRITE(*,fmt='(A11,A15,F11.5)') 'COSMOLOGY:', 'Omega_m:', cosm%om_m
    IF(ihm==1) WRITE(*,fmt='(A11,A15,F11.5)') 'COSMOLOGY:', 'Omega_b:', cosm%om_b
    IF(ihm==1) WRITE(*,fmt='(A11,A15,F11.5)') 'COSMOLOGY:', 'Omega_c:', cosm%om_c
    IF(ihm==1) WRITE(*,fmt='(A11,A15,F11.5)') 'COSMOLOGY:', 'Omega_v:', cosm%om_v
    IF(ihm==1) WRITE(*,fmt='(A11,A15,F11.5)') 'COSMOLOGY:', 'h:', cosm%h
    IF(ihm==1) WRITE(*,fmt='(A11,A15,F11.5)') 'COSMOLOGY:', 'w_0:', cosm%w
    IF(ihm==1) WRITE(*,fmt='(A11,A15,F11.5)') 'COSMOLOGY:', 'w_a:', cosm%wa
    IF(ihm==1) WRITE(*,fmt='(A11,A15,F11.5)') 'COSMOLOGY:', 'sig8:', cosm%sig8
    IF(ihm==1) WRITE(*,fmt='(A11,A15,F11.5)') 'COSMOLOGY:', 'n:', cosm%n
    IF(ihm==1) WRITE(*,fmt='(A11,A15,F11.5)') 'COSMOLOGY:', 'Omega:', cosm%om
    !IF(ihm==1) WRITE(*,fmt='(A11,A15,F10.5)') 'COSMOLOGY:', 'k / (Mpc/h)^-2:', cosm%k
    IF(ihm==1) WRITE(*,fmt='(A11,A15,F11.5)') 'COSMOLOGY:', 'z_CMB:', cosm%z_cmb
    IF(ihm==1) WRITE(*,*)

  END SUBROUTINE write_cosmology

  SUBROUTINE assign_cosmology(icosmo,cosm)

    IMPLICIT NONE
    TYPE(cosmology), INTENT(INOUT) :: cosm
    INTEGER, INTENT(INOUT) :: icosmo
    CHARACTER(len=256) :: names(0:2)

    names(0)='Boring'
    names(1)='WMAP9 (OWLS version)'
    names(2)='Planck 2013 (OWLS version)'

    IF(icosmo==-1) THEN
       WRITE(*,*) 'ASSIGN_COSMOLOGY: Choose cosmological model'
       WRITE(*,*) '==========================================='
       !DO i=0,SIZE(names)-1
       !   WRITE(*,*) i, '- ', TRIM(names(i))
       !END DO
       WRITE(*,*) '0 - Boring'
       WRITE(*,*) '1 - WMAP9 (OWLS version)'
       WRITE(*,*) '2 - Planck 2013 (OWLS version)'
       READ(*,*) icosmo
       WRITE(*,*) '==========================================='
    END IF

    cosm%name=names(icosmo)

    !Boring defaults
    cosm%om_m=0.3
    cosm%om_b=0.05
    cosm%om_v=1.-cosm%om_m
    cosm%om_nu=0.
    cosm%h=0.7
    cosm%sig8=0.8
    cosm%n=0.96
    cosm%w=-1.
    cosm%wa=0.
    cosm%z_cmb=1100.

    IF(icosmo==0) THEN
       !Boring - do nothing
    ELSE IF(icosmo==1) THEN
       !OWLS - WMAP9
       cosm%om_m=0.272
       cosm%om_b=0.0455
       cosm%om_v=1.-cosm%om_m
       cosm%om_nu=0.
       cosm%h=0.704
       cosm%sig8=0.81
       !cosm%sig8=0.797
       !cosm%sig8=0.823
       cosm%n=0.967
    ELSE IF(icosmo==2) THEN
       !OWLS - Planck 2013
       cosm%om_m=0.3175
       cosm%om_b=0.0490
       cosm%om_v=1.-cosm%om_m
       cosm%h=0.6711
       cosm%n=0.9624
       cosm%sig8=0.834
    ELSE
       STOP 'ASSIGN_COSMOLOGY: Error, icosmo not specified correctly'
    END IF

    WRITE(*,*) 'ASSIGN_COSMOLOGY: Cosmology assigned'
    WRITE(*,*)

  END SUBROUTINE assign_cosmology

  SUBROUTINE initialise_cosmology(cosm)

    IMPLICIT NONE
    REAL*8 :: sigi
    TYPE(cosmology) :: cosm

    !Derived cosmological parameters
    cosm%om_c=cosm%om_m-cosm%om_b-cosm%om_nu
    cosm%om=cosm%om_m+cosm%om_v
    cosm%k=(cosm%om-1.)/(conH0**2)

    !Fill the tables of g(z)
    CALL fill_growtab(cosm)

    !Set the normalisation to 1 initially
    cosm%A=1.

    !Calculate the initial sigma_8 value (will not be correct)
    sigi=sigma(8.d0,0.d0,cosm)

    IF(ihm==1) WRITE(*,*) 'INITIALISE COSMOLOGY: Initial sigma_8:', sigi

    !Reset the normalisation to give the correct sigma8
    cosm%A=cosm%sig8/sigi
    !cosm%A=391.0112 !Appropriate for sig8=0.8 in the boring model (for tests)

    !Recalculate sigma8, should be correct this time
    sigi=sigma(8.d0,0.d0,cosm)

    !Write to screen
    IF(ihm==1) THEN
       WRITE(*,*) 'INITIALISE COSMOLOGY: Normalisation factor:', cosm%A
       WRITE(*,*) 'INITIALISE COSMOLOGY: Target sigma_8:', cosm%sig8
       WRITE(*,*) 'INITIALISE COSMOLOGY: Final sigma_8 (calculated):', sigi
       WRITE(*,*) 'INITIALISE COSMOLOGY: Complete'
       WRITE(*,*)
    END IF

    !Fill tables of r vs. sigma(r)
    CALL fill_sigtab(cosm)

  END SUBROUTINE initialise_cosmology

  SUBROUTINE initialise_distances(cosm)

    !Fill up tables of z vs. r(z) (comoving distance)
    IMPLICIT NONE
    TYPE(cosmology), INTENT(INOUT) :: cosm
    REAL*8 :: zmin, zmax
    REAL*8 :: rh
    INTEGER :: i
    CHARACTER(len=256) :: output
    REAL*8, PARAMETER :: zh=1d4 !Redshift considered to be the horizon (sloppy)

    zmin=0.
    zmax=4.
    WRITE(*,*) 'INITIALISE DISTANCE: Redshift range for r(z) tables'
    WRITE(*,*) 'INITIALISE DISTANCE: zmin:', zmin
    WRITE(*,*) 'INITIALISE DISTANCE: zmax:', zmax
    cosm%nr=64
    CALL fill_table(zmin,zmax,cosm%z_r,cosm%nr)
    IF(ALLOCATED(cosm%r)) DEALLOCATE(cosm%r)
    ALLOCATE(cosm%r(cosm%nr))

    !Now do the r(z) calculation
    output='projection/distance.dat'
    WRITE(*,*) 'INITIALISE DISTANCE: Writing r(z): ', TRIM(output)
    OPEN(7,file=output)
    DO i=1,cosm%nr
       cosm%r(i)=integrate_distance(0.d0,cosm%z_r(i),acc,3,cosm)
       WRITE(7,*) cosm%z_r(i), cosm%r(i), f_k(cosm%r(i),cosm)
    END DO
    CLOSE(7)
    WRITE(*,*) 'INITIALISE DISTANCE: rmin [Mpc/h]:', cosm%r(1)
    WRITE(*,*) 'INITIALISE DISTANCE: rmax [Mpc/h]:', cosm%r(cosm%nr)

    !Find the horizon distance in your cosmology
    !This is very lazy, should integrate in 'a' instead from 0->1
    rh=integrate_distance(0.d0,zh,acc,3,cosm)
    WRITE(*,*) 'INITIALISE DISTANCE: Horizon [Mpc/h]:', rh
    WRITE(*,*) 'INITIALISE DISTANCE: Done'
    WRITE(*,*)

  END SUBROUTINE initialise_distances

  SUBROUTINE maxdist(proj,cosm)

    !Calculates the maximum distance necessary for the lensing integration
    IMPLICIT NONE
    TYPE(projection) :: proj
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8 :: rmax1, rmax2
    REAL*8, PARAMETER :: dr=0.01

    !Fix the maximum redshift and distance (which may fixed at source plane)
    rmax1=proj%r_x1(proj%nx1)
    rmax2=proj%r_x2(proj%nx2)
    !Subtract a small distance here because of rounding errors in recalculating zmax
    proj%rs=MIN(rmax1,rmax2)-dr
    proj%zs=find(proj%rs,cosm%r,cosm%z_r,cosm%nr,3,3,2)

    WRITE(*,*) 'MAXDIST: rmax [Mpc/h]:', proj%rs
    WRITE(*,*) 'MAXDIST: zmax:', proj%zs
    WRITE(*,*) 'MAXDIST: Done'
    WRITE(*,*)

  END SUBROUTINE maxdist

  SUBROUTINE write_projection_kernels(proj,cosm)

    IMPLICIT NONE
    TYPE(projection), INTENT(IN) :: proj
    TYPE(cosmology), INTENT(IN) :: cosm
    CHARACTER(len=256) :: output
    INTEGER :: i
    REAL*8 :: r, z

    !Kernel 1
    output=TRIM('projection/kernel1.dat')
    WRITE(*,*) 'WRITE_PROJECTION_KERNEL: Writing out kernel 1: ', TRIM(output)
    OPEN(7,file=output)
    DO i=1,proj%nx1     
       r=proj%r_x1(i)
       z=find(r,cosm%r,cosm%z_r,cosm%nr,3,3,2)
       WRITE(7,*) r, z, proj%x1(i)
    END DO
    CLOSE(7)

    !Kernel 2
    output=TRIM('projection/kernel2.dat')
    WRITE(*,*) 'WRITE_PROJECTION_KERNEL: Writing out kernel 2: ', TRIM(output)
    OPEN(7,file=output)
    DO i=1,proj%nx2
       !Kernel 2
       r=proj%r_x2(i)
       z=find(r,cosm%r,cosm%z_r,cosm%nr,3,3,2)
       WRITE(7,*) r, z, proj%x2(i)
    END DO
    CLOSE(7)
    WRITE(*,*) 'WRITE_PROJECTION_KERNEL: Writing done'
    WRITE(*,*)

  END SUBROUTINE write_projection_kernels

  SUBROUTINE fill_lensing_kernel(inz,r_x,x,nx_out,lens,cosm)

    IMPLICIT NONE
    INTEGER, INTENT(INOUT) :: inz
    TYPE(lensing) :: lens
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8, ALLOCATABLE, INTENT(OUT) :: r_x(:), x(:)
    INTEGER, INTENT(OUT) :: nx_out
    REAL*8 :: zmin, zmax, rmin, rmax
    REAL*8 :: a, q, z, r
    CHARACTER(len=256) :: output
    INTEGER :: i

    !Parameters
    INTEGER, PARAMETER :: nq=128 !Number of entries in q(r) table
    INTEGER, PARAMETER :: nx=128 !Number of entries in X(r) table

    IF(inz==-1) THEN
       WRITE(*,*) 'FILL_LENSING_KERNEL: Choose n(z)'
       WRITE(*,*) '================================'
       WRITE(*,*) '0 - Fixed source plane'
       WRITE(*,*) '1 - Realistic n(z) distribution'
       READ(*,*) inz
       WRITE(*,*) '================================'
       WRITE(*,*)
    END IF

    !Choose either n(z) or fixed z_s
    IF(inz==0) THEN
       !WRITE(*,*) 'FILL_LENSING_KERNEL: Source plane redshift:'
       !READ(*,*) zmax
       zmin=0.
       zmax=4. !Is 4 \simeq 1100?
       !zmax=cosm%z_cmb
       !WRITE(*,*)
    ELSE
       CALL get_nz(inz,lens)
       zmin=lens%z_nz(1)
       zmax=lens%z_nz(lens%nnz)
       output='lensing/nz.dat'
       CALL write_nz(lens,output)
    END IF

    !Get the distance range for the lensing kernel
    rmin=0.
    rmax=find(zmax,cosm%z_r,cosm%r,cosm%nr,3,3,2)
    WRITE(*,*) 'FILL_LENSING_KERNEL: rmin [Mpc/h]:', rmin
    WRITE(*,*) 'FILL_LENSING_KERNEL: rmax [Mpc/h]:', rmax

    !Fill the r vs. q(r) tables
    lens%nq=nq
    WRITE(*,*) 'FILL_LENSING_KERNEL: nq:', lens%nq
    CALL fill_table(rmin,rmax,lens%r_q,lens%nq)
    IF(ALLOCATED(lens%q)) DEALLOCATE(lens%q)
    ALLOCATE(lens%q(lens%nq))
    output='lensing/efficiency.dat'
    WRITE(*,*) 'FILL_LENSING_KERNEL: Writing q(r): ', TRIM(output)
    OPEN(7,file=output)
    DO i=1,lens%nq
       r=lens%r_q(i)
       z=find(r,cosm%r,cosm%z_r,cosm%nr,3,3,2)
       IF(r==0.) THEN
          !To avoid division by zero
          lens%q(i)=1.d0
       ELSE
          IF(inz==0) THEN
             !q(r) for a fixed source plane
             lens%q(i)=f_k(rmax-r,cosm)/f_k(rmax,cosm)
          ELSE
             !q(r) for a n(z) distribution 
             lens%q(i)=integrate_q(r,z,zmax,acc,3,lens,cosm)
          END IF
       END IF
       WRITE(7,*) r, z, lens%q(i)
    END DO
    CLOSE(7)
    WRITE(*,*) 'FILL_LENSING_KERNEL: Done writing'

    !Assign arrays for the projection function
    nx_out=nx
    CALL fill_table(rmin,rmax,r_x,nx)
    WRITE(*,*) 'FILL_LENSING_KERNEL: nx:', nx
    IF(ALLOCATED(x)) DEALLOCATE(x)
    ALLOCATE(x(nx))

    DO i=1,nx

       !Get variables r and z(r)
       r=r_x(i)
       z=find(r,cosm%r,cosm%z_r,cosm%nr,3,3,2)

       !Get the lensing weighting functions
       q=find(r,lens%r_q,lens%q,lens%nq,3,3,2)
       x(i)=(1.+z)*f_k(r,cosm)*q
       x(i)=x(i)*1.5*cosm%om_m/(conH0**2)

       !The kernel must not be negative
       IF(x(i)<0.) x(i)=0.d0

    END DO
    WRITE(*,*) 'FILL_LENSING_KERNEL: Done'
    WRITE(*,*)

  END SUBROUTINE fill_lensing_kernel

  SUBROUTINE fill_y_kernel(r_x,x,nx,cosm)

    IMPLICIT NONE
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8, ALLOCATABLE, INTENT(OUT) :: r_x(:), x(:)
    INTEGER, INTENT(OUT) :: nx
    INTEGER :: i
    REAL*8 :: a, z, r
    REAL*8 :: rmin, rmax

    !Get the distance range for the projection function
    !Use the same as that for the distance calculation
    !Assign arrays for the kernel function
    rmin=0.
    rmax=cosm%r(cosm%nr)
    nx=128
    CALL fill_table(rmin,rmax,r_x,nx)
    WRITE(*,*) 'FILL_Y_KERNEL: rmin [Mpc/h]:', rmin
    WRITE(*,*) 'FILL_Y_KERNEL: rmax [Mpc/h]:', rmax
    WRITE(*,*) 'FILL_Y_KERNEL: nr:', nx
    IF(ALLOCATED(x)) DEALLOCATE(x)
    ALLOCATE(x(nx))

    !Now fill the y-kernel (which is simply 'a')
    DO i=1,nx
       !Compton-y
       r=r_x(i)
       z=find(r,cosm%r,cosm%z_r,cosm%nr,3,3,2)
       a=1./(1.+z)
       x(i)=a*yfac*mpc
    END DO

    WRITE(*,*) 'FILL_Y_KERNEL: Done:'
    WRITE(*,*)

  END SUBROUTINE fill_y_kernel

  FUNCTION f_k(r,cosm)

    IMPLICIT NONE
    REAL*8 :: f_k
    REAL*8, INTENT(IN) :: r
    TYPE(cosmology), INTENT(IN) :: cosm

    IF(cosm%k==0.d0) THEN
       f_k=r
    ELSE IF(cosm%k<0.d0) THEN
       f_k=sinh(sqrt(-cosm%k)*r)/sqrt(-cosm%k)
    ELSE IF(cosm%k>0.d0) THEN
       f_k=sin(sqrt(cosm%k)*r)/sqrt(cosm%k)
    ELSE
       STOP 'F_K: Something went wrong'
    END IF

  END FUNCTION f_k

  SUBROUTINE random_cosmology(cosm)

    IMPLICIT NONE
    TYPE(cosmology) :: cosm
    REAL*8 :: om_m_min, om_m_max, om_b_min, om_b_max, n_min, n_max
    REAL*8 :: w_min, w_max, h_min, h_max, sig8_min, sig8_max, wa_min, wa_max

    !Needs to be set to normalise P_lin
    cosm%A=1.

    om_m_min=0.1
    om_m_max=1.
    cosm%om_m=uniform(om_m_min,om_m_max)

    cosm%om_v=1.-cosm%om_m

    om_b_min=0.005
    om_b_max=MIN(0.095,cosm%om_m)
    cosm%om_b=uniform(om_b_min,om_b_max)

    cosm%om_c=cosm%om_m-cosm%om_b

    n_min=0.5
    n_max=1.5
    cosm%n=uniform(n_min,n_max)

    h_min=0.4
    h_max=1.2
    cosm%h=uniform(h_min,h_max)

    w_min=-1.5
    w_max=-0.5
    cosm%w=uniform(w_min,w_max)

    wa_min=-1.
    wa_max=-cosm%w*0.8
    cosm%wa=uniform(wa_min,wa_max)

    sig8_min=0.2
    sig8_max=1.5
    cosm%sig8=uniform(sig8_min,sig8_max)

  END SUBROUTINE random_cosmology

  SUBROUTINE RNG_set(seed)

    !Seeds the RNG using the system clock so that it is different each time
    IMPLICIT NONE
    INTEGER :: int, timearray(3)
    REAL*8 :: rand
    INTEGER, INTENT(IN) :: seed

    WRITE(*,*) 'Initialising RNG'

    IF(seed==0) THEN
       !This fills the time array using the system clock!
       !If called within the same second the numbers will be identical!
       CALL itime(timeArray)
       !This then initialises the generator!
       int=FLOOR(rand(timeArray(1)+timeArray(2)+timeArray(3)))
    ELSE
       int=FLOOR(rand(seed))
    END IF
    WRITE(*,*) 'RNG set'
    WRITE(*,*)

  END SUBROUTINE RNG_set

  FUNCTION uniform(x1,x2)

    !Produces a uniform random number between x1 and x2
    IMPLICIT NONE
    REAL*8 :: uniform
    REAL*8, INTENT(IN) :: x1, x2
    REAL*8 :: rand !This needs to be defined for the ifort compiler

    !Rand is some inbuilt function
    uniform=x1+(x2-x1)*(rand(0))

  END FUNCTION uniform

  SUBROUTINE allocate_LUT(lut,n)

    IMPLICIT NONE
    TYPE(tables) :: lut
    INTEGER, INTENT(IN) :: n

    !Allocates memory for the look-up tables
    lut%n=n

    ALLOCATE(lut%zc(n),lut%m(n),lut%c(n),lut%rv(n))
    ALLOCATE(lut%nu(n),lut%rr(n),lut%sigf(n),lut%sig(n))
    ALLOCATE(lut%m500(n),lut%r500(n),lut%c500(n))
    ALLOCATE(lut%m500c(n),lut%r500c(n),lut%c500c(n))
    ALLOCATE(lut%m200(n),lut%r200(n),lut%c200(n))
    ALLOCATE(lut%m200c(n),lut%r200c(n),lut%c200c(n))

    !Experimental window look-up table
    !lut%nk=nk
    !ALLOCATE(lut%log_m(n),lut%log_k(nk),lut%log_win(n,nk))
    !lut%log_k=0.
    !lut%log_win=0.
    !lut%iwin=.FALSE.

    lut%zc=0.
    lut%m=0.
    lut%c=0.
    lut%rv=0.
    lut%nu=0.
    lut%rr=0.
    lut%sigf=0.
    lut%sig=0.

    lut%m500=0.
    lut%r500=0.
    lut%c500=0.

    lut%m500c=0.
    lut%r500c=0.
    lut%c500c=0.

    lut%m200=0.
    lut%r200=0.
    lut%c200=0.

    lut%m200c=0.
    lut%r200c=0.
    lut%c200c=0.

    !Experimental log tables
    ALLOCATE(lut%log_m(n))
    lut%log_m=0.

  END SUBROUTINE allocate_LUT

  SUBROUTINE deallocate_LUT(lut)

    IMPLICIT NONE
    TYPE(tables) :: lut

    !Deallocates look-up tables
    DEALLOCATE(lut%zc,lut%m,lut%c,lut%rv,lut%nu,lut%rr,lut%sigf,lut%sig)
    DEALLOCATE(lut%m500,lut%r500,lut%c500,lut%m500c,lut%r500c,lut%c500c)
    DEALLOCATE(lut%m200,lut%r200,lut%c200,lut%m200c,lut%r200c,lut%c200c)

    !Deallocate experimental window tables
    !DEALLOCATE(lut%log_win,lut%log_k)

    !Deallocate experimental log tables
    DEALLOCATE(lut%log_m)

  END SUBROUTINE deallocate_LUT

  SUBROUTINE halomod_init(mmin,mmax,z,lut,cosm)

    IMPLICIT NONE
    REAL*8, INTENT(IN) :: z
    REAL*8, INTENT(IN) :: mmin, mmax
    INTEGER :: i
    REAL*8 :: Dv, dc, f, m, nu, r, sig
    TYPE(cosmology) :: cosm
    TYPE(tables) :: lut
    INTEGER, PARAMETER :: n=64 !Number of mass entries in look-up table

    !Halo-model initialisation routine
    !The computes other tables necessary for the one-halo integral

    !Find value of sigma_v
    lut%sigv=sqrt(dispint(0.d0,z,cosm)/3.d0)
    lut%sigv100=sqrt(dispint(100.d0,z,cosm)/3.d0)
    lut%sig8z=sigma(8.d0,z,cosm)

    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: Filling look-up tables'
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: Tables being filled at redshift:', REAL(z)

    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: sigv [Mpc/h]:', REAL(lut%sigv)
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: sigv100 [Mpc/h]:', REAL(lut%sigv100)
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: sig8(z):', REAL(lut%sig8z)

    IF(ALLOCATED(lut%rr)) CALL deallocate_LUT(lut)

    CALL allocate_LUT(lut,n)

    dc=delta_c(z,cosm)

    DO i=1,n

       m=exp(log(mmin)+log(mmax/mmin)*float(i-1)/float(n-1))
       r=radius_m(m,cosm)
       sig=sigma_cb(r,z,cosm)
       nu=dc/sig

       lut%m(i)=m
       lut%rr(i)=r
       lut%sig(i)=sig
       lut%nu(i)=nu

    END DO

    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: m, r, nu, sig tables filled'

    !Fills up a table for sigma(fM) for Bullock c(m) relation
    !This is the f=0.01 parameter in the Bullock realtion sigma(fM,z)
    f=0.01**onethird
    DO i=1,lut%n
       lut%sigf(i)=sigma_cb(lut%rr(i)*f,z,cosm)
    END DO
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: sigf tables filled'  

    !Fill virial radius table using real radius table
    Dv=Delta_v(z,cosm)
    lut%rv=lut%rr/(Dv**onethird)

    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: rv tables filled'
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: Delta_v:', REAL(Dv)
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: nu min:', REAL(lut%nu(1))
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: nu max:', REAL(lut%nu(lut%n))
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: R_v min [Mpc/h]:', REAL(lut%rv(1))
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: R_v max [Mpc/h]:', REAL(lut%rv(lut%n))
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: M min [Msun/h]:', REAL(lut%m(1))
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: M max [Msun/h]:', REAL(lut%m(lut%n))

    lut%gmin=1.d0-integrate(lut%nu(1),10.d0,gnu,acc,3)
    lut%gmax=integrate(lut%nu(lut%n),10.d0,gnu,acc,3)
    lut%gbmin=1.d0-integrate(lut%nu(1),10.d0,gnubnu,acc,3)
    lut%gbmax=integrate(lut%nu(lut%n),10.d0,gnubnu,acc,3)
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: Missing g(nu) at low end:', REAL(lut%gmin)
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: Missing g(nu) at high end:', REAL(lut%gmax)
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: Missing g(nu)b(nu) at low end:', REAL(lut%gbmin)
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: Missing g(nu)b(nu) at high end:', REAL(lut%gbmax)

    !Find non-linear radius and scale
    lut%rnl=r_nl(lut)
    lut%knl=1./lut%rnl

    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: r_nl [Mpc/h]:', REAL(lut%rnl)
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: k_nl [h/Mpc]:', REAL(lut%knl)

    lut%neff=neff(lut,cosm)

    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: n_eff:', REAL(lut%neff)

    CALL conc_bull(z,cosm,lut)

    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: c tables filled'
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: c min [Msun/h]:', REAL(lut%c(lut%n))
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: c max [Msun/h]:', REAL(lut%c(1))
    IF(ihm==1) WRITE(*,*) 'HALOMOD_INIT: Done'
    IF(ihm==1) WRITE(*,*)

    !Calculate Delta = 200, 500 and Delta_c = 200, 500 quantities
    CALL convert_mass_definition(lut%rv,lut%c,lut%m,Dv,1.d0,lut%r500,lut%c500,lut%m500,500.d0,1.d0,lut%n)
    CALL convert_mass_definition(lut%rv,lut%c,lut%m,Dv,1.d0,lut%r200,lut%c200,lut%m200,200.d0,1.d0,lut%n)
    CALL convert_mass_definition(lut%rv,lut%c,lut%m,Dv,matter_density(cosm),lut%r500c,lut%c500c,lut%m500c,500.d0,critical_density(),lut%n)
    CALL convert_mass_definition(lut%rv,lut%c,lut%m,Dv,matter_density(cosm),lut%r200c,lut%c200c,lut%m200c,200.d0,critical_density(),lut%n)

    IF(ihm==1) CALL write_parameters(z,lut,cosm)
    ihm=0

  END SUBROUTINE halomod_init

  SUBROUTINE convert_mass_definition(ri,ci,mi,Di,rhoi,rj,cj,mj,Dj,rhoj,n)

    !Converts mass definition from Delta_i rho_i overdense to Delta_j rho_j overdense
    IMPLICIT NONE
    INTEGER, INTENT(IN) :: n
    REAL*8, INTENT(IN) :: ri(n), ci(n), mi(n)
    REAL*8, INTENT(OUT) :: rj(n), cj(n), mj(n)
    REAL*8, INTENT(IN) :: Di, Dj, rhoi, rhoj
    REAL*8, ALLOCATABLE :: LHS(:), RHS(:)
    REAL*8 :: rs, LH, RH
    INTEGER :: i

    !Ensure these are all zero
    rj=0.
    cj=0.
    mj=0.

    !Allocate arrays for the LHS and RHS of the equation
    ALLOCATE(LHS(n),RHS(n))

    !Fill arrays for LHS and RHS of the equation - can use same r(i) table
    !The equation: (r_i^3 x rho_i x Delta_i / X_i(r_i/rs) = same for j)
    DO i=1,n
       rs=ri(i)/ci(i)
       LHS(i)=(ri(i)**3)*Di*rhoi/nfw_factor(ri(i)/rs)
       RHS(i)=(ri(i)**3)*Dj*rhoj/nfw_factor(ri(i)/rs)
       !RHS(i)=LHS(i)*Dj*rhoj/(Di*rhoi)
       !WRITE(*,fmt='(I5,3ES15.5)') i, ri(i), LHS(i), RHS(i)
    END DO

    !Now use the find algorithm to invert L(r_i)=R(r_j) so that
    !r_j=R^{-1}[L(r_i)]
    DO i=1,n

       !First find the radius
       rj(i)=exp(find_solve(log(LHS(i)),log(ri),log(RHS),n))

       !This is to check the solution is correct
       !LH=LHS(i)
       !RH=exp(find(log(rj(i)),log(ri),log(RHS),n,3,3,2))
       !WRITE(*,fmt='(I5,2F15.5)') i, LH, RH

       !NOTE VERY WELL - this does *NOT* mean that:
       !LHS(i)=(rj(i)**3)*Dj*rhoj/nfw_factor(rj(i)/rs)
       !Because the integer 'i' does not correspond to the solution
       !LH=LHS(i)
       !RH=(rj(i)**3)*Dj*rhoj/nfw_factor(rj(i)/rs)
       !WRITE(*,fmt='(I5,2F15.5)') i, LH, RH

       !Now do concentration and mass
       rs=ri(i)/ci(i)
       cj(i)=rj(i)/rs
       mj(i)=mi(i)*nfw_factor(cj(i))/nfw_factor(ci(i))

    END DO

    DEALLOCATE(LHS,RHS)

  END SUBROUTINE convert_mass_definition

  FUNCTION find_solve(a,xtab,ytab,n)

    !Solves y(x)=a for x
    IMPLICIT NONE
    REAL*8 :: find_solve
    REAL*8, INTENT(IN) :: a, xtab(n), ytab(n)
    INTEGER, INTENT(IN) :: n

    find_solve=find(a,ytab,xtab,n,3,3,2)

  END FUNCTION find_solve

  PURE FUNCTION nfw_factor(x)

    !The NFW 'mass' factor that crops up all the time
    IMPLICIT NONE
    REAL*8 :: nfw_factor
    REAL*8, INTENT(IN) :: x

    nfw_factor=log(1.d0+x)-x/(1.d0+x)

  END FUNCTION nfw_factor

  PURE FUNCTION radius_m(m,cosm)

    !The comoving radius corresponding to mass M in a homogeneous universe
    IMPLICIT NONE
    REAL*8 :: radius_m
    REAL*8, INTENT(IN) :: m
    TYPE(cosmology), INTENT(IN) :: cosm

    radius_m=(3.*m/(4.*pi*matter_density(cosm)))**onethird

  END FUNCTION radius_m

  FUNCTION neff(lut,cosm)

    !Power spectrum slope a the non-linear scale
    IMPLICIT NONE
    REAL*8 :: neff
    TYPE(cosmology) :: cosm
    TYPE(tables) :: lut

    !Numerical differentiation to find effective index at collapse
    neff=-3.-derivative_table(log(lut%rnl),log(lut%rr),log(lut%sig**2),lut%n,3,3)

    !For some bizarre cosmologies r_nl is very small, so almost no collapse has occured
    !In this case the n_eff calculation goes mad and needs to be fixed using this fudge.
    IF(neff<cosm%n-4.) neff=cosm%n-4.
    IF(neff>cosm%n)    neff=cosm%n

  END FUNCTION neff

  SUBROUTINE conc_bull(z,cosm,lut)

    !Calculates the Bullock et al. (2001) mass-concentration relation
    IMPLICIT NONE
    REAL*8, INTENT(IN) :: z
    TYPE(cosmology) :: cosm, cos_lcdm
    TYPE(tables) :: lut
    REAL*8 :: A, zinf, ainf, zf, g_lcdm, g_wcdm
    INTEGER :: i   

    A=As(cosm)

    !Fill the collapse z look-up table
    CALL zcoll_bull(z,cosm,lut)

    !Fill the concentration look-up table
    DO i=1,lut%n

       zf=lut%zc(i)
       lut%c(i)=A*(1.+zf)/(1.+z)

       !Dolag2004 prescription for adding DE dependence
       IF(imead==1) THEN

          !IF((cosm%w .NE. -1.) .OR. (cosm%wa .NE. 0)) THEN

          !The redshift considered to be infinite (?!)
          zinf=10.
          ainf=1./(1.+zinf)

          !Save the growth function in the current cosmology
          g_wcdm=grow(zinf,cosm)

          !Make a LCDM cosmology
          cos_lcdm=cosm
          DEALLOCATE(cos_lcdm%growth)
          DEALLOCATE(cos_lcdm%a_growth)
          cos_lcdm%w=-1.
          cos_lcdm%wa=0.

          !Needs to use grow_int explicitly in case tabulated values are stored
          g_lcdm=growint(ainf,cos_lcdm)

          !Changed this to a power of 1.5, which produces more accurate results for extreme DE
          lut%c(i)=lut%c(i)*((g_wcdm/g_lcdm)**1.5)

       END IF

    END DO

  END SUBROUTINE conc_bull

  SUBROUTINE zcoll_bull(z,cosm,lut)

    !This fills up the halo collapse redshift table as per Bullock relations   
    IMPLICIT NONE
    REAL*8, INTENT(IN) :: z
    TYPE(cosmology) :: cosm
    TYPE(tables) :: lut
    REAL*8 :: dc
    REAL*8 :: af, zf, RHS, a, growz
    REAL*8, ALLOCATABLE :: af_tab(:), grow_tab(:)
    INTEGER :: i, ntab  

    ntab=SIZE(cosm%growth)
    ALLOCATE(af_tab(ntab),grow_tab(ntab))

    af_tab=cosm%a_growth
    grow_tab=cosm%growth

    !Do numerical inversion
    DO i=1,lut%n

       !I don't think this is really consistent with dc varying as a function of z
       !But the change will be very small
       dc=delta_c(z,cosm)

       RHS=dc*grow(z,cosm)/lut%sigf(i)

       a=1./(1.+z)
       growz=find(a,af_tab,grow_tab,cosm%ng,3,3,2)

       IF(RHS>growz) THEN
          zf=z
       ELSE
          af=find(RHS,grow_tab,af_tab,cosm%ng,3,3,2)
          zf=-1.+1./af
       END IF

       lut%zc(i)=zf

    END DO

    DEALLOCATE(af_tab,grow_tab)

  END SUBROUTINE zcoll_bull

  FUNCTION mass_r(r,cosm)

    !Calcuates the mass contains in a sphere of comoving radius 'r' in a homogeneous universe
    IMPLICIT NONE
    REAL*8 :: mass_r, r
    TYPE(cosmology) :: cosm

    !Relation between mean cosmological mass and radius
    mass_r=(4.*pi/3.)*matter_density(cosm)*(r**3)

  END FUNCTION mass_r

  PURE FUNCTION matter_density(cosm)

    !Comoving matter density in (Msun/h) / (Mpc/h)^3 (z=0 value, obviously)
    !This number is (3/8pi) x H0^2/G x Omega_m(z=0)
    IMPLICIT NONE
    REAL*8 :: matter_density
    TYPE(cosmology), INTENT(IN) :: cosm

    matter_density=(2.775d11)*cosm%om_m

  END FUNCTION matter_density

  PURE FUNCTION critical_density()

    !Comoving critical density in (Msun/h) / (Mpc/h)^3 (z=0 value, obviously)
    !This number is (3/8pi) x H0^2/G
    IMPLICIT NONE
    REAL*8 :: critical_density

    critical_density=2.775d11

  END FUNCTION critical_density

  FUNCTION Tk(k,cosm)

    !Transfer function selection
    IMPLICIT NONE
    REAL*8 :: Tk, k
    TYPE(cosmology) :: cosm

    Tk=Tk_eh(k,cosm)

  END FUNCTION Tk

  FUNCTION Tk_eh(yy,cosm)

    !Eisenstein & Hu fitting function
    !JP - the astonishing D.J. Eisenstein & W. Hu fitting formula (ApJ 496 605 [1998])
    !JP - remember I use k/h, whereas they use pure k, om_m is cdm + baryons
    IMPLICIT NONE
    REAL*8 :: Tk_eh
    REAL*8, INTENT(IN) :: yy
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8 :: rk, e, thet, b1, b2, zd, ze, rd, re, rke, s, rks
    REAL*8 :: q
    REAL*8 :: y, g, ab
    REAL*8 :: a1, a2, ac
    REAL*8 :: bc
    REAL*8 :: f, fac
    REAL*8 :: c1, c2, tc
    REAL*8 :: bb, bn, ss, tb
    REAL*8 :: om_m, om_b, h

    om_m=cosm%om_m
    om_b=cosm%om_b
    h=cosm%h

    rk=yy*h

    e=exp(1.)

    thet=2.728/2.7
    b1=0.313*(om_m*h*h)**(-0.419)*(1+0.607*(om_m*h*h)**0.674)
    b2=0.238*(om_m*h*h)**0.223
    zd=1291.*(1+b1*(om_b*h*h)**b2)*(om_m*h*h)**0.251/(1.+0.659*(om_m*h*h)**0.828)
    ze=2.50e4*om_m*h*h/thet**4.
    rd=31500.*om_b*h*h/thet**4./zd !Should this be 1+zd (Steven Murray enquirey)?
    re=31500.*om_b*h*h/thet**4./ze
    rke=7.46e-2*om_m*h*h/thet**2.
    s=(2./3./rke)*sqrt(6./re)*log((sqrt(1.+rd)+sqrt(rd+re))/(1+sqrt(re)))
    rks=1.6*( (om_b*h*h)**0.52 ) * ( (om_m*h*h)**0.73 ) * (1.+(10.4*om_m*h*h)**(-0.95))

    q=rk/13.41/rke

    y=(1.+ze)/(1.+zd)
    g=y*(-6.*sqrt(1+y)+(2.+3.*y)*log((sqrt(1.+y)+1.)/(sqrt(1.+y)-1.)))
    ab=g*2.07*rke*s/(1.+rd)**(0.75)

    a1=(46.9*om_m*h*h)**0.670*(1+(32.1*om_m*h*h)**(-0.532))
    a2=(12.0*om_m*h*h)**0.424*(1+(45.0*om_m*h*h)**(-0.582))
    ac=(a1**(-om_b/om_m)) * (a2**(-(om_b/om_m)**3.))

    b1=0.944/(1+(458.*om_m*h*h)**(-0.708))
    b2=(0.395*om_m*h*h)**(-0.0266)
    bc=1./(1.+b1*((1.-om_b/om_m)**b2-1.))

    f=1./(1.+(rk*s/5.4)**4.)

    c1=14.2 + 386./(1.+69.9*q**1.08)
    c2=14.2/ac + 386./(1.+69.9*q**1.08)
    tc=f*log(e+1.8*bc*q)/(log(e+1.8*bc*q)+c1*q*q) +(1.-f)*log(e+1.8*bc*q)/(log(e+1.8*bc*q)+c2*q*q)

    bb=0.5+(om_b/om_m) + (3.-2.*om_b/om_m)*sqrt((17.2*om_m*h*h)**2.+1.)
    bn=8.41*(om_m*h*h)**0.435
    ss=s/(1.+(bn/rk/s)**3.)**(1./3.)
    tb=log(e+1.8*q)/(log(e+1.8*q)+c1*q*q)/(1+(rk*s/5.2)**2.)
    !IF((rk/rks**1.4)>7.) THEN
    !   fac=0.
    !ELSE
    !Removed this IF statement as it produced a discontinuity in P_lin(k) as cosmology
    !was varied - thanks David Copeland for pointing this out
    fac=exp(-(rk/rks)**1.4)
    !END IF
    tb=(tb+ab*fac/(1.+(bb/rk/s)**3.))*sin(rk*ss)/rk/ss

    tk_eh=real((om_b/om_m)*tb+(1-om_b/om_m)*tc)

  END FUNCTION TK_EH

  FUNCTION p_lin(k,z,cosm)

    !Linear matter power spectrum
    !P(k) should have been previously normalised so as to get the amplitude 'A' correct
    IMPLICIT NONE
    REAL*8 :: p_lin
    REAL*8, INTENT (IN) :: k, z
    TYPE(cosmology), INTENT(IN) :: cosm 

    IF(k==0.) THEN
       !If p_lin happens to be foolishly called for 0 mode (which should never happen, but might in integrals)
       p_lin=0.
    ELSE IF(k>1.e8) THEN
       !Avoids some issues if p_lin is called for very (absurdly) high k values
       !For some reason crashes can occur if this is the case
       p_lin=0.
    ELSE IF(ibox==1 .AND. k<2.*pi/Lbox) THEN
       p_lin=0.
    ELSE
       !In this case look for the transfer function
       p_lin=(cosm%A**2)*(grow(z,cosm)**2)*(Tk(k,cosm)**2)*(k**(cosm%n+3.))
    END IF

  END FUNCTION p_lin

  SUBROUTINE halomod(ih1,ih2,k,z,p2h,p1h,pfull,plin,lut,cosm)

    !Gets the one- and two-halo terms and combines them
    IMPLICIT NONE
    REAL*8, INTENT(OUT) :: p1h, p2h, pfull
    REAL*8, INTENT(IN) :: plin, k, z
    INTEGER, INTENT(IN) :: ih1, ih2
    TYPE(cosmology), INTENT(IN) :: cosm
    TYPE(tables), INTENT(IN) :: lut
    REAL*8 :: alp
    REAL*8 :: wk(2,lut%n), m, rv, rs
    INTEGER :: i, j, ih(2)

    !Initially fill this small array 
    ih(1)=ih1
    ih(2)=ih2

    !For the i's
    !-1 - DMonly
    ! 0 - All matter
    ! 1 - CDM
    ! 2 - Gas
    ! 3 - Stars
    ! 4 - Bound gas
    ! 5 - Free gas
    ! 6 - Pressure

    !Calls expressions for one- and two-halo terms and then combines
    !to form the full power spectrum
    IF(k==0.) THEN
       !This should really never be called for k=0
       p1h=0.d0
       p2h=0.d0
    ELSE
       !Calculate the halo window functions
       DO j=1,2
          DO i=1,lut%n
             m=lut%m(i)
             rv=lut%rv(i)
             rs=rv/lut%c(i)
             wk(j,i)=win_type(1,ih(j),k,m,rv,rs,z,lut,cosm)
          END DO
          IF(ih(2)==ih(1)) THEN
             !Avoid having to call win_type twice if doing auto spectrum
             wk(2,:)=wk(1,:)
             EXIT
          END IF
       END DO
       p1h=p_1h(ih,wk,k,z,lut,cosm)
       IF(imead==-1) THEN
          !Only if imead=-1 do we need to recalcualte the window
          !functions for the two-halo term with k=0 fixed
          DO j=1,2
             DO i=1,lut%n
                m=lut%m(i)
                rv=lut%rv(i)
                rs=rv/lut%c(i)
                wk(j,i)=win_type(1,ih(j),0.d0,m,rv,rs,z,lut,cosm)
             END DO
             IF(ih(2)==ih(1)) THEN
                !Avoid having to call win_type twice if doing auto spectrum
                wk(2,:)=wk(1,:)
                EXIT
             END IF
          END DO
       END IF
       p2h=p_2h(ih,wk,k,z,plin,lut,cosm)
    END IF

    IF(imead==0 .OR. imead==-1) THEN
       pfull=p2h+p1h
    ELSE IF(imead==1) THEN
       alp=alpha_trans(lut,cosm)
       pfull=(p2h**alp+p1h**alp)**(1.d0/alp)
    END IF

  END SUBROUTINE halomod

  FUNCTION p_2h(ih,wk,k,z,plin,lut,cosm)

    !Produces the 'two-halo' power
    IMPLICIT NONE
    REAL*8 :: p_2h
    REAL*8, INTENT(IN) :: k, plin
    REAL*8, INTENT(IN) :: z
    TYPE(tables), INTENT(IN) :: lut
    REAL*8, INTENT(IN) :: wk(2,lut%n)
    TYPE(cosmology), INTENT(IN) :: cosm
    INTEGER, INTENT(IN) :: ih(2)
    REAL*8 :: sigv, frac, bmin, bmax
    !REAL*8, ALLOCATABLE :: integrand10(:), integrand11(:), integrand12(:)
    !REAL*8, ALLOCATABLE :: integrand20(:), integrand21(:), integrand22(:)
    REAL*8, ALLOCATABLE :: integrand11(:), integrand12(:)
    REAL*8, ALLOCATABLE :: integrand21(:), integrand22(:)
    REAL*8 :: nu, w0(2), m, wk1, wk2, b0, g0, m0
    REAL*8 :: rv, rs, c
    !REAL*8 :: sum10, sum11, sum12
    !REAL*8 :: sum20, sum21, sum22
    REAL*8 :: sum11, sum12
    REAL*8 :: sum21, sum22
    INTEGER :: i, j
    
    IF(imead==0 .OR. imead==-1) THEN

       ALLOCATE(integrand11(lut%n),integrand12(lut%n))

       IF(ibias==2) THEN
          !Only necessary for second-order bias integral
          ALLOCATE(integrand21(lut%n),integrand22(lut%n))
       END IF

       DO i=1,lut%n

          m=lut%m(i)
          nu=lut%nu(i)

          !Linear bias term
          integrand11(i)=gnu(nu)*bnu(nu)*wk(1,i)/m
          integrand12(i)=gnu(nu)*bnu(nu)*wk(2,i)/m

          IF(ibias==2) THEN
             !Second-order bias term
             integrand21(i)=gnu(nu)*b2nu(nu)*wk(1,i)/m
             integrand22(i)=gnu(nu)*b2nu(nu)*wk(2,i)/m
          END IF

          IF(ip2h==2 .AND. i==1) THEN
             !Take the values from the lowest nu point
             m0=m
             wk1=wk(1,i)
             wk2=wk(2,i)
          END IF

       END DO

       !Evaluate these integrals from the tabled values
       sum11=inttab(lut%nu,integrand11,lut%n,3)
       sum12=inttab(lut%nu,integrand12,lut%n,3)

       IF(ip2h==0) THEN
          !Do nothing in this case
       ELSE IF(ip2h==1) THEN
          !Add on the value of integral b(nu)*g(nu) assuming w=1
          sum11=sum11+lut%gbmin*halo_fraction(ih(1),m,cosm)/matter_density(cosm)
          sum12=sum12+lut%gbmin*halo_fraction(ih(2),m,cosm)/matter_density(cosm)
       ELSE IF(ip2h==2) THEN
          !Put the missing part of the integrand as a delta function at nu1
          sum11=sum11+lut%gbmin*wk1/m0
          sum12=sum12+lut%gbmin*wk2/m0
       ELSE
          STOP 'P_2h: Error, ip2h not specified correctly'
       END IF

       p_2h=plin*sum11*sum12*(matter_density(cosm)**2)

       IF(ibias==2) THEN
          !Second order bias correction
          !This has the property that \int f(nu)b2(nu) du = 0
          !This means it is hard to check that the normalisation is correct
          !e.g., how much do low mass haloes matter
          !Varying mmin does make a difference to the values of the integrals
          sum21=inttab(lut%nu,integrand21,lut%n,3)
          sum22=inttab(lut%nu,integrand22,lut%n,3)
          p_2h=p_2h+(plin**2)*sum21*sum22*(matter_density(cosm)**2)
       END IF

    ELSE IF(imead==1) THEN

       sigv=lut%sigv
       frac=fdamp(z,cosm)

       IF(frac==0.) THEN
          p_2h=plin
       ELSE
          p_2h=plin*(1.-frac*(tanh(k*sigv/sqrt(ABS(frac))))**2)
       END IF

       !For some extreme cosmologies frac>1. so this must be added to prevent p_2h<0.
       IF(p_2h<0.) p_2h=0.

    END IF

  END FUNCTION p_2h

  FUNCTION p_1h(ih,wk,k,z,lut,cosm)

    !Calculates the one-halo term
    IMPLICIT NONE
    REAL*8 :: p_1h
    REAL*8, INTENT(IN) :: k, z
    TYPE(tables), INTENT(IN) :: lut
    REAL*8, INTENT(IN) :: wk(2,lut%n)
    TYPE(cosmology), INTENT(IN) :: cosm
    INTEGER, INTENT(IN) :: ih(2)
    REAL*8 :: m, g, fac, et, ks
    REAL*8, ALLOCATABLE :: integrand(:)
    INTEGER :: i, j

    ALLOCATE(integrand(lut%n))
    integrand=0.

    !Only call eta once
    et=eta(z,cosm)

    !Calculates the value of the integrand at all nu values!
    DO i=1,lut%n
       g=gnu(lut%nu(i))
       m=lut%m(i)
       integrand(i)=g*wk(1,i)*wk(2,i)/m
    END DO

    !Carries out the integration
    !Important to use basic trapezium rule because the integrand is messy due to rapid oscillations in W(k)
    p_1h=matter_density(cosm)*inttab(lut%nu,integrand,lut%n,1)*(4.*pi)*(k/(2.*pi))**3

    DEALLOCATE(integrand)

    IF(imead==1) THEN

       !Damping of the 1-halo term at very large scales
       ks=kstar(lut,cosm)

       !Prevents problems if k/ks is very large

       IF(ks>0.) THEN

          IF((k/ks)**2>7.) THEN
             fac=0.
          ELSE
             fac=exp(-((k/ks)**2))
          END IF

          p_1h=p_1h*(1.-fac)

       END IF

    END IF

  END FUNCTION p_1h

  SUBROUTINE fill_sigtab(cosm)

    !This fills up tables of r vs. sigma(r) across a range in r!
    !It is used only in look-up for further calculations of sigma(r) and not otherwise!
    !and prevents a large number of calls to the sigint functions
    IMPLICIT NONE
    TYPE(cosmology), INTENT(INOUT) :: cosm
    REAL*8, ALLOCATABLE :: rtab(:), sigtab(:)
    REAL*8 :: r, sig
    INTEGER :: i
    INTEGER, PARAMETER :: nsig=64 !Number of entries for sigma(R) tables
    REAL*8, PARAMETER :: rmin=1d-4 !Minimum r value (NB. sigma(R) needs to be power-law below)
    REAL*8, PARAMETER :: rmax=1d3 !Maximum r value (NB. sigma(R) needs to be power-law above)

    !These must be not allocated before sigma calculations otherwise when sigma(r) is called
    !otherwise sigma(R) looks for the result in the tables
    IF(ALLOCATED(cosm%r_sigma)) DEALLOCATE(cosm%r_sigma)
    IF(ALLOCATED(cosm%sigma)) DEALLOCATE(cosm%sigma)   

    !These values of 'r' work fine for any power spectrum of cosmological importance
    !Having nsig as a 2** number is most efficient for the look-up routines
    !rmin and rmax need to be decided in advance and are chosen such that
    !R vs. sigma(R) is a power-law below and above these values of R   
    !rmin=1d-4
    !rmax=1d3
    cosm%nsig=nsig

    IF(ihm==1) WRITE(*,*) 'SIGTAB: Filling sigma interpolation table'
    IF(ihm==1) WRITE(*,*) 'SIGTAB: Rmin:', rmin
    IF(ihm==1) WRITE(*,*) 'SIGTAB: Rmax:', rmax
    IF(ihm==1) WRITE(*,*) 'SIGTAB: Values:', nsig

    ALLOCATE(rtab(nsig),sigtab(nsig))

    DO i=1,nsig

       !Equally spaced r in log
       r=exp(log(rmin)+log(rmax/rmin)*float(i-1)/float(nsig-1))

       sig=sigma(r,0.d0,cosm)

       rtab(i)=r
       sigtab(i)=sig

    END DO

    !Must be allocated after the sigtab calulation above
    ALLOCATE(cosm%r_sigma(nsig),cosm%sigma(nsig))

    cosm%r_sigma=rtab
    cosm%sigma=sigtab

    DEALLOCATE(rtab,sigtab)

    IF(ihm==1) WRITE(*,*) 'SIGTAB: Done'
    IF(ihm==1) WRITE(*,*)

  END SUBROUTINE fill_sigtab

  FUNCTION sigma(r,z,cosm)

    !Gets sigma(R)
    IMPLICIT NONE
    REAL*8 :: sigma
    REAL*8, INTENT(IN) :: r, z
    TYPE(cosmology), INTENT(IN) :: cosm
    !REAL*8, PARAMETER :: acc=1d-4
    INTEGER, PARAMETER :: iorder=3
    REAL*8, PARAMETER :: rsplit=1d-2

    IF(r>=rsplit) THEN
       sigma=sqrt(sigint0(r,z,cosm,acc,iorder))
    ELSE IF(r<rsplit) THEN
       sigma=sqrt(sigint1(r,z,cosm,acc,iorder)+sigint2(r,z,cosm,acc,iorder))
    ELSE
       STOP 'SIGMA: Error, something went wrong'
    END IF

  END FUNCTION sigma

  FUNCTION sigma_integrand(k,R,z,cosm)

    !The integrand for the sigma(R) integrals
    IMPLICIT NONE
    REAL*8 :: sigma_integrand
    REAL*8, INTENT(IN) :: k, R, z
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8 :: y, w_hat

    IF(k==0.d0) THEN
       sigma_integrand=0.d0
    ELSE
       y=k*R
       w_hat=wk_tophat(y)
       sigma_integrand=p_lin(k,z,cosm)*(w_hat**2)/k
    END IF

  END FUNCTION sigma_integrand

  FUNCTION sigma_integrand_transformed(t,R,f,z,cosm)

    !The integrand for the sigma(R) integrals
    IMPLICIT NONE
    REAL*8 :: sigma_integrand_transformed
    REAL*8, INTENT(IN) :: t, R, z
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8 :: k, y, w_hat
    
    INTERFACE
       FUNCTION f(x)
         REAL*8 :: f
         REAL*8, INTENT(IN) :: x
       END FUNCTION f
    END INTERFACE

    !Integrand to the sigma integral in terms of t. Defined by k=(1/t-1)/f(R) where f(R) is *any* function

    IF(t==0.d0) THEN
       !t=0 corresponds to k=infintiy when W(kR)=0.
       sigma_integrand_transformed=0.d0
    ELSE IF(t==1.d0) THEN
       !t=1 corresponds to k=0. when P(k)=0.
       sigma_integrand_transformed=0.d0
    ELSE
       !f(R) can be *any* function of R here to improve integration speed
       k=(-1.d0+1.d0/t)/f(R)
       y=k*R
       w_hat=wk_tophat(y)
       sigma_integrand_transformed=p_lin(k,z,cosm)*(w_hat**2)/(t*(1.d0-t))
    END IF

  END FUNCTION sigma_integrand_transformed

  FUNCTION sigint0(r,z,cosm,acc,iorder)

    !Integrates between a and b until desired accuracy is reached
    !Stores information to reduce function calls
    IMPLICIT NONE
    REAL*8 :: sigint0
    REAL*8, INTENT(IN) :: r, z
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8, INTENT(IN) :: acc
    INTEGER, INTENT(IN) :: iorder
    INTEGER :: i, j
    INTEGER :: n
    REAL*8 :: x, dx
    REAL*8 :: f1, f2, fx
    REAL*8 :: sum_n, sum_2n, sum_new, sum_old
    INTEGER, PARAMETER :: jmin=5
    INTEGER, PARAMETER :: jmax=30
    REAL*8, PARAMETER :: a=0.d0 !Integration lower limit (corresponts to k=inf)
    REAL*8, PARAMETER :: b=1.d0 !Integration upper limit (corresponds to k=0)

    IF(a==b) THEN

       !Fix the answer to zero if the integration limits are identical
       sigint0=0.d0

    ELSE

       !Reset the sum variable for the integration
       sum_2n=0.d0

       DO j=1,jmax

          !Note, you need this to be 1+2**n for some integer n
          !j=1 n=2; j=2 n=3; j=3 n=5; j=4 n=9; ...'
          n=1+2**(j-1)

          !Calculate the dx interval for this value of 'n'
          dx=(b-a)/REAL(n-1)

          IF(j==1) THEN

             !The first go is just the trapezium of the end points
             f1=sigma_integrand_transformed(a,r,f0_rapid,z,cosm)
             f2=sigma_integrand_transformed(b,r,f0_rapid,z,cosm)
             sum_2n=0.5d0*(f1+f2)*dx

          ELSE

             !Loop over only new even points to add these to the integral
             DO i=2,n,2
                x=a+(b-a)*REAL(i-1)/REAL(n-1)
                fx=sigma_integrand_transformed(x,r,f0_rapid,z,cosm)
                sum_2n=sum_2n+fx
             END DO

             !Now create the total using the old and new parts
             sum_2n=sum_n/2.d0+sum_2n*dx

             !Now calculate the new sum depending on the integration order
             IF(iorder==1) THEN  
                sum_new=sum_2n
             ELSE IF(iorder==3) THEN         
                sum_new=(4.d0*sum_2n-sum_n)/3.d0 !This is Simpson's rule and cancels error
             ELSE
                STOP 'SIGINT0: Error, iorder specified incorrectly'
             END IF

          END IF

          IF((j>=jmin) .AND. (ABS(-1.d0+sum_new/sum_old)<acc)) THEN
             !jmin avoids spurious early convergence
             sigint0=REAL(sum_new)
             EXIT
          ELSE IF(j==jmax) THEN
             STOP 'SIGINT0: Integration timed out'
          ELSE
             !Integral has not converged so store old sums and reset sum variables
             sum_old=sum_new
             sum_n=sum_2n
             sum_2n=0.d0
          END IF

       END DO

    END IF

  END FUNCTION sigint0

  FUNCTION f0_rapid(r)

    !This is the 'rapidising' function to increase integration speed
    !for sigma(R). Found by trial-and-error
    IMPLICIT NONE
    REAL*8 :: f0_rapid
    REAL*8, INTENT(IN) :: r
    REAL*8 :: alpha
    REAL*8, PARAMETER :: rsplit=1d-2

    IF(r>rsplit) THEN
       !alpha 0.3-0.5 works well
       alpha=0.5d0
    ELSE
       !If alpha=1 this goes tits up
       !alpha 0.7-0.9 works well
       alpha=0.8d0
    END IF

    f0_rapid=r**alpha

  END FUNCTION f0_rapid

  FUNCTION sigint1(r,z,cosm,acc,iorder)

    !Integrates between a and b until desired accuracy is reached
    !Stores information to reduce function calls
    IMPLICIT NONE
    REAL*8 :: sigint1
    REAL*8, INTENT(IN) :: r, z
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8, INTENT(IN) :: acc
    INTEGER, INTENT(IN) :: iorder
    REAL*8 :: a, b
    INTEGER :: i, j
    INTEGER :: n
    REAL*8 :: x, dx
    REAL*8 :: f1, f2, fx
    REAL*8 :: sum_n, sum_2n, sum_new, sum_old
    INTEGER, PARAMETER :: jmin=5
    INTEGER, PARAMETER :: jmax=30

    a=r/(r+r**.5d0)
    b=1.d0

    IF(a==b) THEN

       !Fix the answer to zero if the integration limits are identical
       sigint1=0.d0

    ELSE

       !Reset the sum variable for the integration
       sum_2n=0.d0

       DO j=1,jmax

          !Note, you need this to be 1+2**n for some integer n
          !j=1 n=2; j=2 n=3; j=3 n=5; j=4 n=9; ...'
          n=1+2**(j-1)

          !Calculate the dx interval for this value of 'n'
          dx=(b-a)/REAL(n-1)

          IF(j==1) THEN

             !The first go is just the trapezium of the end points
             f1=sigma_integrand_transformed(a,r,f1_rapid,z,cosm)
             f2=sigma_integrand_transformed(b,r,f1_rapid,z,cosm)
             sum_2n=0.5d0*(f1+f2)*dx

          ELSE

             !Loop over only new even points to add these to the integral
             DO i=2,n,2
                x=a+(b-a)*REAL(i-1)/REAL(n-1)
                fx=sigma_integrand_transformed(x,r,f1_rapid,z,cosm)
                sum_2n=sum_2n+fx
             END DO

             !Now create the total using the old and new parts
             sum_2n=sum_n/2.d0+sum_2n*dx

             !Now calculate the new sum depending on the integration order
             IF(iorder==1) THEN  
                sum_new=REAL(sum_2n)
             ELSE IF(iorder==3) THEN         
                sum_new=(4.d0*sum_2n-sum_n)/3.d0 !This is Simpson's rule and cancels error
             ELSE
                STOP 'SIGINT1: Error, iorder specified incorrectly'
             END IF

          END IF

          IF((j>=jmin) .AND. (ABS(-1.d0+sum_new/sum_old)<acc)) THEN
             !jmin avoids spurious early convergence
             sigint1=REAL(sum_new)
             EXIT
          ELSE IF(j==jmax) THEN
             STOP 'SIGINT1: Integration timed out'
          ELSE
             !Integral has not converged so store old sums and reset sum variables
             sum_old=sum_new
             sum_n=sum_2n
             sum_2n=0.d0
          END IF

       END DO

    END IF

  END FUNCTION sigint1

  FUNCTION f1_rapid(r)

    !This is the 'rapidising' function to increase integration speed
    !for sigma(R). Found by trial-and-error
    IMPLICIT NONE
    REAL*8 :: f1_rapid
    REAL*8, INTENT(IN) :: r
    REAL*8, PARAMETER :: alpha=0.5d0

    f1_rapid=r**alpha

  END FUNCTION f1_rapid

  FUNCTION sigint2(r,z,cosm,acc,iorder)

    !Integrates between a and b until desired accuracy is reached
    !Stores information to reduce function calls
    IMPLICIT NONE
    REAL*8 :: sigint2
    REAL*8, INTENT(IN) :: r, z
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8, INTENT(IN) :: acc
    INTEGER, INTENT(IN) :: iorder
    REAL*8 :: a, b
    INTEGER :: i, j
    INTEGER :: n
    REAL*8 :: x, dx
    REAL*8 :: f1, f2, fx
    REAL*8 :: sum_n, sum_2n, sum_new, sum_old
    INTEGER, PARAMETER :: jmin=5
    INTEGER, PARAMETER :: jmax=30
    REAL*8, PARAMETER :: C=10.d0 !How far to go out in 1/r units for integral

    a=1.d0/r
    b=C/r

    IF(a==b) THEN

       !Fix the answer to zero if the integration limits are identical
       sigint2=0.d0

    ELSE

       !Reset the sum variable for the integration
       sum_2n=0.d0

       DO j=1,jmax

          !Note, you need this to be 1+2**n for some integer n
          !j=1 n=2; j=2 n=3; j=3 n=5; j=4 n=9; ...'
          n=1+2**(j-1)

          !Calculate the dx interval for this value of 'n'
          dx=(b-a)/REAL(n-1)

          IF(j==1) THEN

             !The first go is just the trapezium of the end points
             f1=sigma_integrand(a,r,z,cosm)
             f2=sigma_integrand(b,r,z,cosm)
             sum_2n=0.5d0*(f1+f2)*dx

          ELSE

             !Loop over only new even points to add these to the integral
             DO i=2,n,2
                x=a+(b-a)*REAL(i-1)/REAL(n-1)
                fx=sigma_integrand(x,r,z,cosm)
                sum_2n=sum_2n+fx
             END DO

             !Now create the total using the old and new parts
             sum_2n=sum_n/2.d0+sum_2n*dx

             !Now calculate the new sum depending on the integration order
             IF(iorder==1) THEN  
                sum_new=sum_2n
             ELSE IF(iorder==3) THEN         
                sum_new=(4.d0*sum_2n-sum_n)/3.d0 !This is Simpson's rule and cancels error
             ELSE
                STOP 'SIGINT2: Error, iorder specified incorrectly'
             END IF

          END IF

          IF((j>=jmin) .AND. (ABS(-1.d0+sum_new/sum_old)<acc)) THEN
             !jmin avoids spurious early convergence
             sigint2=REAL(sum_new)
             !WRITE(*,*) 'INTEGRATE_STORE: Nint:', n
             EXIT
          ELSE IF(j==jmax) THEN
             STOP 'SIGINT2: Integration timed out'
          ELSE
             !Integral has not converged so store old sums and reset sum variables
             sum_old=sum_new
             sum_n=sum_2n
             sum_2n=0.d0
          END IF

       END DO

    END IF

  END FUNCTION sigint2

  FUNCTION sigma_cb(r,z,cosm)

    !USE cosdef
    IMPLICIT NONE
    REAL*8 :: sigma_cb
    REAL*8, INTENT(IN) :: r, z
    TYPE(cosmology), INTENT(IN) :: cosm

    !Finds sigma_cold from look-up tables
    !In this version sigma_cold=sigma

    sigma_cb=grow(z,cosm)*exp(find(log(r),log(cosm%r_sigma),log(cosm%sigma),cosm%nsig,3,3,2))

  END FUNCTION sigma_cb

  PURE FUNCTION wk_tophat(x)

    !The normlaised Fourier Transform of a top-hat
    IMPLICIT NONE
    REAL*8 :: wk_tophat
    REAL*8, INTENT(IN) :: x
    REAL*8, PARAMETER :: dx=1d-3

    !Taylor expansion used for low |x| to avoid cancellation problems

    IF(ABS(x)<ABS(dx)) THEN
       wk_tophat=1.d0-(x**2)/10.d0
    ELSE
       wk_tophat=3.d0*(sin(x)-x*cos(x))/(x**3)
    END IF

  END FUNCTION wk_tophat

  FUNCTION inttab(x,y,n,iorder)

    !Integrates tables y(x)dx
    IMPLICIT NONE
    REAL*8 :: inttab
    INTEGER, INTENT(IN) :: n
    REAL*8, INTENT(IN) :: x(n), y(n)
    REAL*8 :: a, b, c, d, h
    REAL*8 :: q1, q2, q3, qi, qf
    REAL*8 :: x1, x2, x3, x4, y1, y2, y3, y4, xi, xf
    REAL*8 :: sum
    INTEGER :: i, i1, i2, i3, i4
    INTEGER, INTENT(IN) :: iorder

    sum=0.d0

    IF(iorder==1) THEN

       !Sums over all Trapezia (a+b)*h/2
       DO i=1,n-1
          a=y(i+1)
          b=y(i)
          h=x(i+1)-x(i)
          sum=sum+(a+b)*h/2.d0
       END DO

    ELSE IF(iorder==2) THEN

       DO i=1,n-2

          x1=x(i)
          x2=x(i+1)
          x3=x(i+2)

          y1=y(i)
          y2=y(i+1)
          y3=y(i+2)

          CALL fit_quadratic(a,b,c,x1,y1,x2,y2,x3,y3)

          q1=a*(x1**3.)/3.+b*(x1**2.)/2.+c*x1
          q2=a*(x2**3.)/3.+b*(x2**2.)/2.+c*x2
          q3=a*(x3**3.)/3.+b*(x3**2.)/2.+c*x3

          !Takes value for first and last sections but averages over sections where you
          !have two independent estimates of the area
          IF(n==3) THEN
             sum=sum+q3-q1
          ELSE IF(i==1) THEN
             sum=sum+(q2-q1)+(q3-q2)/2.d0
          ELSE IF(i==n-2) THEN
             sum=sum+(q2-q1)/2.d0+(q3-q2)
          ELSE
             sum=sum+(q3-q1)/2.
          END IF

       END DO

    ELSE IF(iorder==3) THEN

       DO i=1,n-1

          !First choose the integers used for defining cubics for each section
          !First and last are different because the section does not lie in the *middle* of a cubic

          IF(i==1) THEN

             i1=1
             i2=2
             i3=3
             i4=4

          ELSE IF(i==n-1) THEN

             i1=n-3
             i2=n-2
             i3=n-1
             i4=n

          ELSE

             i1=i-1
             i2=i
             i3=i+1
             i4=i+2

          END IF

          x1=x(i1)
          x2=x(i2)
          x3=x(i3)
          x4=x(i4)

          y1=y(i1)
          y2=y(i2)
          y3=y(i3)
          y4=y(i4)

          CALL fit_cubic(a,b,c,d,x1,y1,x2,y2,x3,y3,x4,y4)

          !These are the limits of the particular section of integral
          xi=x(i)
          xf=x(i+1)

          qi=a*(xi**4.)/4.+b*(xi**3.)/3.+c*(xi**2.)/2.+d*xi
          qf=a*(xf**4.)/4.+b*(xf**3.)/3.+c*(xf**2.)/2.+d*xf

          sum=sum+qf-qi

       END DO

    ELSE

       STOP 'INTTAB: Error, order not specified correctly'

    END IF

    inttab=REAL(sum)

  END FUNCTION inttab

!!$  FUNCTION sigma_integrand(t,R,f,z,cosm)
!!$
!!$    !USE cosdef
!!$    IMPLICIT NONE
!!$    REAL*8 :: sigma_integrand
!!$    REAL*8, INTENT(IN) :: t, R, z
!!$    REAL*8 :: k, y, w_hat
!!$    TYPE(cosmology), INTENT(IN) :: cosm
!!$
!!$    INTERFACE
!!$       REAL*8 FUNCTION f(x)
!!$         REAL*8, INTENT(IN) :: x
!!$       END FUNCTION f
!!$    END INTERFACE
!!$
!!$    !Integrand to the sigma integral in terms of t. Defined by k=(1/t-1)/f(R) where f(R) is *any* function
!!$
!!$    IF(t==0.) THEN
!!$       !t=0 corresponds to k=infintiy when W(kR)=0.
!!$       sigma_integrand=0.
!!$    ELSE IF(t==1.) THEN
!!$       !t=1 corresponds to k=0. when P(k)=0.
!!$       sigma_integrand=0.
!!$    ELSE
!!$       !f(R) can be *any* function of R here to improve integration speed
!!$       k=(-1.+1./t)/f(R)
!!$       y=k*R
!!$       w_hat=wk_tophat(y)
!!$       sigma_integrand=p_lin(k,z,cosm)*(w_hat**2.)/(t*(1.-t))
!!$    END IF
!!$
!!$  END FUNCTION sigma_integrand

!!$  FUNCTION f_rapid(r)
!!$
!!$    IMPLICIT NONE
!!$    REAL*8 :: f_rapid
!!$    REAL*8, INTENT(IN) :: r
!!$    REAL*8 :: alpha
!!$
!!$    !This is the 'rapidising' function to increase integration speed
!!$    !for sigma(R). Found by trial-and-error
!!$
!!$    IF(r>1.e-2) THEN
!!$       !alpha 0.3-0.5 works well
!!$       alpha=0.5
!!$    ELSE
!!$       !If alpha=1 this goes tits up
!!$       !alpha 0.7-0.9 works well
!!$       alpha=0.8
!!$    END IF
!!$
!!$    f_rapid=r**alpha
!!$
!!$  END FUNCTION f_rapid

!!$  FUNCTION sigint0(r,z,cosm,acc,iorder)
!!$
!!$    !Integrates between a and b until desired accuracy is reached!
!!$    !USE cosdef
!!$    IMPLICIT NONE
!!$    REAL*8 :: sigint0
!!$    REAL*8, INTENT(IN) :: r, z
!!$    REAL*8, INTENT(IN) :: acc
!!$    INTEGER, INTENT(IN) :: iorder
!!$    TYPE(cosmology), INTENT(IN) :: cosm
!!$    INTEGER :: i, j, n
!!$    REAL*8 :: x, dx, weight
!!$    REAL*8 :: sum1, sum2
!!$    INTEGER, PARAMETER :: ninit=8 !Initial number of points
!!$    INTEGER, PARAMETER :: jmax=30 !Maximum number of attempts  
!!$
!!$    sum1=0.d0
!!$    sum2=0.d0
!!$
!!$    DO j=1,jmax
!!$
!!$       n=ninit*2**(j-1)
!!$
!!$       !Avoids the end-points where the integrand is 0 anyway
!!$       DO i=2,n-1
!!$
!!$          !Get the weights
!!$          IF(iorder==1) THEN
!!$             !Composite trapezium weights
!!$             IF(i==1 .OR. i==n) THEN
!!$                weight=0.5d0
!!$             ELSE
!!$                weight=1.d0
!!$             END IF
!!$          ELSE IF(iorder==2) THEN
!!$             !Composite extended formula weights
!!$             IF(i==1 .OR. i==n) THEN
!!$                weight=0.416666666666d0
!!$             ELSE IF(i==2 .OR. i==n-1) THEN
!!$                weight=1.083333333333d0
!!$             ELSE
!!$                weight=1.d0
!!$             END IF
!!$          ELSE IF(iorder==3) THEN
!!$             !Composite Simpson weights
!!$             IF(i==1 .OR. i==n) THEN
!!$                weight=0.375d0
!!$             ELSE IF(i==2 .OR. i==n-1) THEN
!!$                weight=1.166666666666
!!$             ELSE IF(i==3 .OR. i==n-2) THEN
!!$                weight=0.958333333333
!!$             ELSE
!!$                weight=1.d0
!!$             END IF
!!$          ELSE
!!$             STOP 'SIGINT0: Error, order specified incorrectly'
!!$          END IF
!!$
!!$          !x is defined on the interval 0 -> 1
!!$          x=float(i-1)/float(n-1)
!!$
!!$          sum2=sum2+weight*sigma_integrand(x,r,f_rapid,z,cosm)
!!$
!!$       END DO
!!$
!!$       dx=1.d0/DBLE(n-1)
!!$       sum2=sum2*dx
!!$       sum2=sqrt(sum2)
!!$
!!$       IF(j .NE. 1 .AND. ABS(-1.+sum2/sum1)<acc) THEN
!!$          sigint0=real(sum2)
!!$          EXIT
!!$       ELSE IF(j==jmax) THEN
!!$          WRITE(*,*)
!!$          WRITE(*,*) 'SIGINT: r:', r
!!$          WRITE(*,*) 'SIGINT: Integration timed out'
!!$          WRITE(*,*)
!!$          STOP
!!$       ELSE
!!$          sum1=sum2
!!$          sum2=0.d0
!!$       END IF
!!$
!!$    END DO
!!$
!!$  END FUNCTION sigint0
!!$
!!$  FUNCTION sigint1(r,z,cosm,acc,iorder)
!!$
!!$    !Integrates between a and b until desired accuracy is reached!
!!$    !USE cosdef
!!$    IMPLICIT NONE
!!$    REAL*8 :: sigint1
!!$    REAL*8, INTENT(IN) :: r, z
!!$    REAL*8, INTENT(IN) :: acc
!!$    INTEGER, INTENT(IN) :: iorder
!!$    TYPE(cosmology), INTENT(IN) :: cosm
!!$    INTEGER :: i, j, n
!!$    REAL*8 :: x, dx, weight, xmin, xmax, k
!!$    REAL*8 :: sum1, sum2  
!!$    INTEGER, PARAMETER :: ninit=8 !Initial number of points
!!$    INTEGER, PARAMETER :: jmax=30 !Maximum number of attempts  
!!$
!!$    sum1=0.d0
!!$    sum2=0.d0
!!$
!!$    xmin=r/(r+r**.5)
!!$    xmax=1.
!!$
!!$    DO j=1,jmax
!!$
!!$       n=ninit*2**(j-1)
!!$
!!$       !Avoids the end-point where the integrand is 0 anyway
!!$       DO i=1,n-1
!!$
!!$          x=xmin+(xmax-xmin)*float(i-1)/float(n-1)
!!$
!!$          !Get the weights
!!$          IF(iorder==1) THEN
!!$             !Composite trapezium weights
!!$             IF(i==1 .OR. i==n) THEN
!!$                weight=0.5d0
!!$             ELSE
!!$                weight=1.d0
!!$             END IF
!!$          ELSE IF(iorder==2) THEN
!!$             !Composite extended formula weights
!!$             IF(i==1 .OR. i==n) THEN
!!$                weight=0.416666666666d0
!!$             ELSE IF(i==2 .OR. i==n-1) THEN
!!$                weight=1.083333333333d0
!!$             ELSE
!!$                weight=1.d0
!!$             END IF
!!$          ELSE IF(iorder==3) THEN
!!$             !Composite Simpson weights
!!$             IF(i==1 .OR. i==n) THEN
!!$                weight=0.375d0
!!$             ELSE IF(i==2 .OR. i==n-1) THEN
!!$                weight=1.166666666666
!!$             ELSE IF(i==3 .OR. i==n-2) THEN
!!$                weight=0.958333333333
!!$             ELSE
!!$                weight=1.d0
!!$             END IF
!!$          ELSE
!!$             STOP 'WININT_NORMAL: Error, order specified incorrectly'
!!$          END IF
!!$
!!$          k=(-1.+1./x)/r**.5
!!$          sum2=sum2+weight*p_lin(k,z,cosm)*(wk_tophat(k*r)**2.)/(x*(1.-x))
!!$
!!$       END DO
!!$
!!$       dx=(xmax-xmin)/float(n-1)
!!$       sum2=sum2*dx
!!$
!!$       IF(j .NE. 1 .AND. ABS(-1.+sum2/sum1)<acc) THEN
!!$          sigint1=real(sum2)
!!$          EXIT
!!$       ELSE IF(j==jmax) THEN
!!$          WRITE(*,*)
!!$          WRITE(*,*) 'SIGINT1: r:', r
!!$          WRITE(*,*) 'SIGINT1: Integration timed out'
!!$          WRITE(*,*)
!!$          STOP
!!$       ELSE
!!$          sum1=sum2
!!$          sum2=0.d0
!!$       END IF
!!$
!!$    END DO
!!$
!!$  END FUNCTION sigint1
!!$
!!$  FUNCTION sigint2(r,z,cosm,acc,iorder)
!!$
!!$    !Integrates between a and b until desired accuracy is reached!
!!$    !USE cosdef
!!$    IMPLICIT NONE
!!$    REAL*8 :: sigint2
!!$    REAL*8, INTENT(IN) :: r, z
!!$    REAL*8, INTENT(IN) :: acc
!!$    INTEGER, INTENT(IN) :: iorder
!!$    TYPE(cosmology), INTENT(IN) :: cosm
!!$    INTEGER :: i, j, n
!!$    REAL*8 :: x, dx, weight, xmin, xmax, A
!!$    REAL*8 :: sum1, sum2
!!$    INTEGER, PARAMETER :: ninit=8 !Initial number of points
!!$    INTEGER, PARAMETER :: jmax=30 !Maximum number of attempts  
!!$
!!$    sum1=0.d0
!!$    sum2=0.d0
!!$
!!$    !How far to go out in 1/r units for integral
!!$    A=10.
!!$
!!$    xmin=1./r
!!$    xmax=A/r
!!$
!!$    DO j=1,jmax
!!$
!!$       n=ninit*2**(j-1)
!!$
!!$       DO i=1,n
!!$
!!$          x=xmin+(xmax-xmin)*float(i-1)/float(n-1)
!!$
!!$          !Get the weights
!!$          IF(iorder==1) THEN
!!$             !Composite trapezium weights
!!$             IF(i==1 .OR. i==n) THEN
!!$                weight=0.5d0
!!$             ELSE
!!$                weight=1.d0
!!$             END IF
!!$          ELSE IF(iorder==2) THEN
!!$             !Composite extended formula weights
!!$             IF(i==1 .OR. i==n) THEN
!!$                weight=0.416666666666d0
!!$             ELSE IF(i==2 .OR. i==n-1) THEN
!!$                weight=1.083333333333d0
!!$             ELSE
!!$                weight=1.d0
!!$             END IF
!!$          ELSE IF(iorder==3) THEN
!!$             !Composite Simpson weights
!!$             IF(i==1 .OR. i==n) THEN
!!$                weight=0.375d0
!!$             ELSE IF(i==2 .OR. i==n-1) THEN
!!$                weight=1.166666666666
!!$             ELSE IF(i==3 .OR. i==n-2) THEN
!!$                weight=0.958333333333
!!$             ELSE
!!$                weight=1.d0
!!$             END IF
!!$          ELSE
!!$             STOP 'WININT_NORMAL: Error, order specified incorrectly'
!!$          END IF
!!$
!!$          !Integrate linearly in k for the rapidly oscillating part
!!$          sum2=sum2+weight*p_lin(x,z,cosm)*(wk_tophat(x*r)**2.)/x
!!$
!!$       END DO
!!$
!!$       dx=(xmax-xmin)/float(n-1)
!!$       sum2=sum2*dx
!!$
!!$       IF(j .NE. 1 .AND. ABS(-1.+sum2/sum1)<acc) THEN
!!$          sigint2=real(sum2)
!!$          EXIT
!!$       ELSE IF(j==jmax) THEN
!!$          WRITE(*,*)
!!$          WRITE(*,*) 'SIGINT2: r:', r
!!$          WRITE(*,*) 'SIGINT2: Integration timed out'
!!$          WRITE(*,*)
!!$          STOP
!!$       ELSE
!!$          sum1=sum2
!!$          sum2=0.d0
!!$       END IF
!!$
!!$    END DO
!!$
!!$  END FUNCTION sigint2

  FUNCTION win_type(ik,itype,k,m,rv,rs,z,lut,cosm)

    IMPLICIT NONE
    REAL*8 :: win_type
    REAL*8, INTENT(IN) :: k, m, rv, rs, z
    INTEGER, INTENT(IN) :: itype, ik
    TYPE(cosmology), INTENT(IN) :: cosm
    TYPE(tables), INTENT(IN) :: lut

    !IF(ik .NE. 0 .OR. ik .NE. 1) STOP 'WIN_TYPE: ik should be either 0 or 1'

    IF(itype==-1) THEN
       !Overdensity if all the matter were CDM
       win_type=win_DMONLY(ik,k,m,rv,rs,cosm)
    ELSE IF(itype==0) THEN
       !matter overdensity (sum of CDM, gas, stars)
       win_type=win_total(ik,k,m,rv,rs,cosm)
    ELSE IF(itype==1) THEN
       !CDM overdensity
       win_type=win_CDM(ik,k,m,rv,rs,cosm)
    ELSE IF(itype==2) THEN
       !All gas, both bound and free overdensity
       win_type=win_gas(ik,k,m,rv,rs,cosm)
    ELSE IF(itype==3) THEN
       !Stellar overdensity
       win_type=win_star(ik,k,m,rv,rs,cosm)
    ELSE IF(itype==4) THEN
       !Bound gas overdensity
       win_type=win_boundgas(ik,k,m,rv,rs,cosm)
    ELSE IF(itype==5) THEN
       !Free gas overdensity
       win_type=win_freegas(ik,k,m,rv,rs,cosm)
    ELSE IF(itype==6) THEN
       !Pressure
       win_type=win_pressure(ik,k,m,rv,rs,z,lut,cosm)
    ELSE
       STOP 'WIN_TYPE: Error, itype not specified correclty' 
    END IF

  END FUNCTION win_type

  FUNCTION win_total(ik,k,m,rv,rs,cosm)

    IMPLICIT NONE
    REAL*8 :: win_total
    INTEGER, INTENT(IN) :: ik
    REAL*8, INTENT(IN) :: k, rv, rs, m
    TYPE(cosmology), INTENT(IN) :: cosm

    win_total=win_CDM(ik,k,m,rv,rs,cosm)+win_gas(ik,k,m,rv,rs,cosm)+win_star(ik,k,m,rv,rs,cosm)

  END FUNCTION win_total

  FUNCTION win_gas(ik,k,m,rv,rs,cosm)

    IMPLICIT NONE
    REAL*8 :: win_gas
    INTEGER, INTENT(IN) :: ik
    REAL*8, INTENT(IN) :: k, m, rv, rs
    TYPE(cosmology), INTENT(IN) :: cosm

    win_gas=win_boundgas(ik,k,m,rv,rs,cosm)+win_freegas(ik,k,m,rv,rs,cosm)

  END FUNCTION win_gas

  FUNCTION win_DMONLY(ik,k,m,rv,rs,cosm)

    IMPLICIT NONE
    REAL*8 :: win_DMONLY
    INTEGER, INTENT(IN) :: ik
    REAL*8, INTENT(IN) :: k, m, rv, rs
    TYPE(cosmology), INTENT(IN) :: cosm
    INTEGER :: irho
    REAL*8 :: r, rmax

    !Set the DMONLY halo model
    INTEGER, PARAMETER :: imod=1

    IF(imod==1) THEN
       !Analytical NFW
       irho=5
    ELSE IF(imod==2) THEN
       !Non-analyical NFW
       irho=4
    ELSE IF(imod==3) THEN
       !Tophat
       irho=2
    ELSE
       STOP 'WIN_DMONLY: Error, imod specified incorrectly'
    END IF

    rmax=rv

    IF(ik==0) THEN
       r=k
       win_DMONLY=rho(r,rmax,rv,rs,irho)
       win_DMONLY=win_DMONLY/normalisation(rmax,rv,rs,irho)
    ELSE IF(ik==1) THEN
       !Properly normalise and convert to overdensity
       win_DMONLY=m*win_norm(k,rmax,rv,rs,irho)/matter_density(cosm)
    ELSE
       STOP 'WIN_DMONLY: ik not specified correctly'
    END IF

  END FUNCTION win_DMONLY

  FUNCTION win_CDM(ik,k,m,rv,rs,cosm)

    IMPLICIT NONE
    REAL*8 :: win_CDM
    INTEGER, INTENT(IN) :: ik
    REAL*8, INTENT(IN) :: k, m, rv, rs
    TYPE(cosmology), INTENT(IN) :: cosm
    INTEGER :: irho
    REAL*8 :: rss, dc, r

    !Set the model
    INTEGER, PARAMETER :: imod=1

    IF(imod==1) THEN
       !Analytical NFW
       irho=5
       rss=rs
    ELSE IF(imod==2) THEN
       !NFW with increase concentation
       irho=5
       dc=1. !Increase in concentration (delta_c)
       rss=1./(1./rs+dc/rv)
    ELSE
       STOP 'WIN_CDM: Error, imod specified incorrectly'
    END IF

    IF(ik==0) THEN
       r=k
       win_CDM=rho(r,rv,rv,rss,irho)
       win_CDM=win_CDM/normalisation(rv,rv,rss,irho)
    ELSE IF(ik==1) THEN
       !Properly normalise and convert to overdensity
       win_CDM=m*win_norm(k,rv,rv,rss,irho)/matter_density(cosm)
    ELSE
       STOP 'WIN_CDM: ik not specified correctly'
    END IF

    win_CDM=halo_CDM_fraction(m,cosm)*win_CDM

  END FUNCTION win_CDM

  FUNCTION win_star(ik,k,m,rv,rs,cosm)

    IMPLICIT NONE
    REAL*8 :: win_star
    INTEGER, INTENT(IN) :: ik
    REAL*8, INTENT(IN) :: k, m, rv, rs
    TYPE(cosmology), INTENT(IN) :: cosm
    INTEGER :: irho
    REAL*8 :: rstar, r, rmax
    INTEGER, PARAMETER :: imod=2 !Set the model
    INTEGER, PARAMETER :: idelta=0 !Decide if we treat stars as a delta function at r=0 or not

    IF(imod==1) THEN
       !Fedeli (2014)
       irho=7
       rstar=0.11*rv
       rmax=rv
    ELSE IF(imod==2) THEN
       !Schneider (2015), following Mohammed (2014)
       irho=9
       rmax=rv
       rstar=0.01*rv
    ELSE
       STOP 'WIN_STAR: Error, imod_star specified incorrectly'
    END IF

    IF(ik==0) THEN
       r=k
       win_star=rho(r,rmax,rv,rstar,irho)
       win_star=win_star/normalisation(rmax,rv,rstar,irho)
    ELSE IF(ik==1) THEN    
       !IF(imod==1) THEN
       !   win_star=win_norm(k,rmax,rv,rstar,irho)
       !ELSE IF(imod==2) THEN
       !   !Density profiles drops fast, and this plays havoc with the 'bumps' integration scheme.
       !   !Setting w(k)=1. is equivalent to assuming the stars are a delta function at r=0 (not such a bad thing)
       !   win_star=win_norm(k,rmax,rv,rstar,irho)
       !   !win_star=1.d0
       !ELSE
       !   STOP 'WIN_STAR: Error, imod_star specified incorrectly'
       !END IF
       !win_star=win_star*m/matter_density(cosm)
       IF(idelta==0) THEN
          !Properly normalise and convert to overdensity
          win_star=m*win_norm(k,rmax,rv,rstar,irho)/matter_density(cosm)
       ELSE IF(idelta==1) THEN
          !Fix wk=1
          win_star=m/matter_density(cosm)
       END IF
    ELSE
       STOP 'WIN_STAR: ik not specified correctly'
    END IF

    win_star=halo_star_fraction(m,cosm)*win_star

  END FUNCTION win_star

  FUNCTION win_boundgas(ik,k,m,rv,rs,cosm)

    IMPLICIT NONE
    REAL*8 :: win_boundgas
    INTEGER, INTENT(IN) :: ik
    REAL*8, INTENT(IN) :: k, m, rv, rs
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8 :: rb, r
    INTEGER :: irho

    !Set the model
    INTEGER, PARAMETER :: imod=3

    IF(imod==1) THEN
       !Cored isothermal profile (Fedeli 2014)
       irho=6
       rb=0.35*rv
    ELSE IF(imod==2) THEN
       !KS profile with NFW transition
       irho=8
       rb=rs
       !Should define rt here too, but would need an extra parameter in rho(r) function
    ELSE IF(imod==3) THEN
       !Pure KS profile
       irho=11
       rb=rs
    ELSE
       STOP 'WIN_BOUNDGAS: Error, imod_boundgas specified incorrectly'
    END IF

    IF(ik==0) THEN
       r=k
       win_boundgas=rho(r,rv,rv,rb,irho)
       win_boundgas=win_boundgas/normalisation(rv,rv,rb,irho)
    ELSE IF(ik==1) THEN
       !Properly normalise and convert to overdensity
       win_boundgas=m*win_norm(k,rv,rv,rb,irho)/matter_density(cosm)
    ELSE
       STOP 'WIN_BOUNDGAS: ik not specified correctly'
    END IF

    win_boundgas=halo_boundgas_fraction(m,cosm)*win_boundgas

  END FUNCTION win_boundgas

  FUNCTION win_freegas(ik,k,m,rv,rs,cosm)

    IMPLICIT NONE
    REAL*8 :: win_freegas
    INTEGER, INTENT(IN) :: ik
    REAL*8, INTENT(IN) :: k, m, rv, rs
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8 :: rfree, rmax, r
    INTEGER :: irho

    !Set the model
    INTEGER, PARAMETER :: imod=2

    IF(imod==1) THEN
       !Simple isothermal model, motivated by constant velocity and rate expulsion
       irho=1
       rmax=3.5*rv
       rfree=rmax
    ELSE IF(imod==2) THEN
       !Ejected gas model from Schneider (2015)
       irho=10
       rmax=15.*rv
       rfree=1.*rv
    ELSE
       STOP 'WIN_FREEGAS: Error, imod_freegas specified incorrectly'
    END IF

    IF(ik==0) THEN
       r=k
       win_freegas=rho(r,rmax,rv,rfree,irho)
       win_freegas=win_freegas/normalisation(rmax,rv,rfree,irho)
    ELSE IF(ik==1) THEN
       !Properly normalise and convert to overdensity
       win_freegas=m*win_norm(k,rmax,rv,rfree,irho)/matter_density(cosm)
    ELSE
       STOP 'WIN_FREEGAS: ik not specified correctly'
    END IF

    win_freegas=halo_freegas_fraction(m,cosm)*win_freegas

  END FUNCTION win_freegas

  FUNCTION win_pressure(ik,k,m,rv,rs,z,lut,cosm)

    IMPLICIT NONE
    REAL*8 :: win_pressure
    INTEGER, INTENT(IN) :: ik
    REAL*8, INTENT(IN) :: k, m, rv, rs, z
    TYPE(cosmology), INTENT(IN) :: cosm
    TYPE(tables), INTENT(IN) :: lut

    win_pressure=win_pressure_bound(ik,k,m,rv,rs,z,lut,cosm)+win_pressure_free(ik,k,m,rv,rs,z,lut,cosm)

  END FUNCTION win_pressure

  FUNCTION virial_temperature(M,R)

    !Computes the halo virial temperature in K
    IMPLICIT NONE
    REAL*8 :: virial_temperature
    REAL*8 :: M, R
    REAL*8, PARAMETER :: fac=1. !Virial relation pre-factor (1/2, 3/2, ... ?)

    virial_temperature=fac*bigG*((m*msun)*mp)/(kb*(r*mpc))
    
  END FUNCTION virial_temperature

  FUNCTION win_pressure_bound(ik,k,m,rv,rs,z,lut,cosm)

    IMPLICIT NONE
    REAL*8 :: win_pressure_bound
    INTEGER, INTENT(IN) :: ik
    REAL*8, INTENT(IN) :: k, m, rv, rs, z
    TYPE(cosmology), INTENT(IN) :: cosm
    TYPE(tables), INTENT(IN) :: lut
    REAL*8 :: rho0, T0, r, a
    REAL*8 :: E, alphap, r500c, m500c, rmax, fac, hsbias
    INTEGER :: irho_pressure, irho_density, irho

    !Select model
    INTEGER, PARAMETER :: imod=2

    !1 - Gas model
    !2 - UPP
    !3 - Isothermal beta model

    IF(imod==1) THEN

       !Set KS profile
       irho_density=11
       irho_pressure=13

       IF(ik==0) THEN
          r=k
          win_pressure_bound=rho(r,rv,rv,rs,irho_pressure)
       ELSE IF(ik==1) THEN
          !The pressure window is T(r) x rho(r), we want unnormalised, so multiply by normalisation
          win_pressure_bound=win_norm(k,rv,rv,rs,irho_pressure)*normalisation(rv,rv,rs,irho_pressure) 
       ELSE
          STOP 'WIN_PRESSURE_BOUND: Error, ik not specified correctly'
       END IF

       !Calculate the value of the density profile prefactor
       !also change units from cosmological to SI
       rho0=m*halo_boundgas_fraction(m,cosm)/normalisation(rv,rv,rs,irho_density)
       rho0=rho0*msun/mpc**3.

       !Calculate the value of the temperature prefactor
       !fac=1. !Fudge factor
       !T0=fac*bigG*((m*msun)*mp)/(kb*(rv*mpc)) !Virial temperature
       T0=virial_temperature(m,rv)

       win_pressure_bound=win_pressure_bound*rho0*T0*kb/(mp*mue)

    ELSE IF(imod==2) THEN

       !Set UPP profile
       irho=14

       r500c=exp(find(log(m),log(lut%m),log(lut%r500c),lut%n,3,3,2))
       !r500c=1.22d0
       rmax=1.*rv

       !UPP is written in terms of physical coordinates
       a=1./(1.+z)
       !a=1.
       IF(ik==0) THEN
          r=k
          win_pressure_bound=rho(a*r,a*rmax,a*r500c,a*rs,irho)
       ELSE IF(ik==1) THEN
          win_pressure_bound=winint(k/a,a*rmax,a*r500c,a*rs,irho)
       ELSE
          STOP 'WIN_PRESSURE_BOUND: Error, ik not specified correctly'
       END IF

       !UPP parameter
       alphap=0.12
       hsbias=1. !How different is inferred hydrostatic mass from true mass? (M_obs = hsbias * M_true)

       !Upp, P(x), equation 4.1 in Ma et al. (2015)
       m500c=exp(find(log(m),log(lut%m),log(lut%m500c),lut%n,3,3,2))
       !m500c=cosm%h*5.23d14
       m500c=m500c*hsbias

       !Dimensionless Hubble
       E=sqrt(hubble2(z,cosm))

       !WRITE(*,*) 'M [Msun/h]:', REAL(m)
       !WRITE(*,*) 'M500c [Msun/h]:', REAL(m500c)
       !WRITE(*,*) 'r500c [Mpc/h]:', r500c
       !WRITE(*,*)

       !Pre-factors from equation 4.1 in Ma et al. (2015)
       win_pressure_bound=win_pressure_bound*((m500c/2.1d14)**(alphap+2./3.))*(E**(8./3.))*3.37

       !Convert from eV cm^-3 to J m^-3
       win_pressure_bound=win_pressure_bound*eV*(0.01**(-3.))

       !Is pressure comoving or not??
       !win_pressure_bound=win_pressure_bound/(1.+z)**2.

    ELSE IF(imod==3) THEN
       
       irho=6 !Set cored isothermal profile with beta=2/3 (okay to use density for pressure because T is constant)

       IF(ik==0) THEN
          r=k
          win_pressure_bound=rho(r,rv,rv,rs,irho)
       ELSE IF(ik==1) THEN
          !The pressure window is T(r) x rho(r), we want unnormalised, so multiply by normalisation
          win_pressure_bound=win_norm(k,rv,rv,rs,irho)*normalisation(rv,rv,rs,irho) 
       ELSE
          STOP 'WIN_PRESSURE_BOUND: Error, ik not specified correctly'
       END IF

       !Calculate the value of the density profile prefactor
       !also change units from cosmological to SI
       rho0=m*halo_boundgas_fraction(m,cosm)/normalisation(rv,rv,rs,irho)
       rho0=rho0*msun/mpc**3.

       !Calculate the value of the temperature prefactor
       !fac=1. !Fudge factor
       !T0=fac*bigG*((m*msun)*mp)/(kb*(rv*mpc)) !Virial temperature
       T0=virial_temperature(m,rv)

       win_pressure_bound=win_pressure_bound*rho0*T0*kb/(mp*mue)
       
    ELSE
       STOP 'WIN_PRESSURE_BOUND: Error, imod not specified correctly'
    END IF

  END FUNCTION win_pressure_bound

  FUNCTION win_pressure_free(ik,k,m,rv,rs,z,lut,cosm)

    IMPLICIT NONE
    REAL*8 :: win_pressure_free
    INTEGER, INTENT(IN) :: ik
    REAL*8, INTENT(IN) :: k, m, rv, rs, z
    TYPE(cosmology), INTENT(IN) :: cosm
    TYPE(tables), INTENT(IN) :: lut
    REAL*8 :: rho0, T0, rmax, rfree, fac
    INTEGER :: irho

    !Set the model
    INTEGER, PARAMETER :: imod=1

    IF(imod==1) THEN

       !Set exponential profile
       irho=10

       !Calculate the value of the density profile prefactor
       !and change units from cosmological to SI
       rho0=m*halo_freegas_fraction(m,cosm)/normalisation(rv,rv,rs,10)
       rho0=rho0*msun/mpc**3.

       !Calculate the value of the temperature prefactor
       fac=1d-3 !Fudge factor
       T0=fac*bigG*((m*msun)*mp)/(kb*(rv*mpc)) !Virial temperature
       !T0=1e4 !Randomly chosen constant temperature

       rmax=15.*rv
       rfree=1.*rv
       IF(ik==0) THEN
          win_pressure_free=win_norm(k,rmax,rmax,rfree,irho)*rho0*T0*kb/(mp*mue)
       ELSE IF(ik==1) THEN  
          win_pressure_free=win_norm(k,rmax,rmax,rfree,irho)*normalisation(rmax,rv,rfree,irho)
          !Pre factors to convert from Temp x density -> pressure (Temp x n_e)
          win_pressure_free=win_pressure_free*rho0*T0
          !Sum up contributions and multiply by pre-factors
          win_pressure_free=win_pressure_free*kb/(mp*mue)
       ELSE
          STOP 'WIN_PRESSURE_FREE: Error, ik not specified correctly'
       END IF

    ELSE IF(imod==2) THEN
       !Ignore contribution from pressure in free gas
       win_pressure_free=0.
    ELSE
       STOP 'WIN_PRESSURE_FREE: Error, imod not specified correctly'
    END IF

  END FUNCTION win_pressure_free

  FUNCTION win_norm(k,rmax,rv,rs,irho)

    !Calculates the normalised spherical Fourier Transform of the density profile
    !Note that this means win_norm(k->0)=1
    !and that win must be between 0 and 1
    !USE cosdef
    IMPLICIT NONE
    REAL*8 :: win_norm
    REAL*8, INTENT(IN) :: k, rmax, rv, rs
    INTEGER, INTENT(IN) :: irho
    REAL*8 :: c, r

    IF(k==0.) THEN

       !If called for the zero mode (e.g. for the normalisation)
       win_norm=1.

    ELSE

       IF(irho==2) THEN
          !Analytic for top hat
          win_norm=wk_tophat(k*rmax)
       ELSE IF(irho==5) THEN
          !Analytic for NFW
          win_norm=winnfw(k,rmax,rs)
       ELSE IF(irho==10) THEN
          !For ejected gas profile
          win_norm=exp(-1.5*(k*rs)**2.)
       ELSE
          !Numerical integral over the density profile (slower)
          win_norm=winint(k,rmax,rv,rs,irho)/normalisation(rmax,rv,rs,irho)
       END IF

    END IF

  END FUNCTION win_norm

  FUNCTION rhor2at0(rmax,rv,rs,irho)

    !This is the value of r^2/rho(r) at r=0. For most profiles this is zero

    IMPLICIT NONE
    REAL*8 :: rhor2at0
    REAL*8, INTENT(IN) :: rmax, rv, rs
    INTEGER, INTENT(IN) :: irho

    IF(irho==1 .OR. irho==9) THEN
       !1 - Isothermal
       !9 - Stellar profile from Schneider (2015)
       rhor2at0=1.d0
    ELSE
       rhor2at0=0.d0
    END IF

  END FUNCTION rhor2at0

  FUNCTION rho(r,rmax,rv,rs,irho)

    !This is an UNNORMALISED halo profile of some sort (density, temperature, ...)

    !Types of profile
    !================
    ! 1 - Isothermal
    ! 2 - Top hat
    ! 3 - Moore (1999)
    ! 4 - NFW (1997)
    ! 5 - Analytic NFW
    ! 6 - Beta model with beta=2/3
    ! 7 - Star profile
    ! 8 - Komatsu & Seljak (2002) according to Schneider (2015)
    ! 9 - Stellar profile from Schneider (2015)
    !10 - Ejected gas profile (Schneider 2015)
    !11 - KS density
    !12 - KS temperature
    !13 - KS pressure
    !14 - Universal pressure profile
    !15 - Isothermal beta model, beta=0.86 (Ma et al. 2015)

    IMPLICIT NONE
    REAL*8 :: rho
    REAL*8, INTENT(IN) :: r, rmax, rv, rs
    INTEGER, INTENT(IN) :: irho
    REAL*8 :: y, ct, t, c, gamma, rt, A
    REAL*8 :: P0, c500, alpha, beta, r500
    REAL*8 :: f1, f2

    IF(r>rmax) THEN

       !The profile is considered to be hard cut at rmax
       rho=0.d0

    ELSE

       IF(irho==1) THEN
          !Isothermal
          rho=1.d0/(r**2.)
       ELSE IF(irho==2) THEN
          !Top hat
          rho=1.d0
       ELSE IF(irho==3) THEN
          !Moore (1999)
          y=r/rs
          rho=1.d0/((y**1.5)*(1.+y**1.5))
       ELSE IF(irho==4 .OR. irho==5) THEN
          !NFW (1997)
          y=r/rs
          rho=1.d0/(y*(1.+y)**2.)
       ELSE IF(irho==6) THEN
          !Isothermal beta model (X-ray gas; SZ profiles; beta=2/3 fixed)
          !AKA 'cored isothermal profile'
          y=r/rs
          beta=2./3.
          rho=1.d0/((1.+y**2.)**(3.*beta/2.))
       ELSE IF(irho==7) THEN
          !Stellar profile from Fedeli (2014a)
          y=r/rs
          rho=(1./y)*exp(-y)
       ELSE IF(irho==8) THEN
          !Komatsu & Seljak (2001) profile with NFW transition radius
          !VERY slow to calculate the W(k) for some reason
          !Also creates a weird upturn in P(k) that I do not think can be correct
          t=sqrt(5.d0)
          rt=rv/t
          y=r/rs
          c=rs/rv
          ct=c/t
          gamma=(1.+3.*ct)*log(1.+ct)/((1.+ct)*log(1.+ct)-ct)
          IF(r<=rt) THEN
             !Komatsu Seljak in the interior
             rho=(log(1.+y)/y)**gamma
          ELSE
             !NFW in the outskirts
             A=((rt/rs)*(1.+rt/rs)**2.)*(log(1.+rt/rs)/(rt/rs))**gamma
             rho=A/(y*(1.+y)**2.)
          END IF
       ELSE IF(irho==9) THEN
          !Stellar profile from Schneider (2015) via Mohammed (2014)    
          rho=exp(-(r/(2.*rs))**2.)/r**2.
          !Converting to y caused the integration to crash for some reason !?!
          !y=r/rs
          !rho=exp(-(y/2.)**2.)/y**2.
       ELSE IF(irho==10) THEN
          !Ejected gas profile from Schneider (2015)
          rho=exp(-0.5*(r/rs)**2.)
       ELSE IF(irho==11 .OR. irho==12 .OR. irho==13) THEN
          !Komatsu & Seljak (2001) profile
          gamma=1.18 !Recommended by Rabold (2017)
          y=r/rs
          rho=(log(1.+y)/y)
          IF(irho==11) THEN
             !KS density profile
             rho=rho**(1./(gamma-1.))
          ELSE IF(irho==12) THEN
             !KS temperature profile
             rho=rho
          ELSE IF(irho==13) THEN
             !KS pressure profile
             rho=rho**(gamma/(gamma-1.))
          END IF
       ELSE IF(irho==14) THEN

          !UPP is in terms of r500c, not rv
          r500=rv

          !UPP parameters from Planck V (2013) also in Ma et al. (2015)
          P0=6.41
          c500=1.81
          alpha=1.33
          beta=4.13
          gamma=0.31

          !UPP funny-P(x), equation 4.2 in Ma et al. (2015)
          f1=(c500*r/r500)**gamma
          f2=(1.+(c500*r/r500)**alpha)**((beta-gamma)/alpha)
          rho=P0/(f1*f2)

       ELSE IF(irho==15) THEN
          !Isothermal beta model
          !Parameter from Ma et al. (2015)
          beta=0.86
          rho=(1.+(r/rs)**2.)**(-3.*beta/2.)
       ELSE
          STOP 'RHO: Error, irho not specified correctly'
       END IF

    END IF

  END FUNCTION rho

  FUNCTION winint(k,rmax,rv,rs,irho)

    !Calculates W(k,M)
    IMPLICIT NONE
    REAL*8 :: winint
    REAL*8, INTENT(IN) :: k, rmax, rv, rs
    INTEGER, INTENT(IN) :: irho
    !REAL*8, PARAMETER :: acc=1d-4
    INTEGER, PARAMETER :: imeth=3
    INTEGER, PARAMETER :: iorder=3

    !imeth = 1 - normal integration
    !imeth = 2 - bumps with normal integration
    !imeth = 3 - storage integration
    !imeth = 4 - bumps with storage integration
    !imeth = 5 - linear bumps
    !imeth = 6 - cubic bumps
    !imeth = 7 - Hybrid with storage and cubic bumps

    IF(imeth==1) THEN
       winint=winint_normal(0.d0,rmax,k,rmax,rv,rs,irho,iorder,acc)
    ELSE IF(imeth==2 .OR. imeth==4 .OR. imeth==5 .OR. imeth==6 .OR. imeth==7) THEN
       winint=winint_bumps(k,rmax,rv,rs,irho,iorder,acc,imeth)
    ELSE IF(imeth==3) THEN
       winint=winint_store(0.d0,rmax,k,rmax,rv,rs,irho,iorder,acc)
    ELSE
       STOP 'WININT: Error, imeth not specified correctly'
    END IF

  END FUNCTION winint

  FUNCTION winint_normal(a,b,k,rmax,rv,rs,irho,iorder,acc)

    !Integration routine using 'normal' method to calculate the normalised halo FT
    IMPLICIT NONE
    REAL*8 :: winint_normal
    REAL*8, INTENT(IN) :: k, rmax, rv, rs
    REAL*8, INTENT(IN) :: a, b
    INTEGER, INTENT(IN) :: irho
    INTEGER, INTENT(IN) :: iorder
    REAL*8, INTENT(IN) :: acc
    REAL*8 :: sum
    REAL*8 :: r, dr, winold, weight
    INTEGER :: n, i, j
    INTEGER, PARAMETER :: jmin=5
    INTEGER, PARAMETER :: jmax=30
    INTEGER, PARAMETER :: ninit=2

    !Integrates to required accuracy!
    DO j=1,jmax

       !Increase the number of integration points each go until convergence
       n=ninit*(2**(j-1))

       !Set the integration sum variable to zero
       sum=0.d0

       DO i=1,n

          !Get the weights
          IF(iorder==1) THEN
             !Composite trapezium weights
             IF(i==1 .OR. i==n) THEN
                weight=0.5d0
             ELSE
                weight=1.d0
             END IF
          ELSE IF(iorder==2) THEN
             !Composite extended formula weights
             IF(i==1 .OR. i==n) THEN
                weight=0.416666666666d0
             ELSE IF(i==2 .OR. i==n-1) THEN
                weight=1.083333333333d0
             ELSE
                weight=1.d0
             END IF
          ELSE IF(iorder==3) THEN
             !Composite Simpson weights
             IF(i==1 .OR. i==n) THEN
                weight=0.375d0
             ELSE IF(i==2 .OR. i==n-1) THEN
                weight=1.166666666666
             ELSE IF(i==3 .OR. i==n-2) THEN
                weight=0.958333333333
             ELSE
                weight=1.d0
             END IF
          ELSE
             STOP 'WININT_NORMAL: Error, order specified incorrectly'
          END IF

          !Now get r and do the function evaluations
          r=a+(b-a)*DBLE(i-1)/DBLE(n-1)
          sum=sum+weight*winint_integrand(r,k,rmax,rv,rs,irho)*sinc(r*k)

       END DO

       !The dr are all equally spaced
       dr=(b-a)/DBLE(n-1)

       winint_normal=sum*dr

       IF((j>jmin) .AND. (ABS(-1.d0+winint_normal/winold)<acc)) THEN
          EXIT
       ELSE
          winold=winint_normal
       END IF

    END DO

  END FUNCTION winint_normal

  FUNCTION winint_store(a,b,k,rmax,rv,rs,irho,iorder,acc)

    !Integrates between a and b until desired accuracy is reached
    !Stores information to reduce function calls
    IMPLICIT NONE
    REAL*8 :: winint_store
    REAL*8, INTENT(IN) :: k, rmax, rv, rs, acc
    REAL*8, INTENT(IN) :: a, b
    INTEGER, INTENT(IN) :: iorder, irho
    INTEGER :: i, j, n
    REAL*8 :: x, dx
    REAL*8 :: f1, f2, fx
    REAL*8 :: sum_n, sum_2n, sum_new, sum_old
    INTEGER, PARAMETER :: jmin=5
    INTEGER, PARAMETER :: jmax=30

    IF(a==b) THEN

       !Fix the answer to zero if the integration limits are identical
       winint_store=0.d0

    ELSE

       !Reset the sum variables for the integration
       sum_2n=0.d0

       DO j=1,jmax

          !Note, you need this to be 1+2**n for some integer n
          !j=1 n=2; j=2 n=3; j=3 n=5; j=4 n=9; ...'
          n=1+2**(j-1)

          !Calculate the dx interval for this value of 'n'
          dx=(b-a)/DBLE(n-1)

          IF(j==1) THEN

             !The first go is just the trapezium of the end points
             f1=winint_integrand(a,k,rmax,rv,rs,irho)*sinc(a*k)
             f2=winint_integrand(b,k,rmax,rv,rs,irho)*sinc(b*k)
             sum_2n=0.5d0*(f1+f2)*dx

          ELSE

             !Loop over only new even points to add these to the integral
             DO i=2,n,2
                x=a+(b-a)*DBLE(i-1)/DBLE(n-1)
                fx=winint_integrand(x,k,rmax,rv,rs,irho)
                sum_2n=sum_2n+fx*sinc(x*k)
             END DO

             !Now create the total using the old and new parts
             sum_2n=sum_n/2.d0+sum_2n*dx

             !Now calculate the new sum depending on the integration order
             IF(iorder==1) THEN  
                sum_new=sum_2n
             ELSE IF(iorder==3) THEN         
                sum_new=(4.d0*sum_2n-sum_n)/3.d0 !This is Simpson's rule and cancels error
             ELSE
                STOP 'WININT_STORE: Error, iorder specified incorrectly'
             END IF

          END IF

          IF((j>=jmin) .AND. (ABS(-1.d0+sum_new/sum_old)<acc)) THEN
             !jmin avoids spurious early convergence
             winint_store=sum_new
             !WRITE(*,*) 'WININT_STORE: Nint:', n
             EXIT
          ELSE IF(j==jmax) THEN
             STOP 'WININT_STORE: Integration timed out'
          ELSE
             !Integral has not converged so store old sums and reset sum variables
             sum_old=sum_new
             sum_n=sum_2n
             sum_2n=0.d0
          END IF

       END DO

    END IF

  END FUNCTION winint_store

  FUNCTION winint_integrand(r,k,rmax,rv,rs,irho)

    IMPLICIT NONE
    REAL*8 :: winint_integrand
    REAL*8, INTENT(IN) :: r, k, rmax, rv, rs
    INTEGER, INTENT(IN) :: irho

    IF(r==0.d0) THEN
       winint_integrand=4.d0*pi*rhor2at0(rmax,rv,rs,irho)
    ELSE
       winint_integrand=4.d0*pi*(r**2)*rho(r,rmax,rv,rs,irho)
    END IF

  END FUNCTION winint_integrand

  FUNCTION winint_bumps(k,rmax,rv,rs,irho,iorder,acc,imeth)

    !Integration routine to calculate the normalised halo FT
    IMPLICIT NONE
    REAL*8 :: winint_bumps
    REAL*8, INTENT(IN) :: k, rmax, rv, rs
    INTEGER, INTENT(IN) :: irho
    INTEGER, INTENT(IN) :: iorder, imeth
    REAL*8, INTENT(IN) :: acc
    REAL*8 :: sum, w, rn, dr
    REAL*8 :: r1, r2
    REAL*8 :: a3, a2, a1, a0
    REAL*8 :: x1, x2, x3, x4
    REAL*8 :: y1, y2, y3, y4
    INTEGER :: i, n
    INTEGER, PARAMETER :: nlim=50

    !Calculate the number of nodes of sinc(k*rmax) for 0<=r<=rmax
    n=FLOOR(k*rmax/pi)

    !Set the sum variable to zero
    sum=0.d0

    !Integrate over each chunk between nodes separately
    DO i=0,n

       !Set the lower integration limit
       IF(k==0.d0) THEN
          !Special case when k=0 to avoid division by zero
          r1=0.d0
       ELSE
          r1=i*pi/k
       END IF

       !Set the upper integration limit
       IF(i==n) THEN
          !Special case when on last section because end is rmax, not a node!
          r2=rmax
       ELSE
          r2=(i+1)*pi/k
       END IF

       !Now do the integration along a section
       IF(k==0.d0 .OR. imeth==2) THEN
          w=winint_normal(r1,r2,k,rmax,rv,rs,irho,iorder,acc)
       ELSE IF(imeth==4 .OR. (imeth==7 .AND. n<=nlim)) THEN
          w=winint_store(r1,r2,k,rmax,rv,rs,irho,iorder,acc)
       ELSE IF(imeth==5 .OR. imeth==6 .OR. imeth==7) THEN
          IF(i==0 .OR. i==n) THEN
             !First piece done 'normally' because otherwise /0 occurs in cubic
             !Last piece will not generally be over one full oscillation
             w=winint_store(r1,r2,k,rmax,rv,rs,irho,iorder,acc)
          ELSE
             IF(imeth==5) THEN
                rn=pi*(2*i+1)/(2.*k)
                w=(2.d0/k**2)*winint_integrand(rn,k,rmax,rv,rs,irho)*((-1.d0)**i)/rn
             ELSE IF(imeth==6 .OR. (imeth==7 .AND. n>nlim)) THEN
                x1=r1
                x2=r1+1.d0*(r2-r1)/3.d0
                x3=r1+2.d0*(r2-r1)/3.d0
                x4=r2
                y1=winint_integrand(x1,k,rmax,rv,rs,irho)/x1
                y2=winint_integrand(x2,k,rmax,rv,rs,irho)/x2
                y3=winint_integrand(x3,k,rmax,rv,rs,irho)/x3
                y4=winint_integrand(x4,k,rmax,rv,rs,irho)/x4
                CALL fit_cubic(a3,a2,a1,a0,x1,y1,x2,y2,x3,y3,x4,y4)
                w=-6.d0*a3*(r2+r1)-4.d0*a2
                w=w+(k**2)*(a3*(r2**3+r1**3)+a2*(r2**2+r1**2)+a1*(r2+r1)+2.d0*a0)
                w=w*((-1)**i)/(k**4)
             END IF
          END IF
       ELSE
          STOP 'BUMPS: Error, imeth specified incorrectly'
       END IF

       sum=sum+w

    END DO

    winint_bumps=sum

  END FUNCTION winint_bumps

  FUNCTION winnfw(k,rv,rs)

    !The analytic normalised (W(k=0)=1) Fourier Transform of the NFW profile
    IMPLICIT NONE
    REAL*8 :: winnfw
    REAL*8, INTENT(IN) :: k, rv, rs
    REAL*8 :: c, ks
    REAL*8 :: si1, si2, ci1, ci2
    REAL*8 :: p1, p2, p3

    c=rv/rs
    ks=k*rv/c

    si1=si(ks)
    si2=si((1.+c)*ks)
    ci1=ci(ks)
    ci2=ci((1.+c)*ks)

    p1=cos(ks)*(ci2-ci1)
    p2=sin(ks)*(si2-si1)
    p3=sin(ks*c)/(ks*(1.+c))

    winnfw=p1+p2-p3
    winnfw=4.*pi*winnfw*(rs**3.)/normalisation(rv,rv,rs,4)

  END FUNCTION winnfw

  FUNCTION normalisation(rmax,rv,rs,irho)

    !This calculates the normalisation of a halo of concentration c
    !See your notes for details of what this means!

    !Factors of 4\pi have been *RESTORED*

    ! 1 - Isothermal (M = 4pi*rv)
    ! 2 - Top hat (M = (4pi/3)*rv^3)
    ! 3 - Moore (M = (8pi/3)*rv^3*ln(1+c^1.5)/c^3)
    ! 4,5 - NFW (M = 4pi*rs^3*[ln(1+c)-c/(1+c)])
    ! 6 - Beta model with beta=2/3 (M = 4*pi*rs^3*(rv/rs-atan(rv/rs)))
    ! 7 - Stellar profile from Fedeli (2014b)
    ! 8 - Komatsu & Seljak gas profile
    ! 9 - Stellar profile (Schneider (2015)
    !10 - Ejected gas profile (Schneider 2015)
    !11, 12, 13 - Various KS profiles (rho, temp, pressure)
    !14 - UPP

    IMPLICIT NONE
    REAL*8 :: normalisation
    REAL*8, INTENT(IN) :: rmax, rv, rs
    INTEGER, INTENT(IN) :: irho
    REAL*8 :: cmax

    IF(irho==1) THEN
       !Isothermal
       normalisation=4.*pi*rmax
    ELSE IF(irho==2) THEN
       !Top hat
       normalisation=4.*pi*(rmax**3)/3.
    ELSE IF(irho==3) THEN
       !Moore
       cmax=rmax/rs
       normalisation=(2./3.)*4.*pi*(rs**3)*log(1.+cmax**1.5)
    ELSE IF(irho==4 .OR. irho==5) THEN
       !NFW
       cmax=rmax/rs
       normalisation=4.*pi*(rs**3)*(log(1.+cmax)-cmax/(1.+cmax))
    ELSE IF(irho==6) THEN
       !Beta model with beta=2/3
       normalisation=4.*pi*(rs**3)*(rmax/rs-atan(rmax/rs))
    ELSE IF(irho==9) THEN
       !Stellar profile from Schneider (2015)
       !Assumed to go on to r -> infinity
       normalisation=4.*pi*rs*sqrt(pi)
    ELSE IF(irho==10) THEN
       !Ejected gas profile from Schneider (2015)
       !Assumed to go on to r -> infinity
       normalisation=4.*pi*sqrt(pi/2.)*rs**3
    ELSE
       !Otherwise need to do the integral numerically
       normalisation=winint(0.d0,rmax,rv,rs,irho)
    END IF

  END FUNCTION normalisation

  FUNCTION bnu(nu)

    !Bias function selection!
    IMPLICIT NONE
    REAL*8, INTENT(IN) :: nu
    REAL*8 :: bnu

    IF(imf==1) THEN
       bnu=bps(nu)
    ELSE IF(imf==2) THEN
       bnu=bst(nu)
    ELSE
       STOP 'BNU: Error, imf not specified correctly'
    END IF

  END FUNCTION bnu

  FUNCTION bps(nu)

    !Press Scheter bias
    IMPLICIT NONE
    REAL*8 :: bps
    REAL*8, INTENT(IN) :: nu
    REAL*8 :: dc

    dc=1.686

    bps=1.+(nu**2-1.)/dc

  END FUNCTION bps

  FUNCTION bst(nu)

    !Sheth Tormen bias
    IMPLICIT NONE
    REAL*8 :: bst
    REAL*8, INTENT(IN) :: nu
    REAL*8 :: p, q, dc

    p=0.3
    q=0.707
    dc=1.686

    bst=1.+(q*(nu**2)-1.+2.*p/(1.+(q*nu**2)**p))/dc

  END FUNCTION bst

  FUNCTION b2nu(nu)

    !Bias function selection!
    IMPLICIT NONE
    REAL*8, INTENT(IN) :: nu
    REAL*8 :: b2nu

    IF(imf==1) THEN
       b2nu=b2ps(nu)
    ELSE IF(imf==2) THEN
       b2nu=b2st(nu)
    ELSE
       STOP 'B2NU: Error, imf not specified correctly'
    END IF

  END FUNCTION b2nu

  FUNCTION b2ps(nu)

    !Press & Schechter second order bias
    IMPLICIT NONE
    REAL*8 :: b2ps
    REAL*8, INTENT(IN) :: nu
    REAL*8 :: p, q, dc
    REAL*8 :: eps1, eps2, E1, E2, a2

    STOP 'B2PS: Check this very carefully'
    !I just took the ST form and set p=0 and q=1

    a2=-17./21.
    p=0.0
    q=1.0
    dc=1.686

    eps1=(q*nu**2-1.)/dc
    eps2=(q*nu**2)*(q*nu**2-3.)/dc**2
    E1=(2.*p)/(dc*(1.+(q*nu**2)**p))
    E2=((1.+2.*p)/dc+2.*eps1)*E1

    b2ps=2.*(1.+a2)*(eps1+E1)+eps2+E2

  END FUNCTION b2ps

  FUNCTION b2st(nu)

    !Sheth & Tormen second-order bias
    IMPLICIT NONE
    REAL*8 :: b2st
    REAL*8, INTENT(IN) :: nu
    REAL*8 :: p, q, dc
    REAL*8 :: eps1, eps2, E1, E2, a2

    !Notation follows from Cooray & Sheth (2002) pp 25-26

    a2=-17./21.
    p=0.3
    q=0.707
    dc=1.686

    eps1=(q*nu**2-1.)/dc
    eps2=(q*nu**2)*(q*nu**2-3.)/dc**2
    E1=(2.*p)/(dc*(1.+(q*nu**2)**p))
    E2=((1.+2.*p)/dc+2.*eps1)*E1

    b2st=2.*(1.+a2)*(eps1+E1)+eps2+E2

  END FUNCTION b2st

  FUNCTION gnu(nu)

    !Mass function
    IMPLICIT NONE
    REAL*8 :: gnu
    REAL*8, INTENT(IN) :: nu

    IF(imf==1) THEN
       gnu=gps(nu)
    ELSE IF(imf==2) THEN
       gnu=gst(nu)
    ELSE
       STOP 'GNU: Error, imf specified incorrectly'
    END IF

  END FUNCTION gnu

  FUNCTION gps(nu)

    !Press Scheter mass function!
    IMPLICIT NONE
    REAL*8 :: gps
    REAL*8, INTENT(IN) :: nu
    REAL*8, PARAMETER :: A=0.7978846

    gps=A*exp(-(nu**2)/2.)

  END FUNCTION gps

  FUNCTION gst(nu)

    !Sheth Tormen mass function!
    !Note I use nu=dc/sigma(M) and this Sheth & Tormen (1999) use nu=(dc/sigma)^2
    !This accounts for some small differences
    IMPLICIT NONE
    REAL*8 :: gst
    REAL*8, INTENT(IN) :: nu
    REAL*8, PARAMETER :: p=0.3d0
    REAL*8, PARAMETER :: q=0.707d0
    REAL*8, PARAMETER :: A=0.21616

    !p=0.3d0
    !q=0.707d0
    !A=0.21616

    gst=A*(1.+((q*nu*nu)**(-p)))*exp(-q*nu*nu/2.)

  END FUNCTION gst

  FUNCTION gnubnu(nu)

    !g(nu) times b(nu)
    IMPLICIT NONE
    REAL*8 :: gnubnu
    REAL*8, INTENT(IN) :: nu

    gnubnu=gnu(nu)*bnu(nu)
    
  END FUNCTION GNUBNU

  FUNCTION hubble2(z,cosm)

    !Calculates Hubble^2 in units such that H^2(z=0)=1.
    !USE cosdef
    IMPLICIT NONE
    REAL*8 :: hubble2
    REAL*8, INTENT(IN) :: z
    REAL*8 :: om_m, om_v, a
    TYPE(cosmology), INTENT(IN) :: cosm

    om_m=cosm%om_m
    om_v=cosm%om_v
    a=1./(1.+z)
    hubble2=(om_m*(1.+z)**3)+om_v*X_de(a,cosm)+((1.-om_m-om_v)*(1.+z)**2)

  END FUNCTION hubble2

  FUNCTION omega_m(z,cosm)

    !This calculates Omega_m variations with z!
    !USE cosdef
    IMPLICIT NONE
    REAL*8 :: omega_m
    REAL*8, INTENT(IN) :: z
    REAL*8 :: om_m
    TYPE(cosmology), INTENT(IN) :: cosm

    om_m=cosm%om_m
    omega_m=(om_m*(1.+z)**3)/hubble2(z,cosm)

  END FUNCTION omega_m

  FUNCTION grow(z,cosm)

    !Scale-independent growth function | g(z=0)=1
    !USE cosdef
    IMPLICIT NONE
    REAL*8 :: grow
    REAL*8, INTENT(IN) :: z
    REAL*8 :: a
    TYPE(cosmology), INTENT(IN) :: cosm

    IF(z==0.) THEN
       grow=1.
    ELSE
       a=1./(1.+z)
       grow=find(a,cosm%a_growth,cosm%growth,cosm%ng,3,3,2)
    END IF

  END FUNCTION grow

  FUNCTION growint(a,cosm)

    !Integrates between a and b until desired accuracy is reached
    !Stores information to reduce function calls
    IMPLICIT NONE
    REAL*8 :: growint
    REAL*8, INTENT(IN) :: a
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8 :: b
    INTEGER :: i, j
    INTEGER :: n
    REAL*8 :: x, dx
    REAL*8 :: f1, f2, fx
    REAL*8 :: sum_n, sum_2n, sum_new, sum_old
    INTEGER, PARAMETER :: jmin=5
    INTEGER, PARAMETER :: jmax=30
    !REAL*8, PARAMETER :: acc=1d-4
    INTEGER, PARAMETER :: iorder=3   

    !Integration range for integration parameter
    !Note a -> 1
    b=1.d0

    IF(a==b) THEN

       !Fix the answer to zero if the integration limits are identical
       growint=exp(0.d0)

    ELSE

       !Reset the sum variable for the integration
       sum_2n=0.d0

       DO j=1,jmax

          !Note, you need this to be 1+2**n for some integer n
          !j=1 n=2; j=2 n=3; j=3 n=5; j=4 n=9; ...'
          n=1+2**(j-1)

          !Calculate the dx interval for this value of 'n'
          dx=(b-a)/REAL(n-1)

          IF(j==1) THEN

             !The first go is just the trapezium of the end points
             f1=growint_integrand(a,cosm)
             f2=growint_integrand(b,cosm)
             sum_2n=0.5d0*(f1+f2)*dx

          ELSE

             !Loop over only new even points to add these to the integral
             DO i=2,n,2
                x=a+(b-a)*REAL(i-1)/REAL(n-1)
                fx=growint_integrand(x,cosm)
                sum_2n=sum_2n+fx
             END DO

             !Now create the total using the old and new parts
             sum_2n=sum_n/2.d0+sum_2n*dx

             !Now calculate the new sum depending on the integration order
             IF(iorder==1) THEN  
                sum_new=sum_2n
             ELSE IF(iorder==3) THEN         
                sum_new=(4.d0*sum_2n-sum_n)/3.d0 !This is Simpson's rule and cancels error
             ELSE
                STOP 'GROWINT: Error, iorder specified incorrectly'
             END IF

          END IF

          IF((j>=jmin) .AND. (ABS(-1.d0+sum_new/sum_old)<acc)) THEN
             !jmin avoids spurious early convergence
             growint=exp(sum_new)
             EXIT
          ELSE IF(j==jmax) THEN
             STOP 'GROWINT: Integration timed out'
          ELSE
             !Integral has not converged so store old sums and reset sum variables
             sum_old=sum_new
             sum_n=sum_2n
             sum_2n=0.d0
          END IF

       END DO

    END IF

  END FUNCTION growint

  FUNCTION growint_integrand(a,cosm)

    !Integrand for the approximate growth integral
    IMPLICIT NONE
    REAL*8 :: growint_integrand
    REAL*8, INTENT(IN) :: a
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8 :: gam

    IF(cosm%w<-1.) THEN
       gam=0.55+0.02*(1.+cosm%w)
    ELSE IF(cosm%w>-1) THEN
       gam=0.55+0.05*(1.+cosm%w)
    ELSE
       gam=0.55
    END IF

    !Note the minus sign here
    growint_integrand=-(Omega_m(-1.+1./a,cosm)**gam)/a

  END FUNCTION growint_integrand

  FUNCTION dispint(R,z,cosm)

    !Integrates between a and b until desired accuracy is reached
    !Stores information to reduce function calls
    IMPLICIT NONE
    REAL*8 :: dispint
    REAL*8, INTENT(IN) :: z, R
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8 :: a, b
    INTEGER :: i, j
    INTEGER :: n
    REAL*8 :: x, dx
    REAL*8 :: f1, f2, fx
    REAL*8 :: sum_n, sum_2n, sum_new, sum_old
    INTEGER, PARAMETER :: jmin=5
    INTEGER, PARAMETER :: jmax=30
    !REAL*8, PARAMETER :: acc=1d-4
    INTEGER, PARAMETER :: iorder=3   

    !Integration range for integration parameter
    !Note 0 -> infinity in k has changed to 0 -> 1 in x
    a=0.d0
    b=1.d0

    IF(a==b) THEN

       !Fix the answer to zero if the integration limits are identical
       dispint=0.

    ELSE

       !Reset the sum variable for the integration
       sum_2n=0.d0

       DO j=1,jmax

          !Note, you need this to be 1+2**n for some integer n
          !j=1 n=2; j=2 n=3; j=3 n=5; j=4 n=9; ...'
          n=1+2**(j-1)

          !Calculate the dx interval for this value of 'n'
          dx=(b-a)/REAL(n-1)

          IF(j==1) THEN

             !The first go is just the trapezium of the end points
             f1=dispint_integrand(a,R,z,cosm)
             f2=dispint_integrand(b,R,z,cosm)
             sum_2n=0.5d0*(f1+f2)*dx

          ELSE

             !Loop over only new even points to add these to the integral
             DO i=2,n,2
                x=a+(b-a)*REAL(i-1)/REAL(n-1)
                fx=dispint_integrand(x,R,z,cosm)
                sum_2n=sum_2n+fx
             END DO

             !Now create the total using the old and new parts
             sum_2n=sum_n/2.d0+sum_2n*dx

             !Now calculate the new sum depending on the integration order
             IF(iorder==1) THEN  
                sum_new=sum_2n
             ELSE IF(iorder==3) THEN         
                sum_new=(4.d0*sum_2n-sum_n)/3.d0 !This is Simpson's rule and cancels error
             ELSE
                STOP 'DISPINT: Error, iorder specified incorrectly'
             END IF

          END IF

          IF((j>=jmin) .AND. (ABS(-1.d0+sum_new/sum_old)<acc)) THEN
             !jmin avoids spurious early convergence
             dispint=REAL(sum_new)
             EXIT
          ELSE IF(j==jmax) THEN
             STOP 'DISPINT: Integration timed out'
          ELSE
             !Integral has not converged so store old sums and reset sum variables
             sum_old=sum_new
             sum_n=sum_2n
             sum_2n=0.d0
          END IF

       END DO

    END IF

  END FUNCTION dispint

  FUNCTION dispint_integrand(theta,R,z,cosm)

    !This is the integrand for the velocity dispersion integral
    IMPLICIT NONE
    REAL*8 :: dispint_integrand
    REAL*8, INTENT(IN) :: theta, z, R
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8 :: k
    REAL*8, PARAMETER :: alpha=1.65d0 !Speeds up integral for large 'R'
    REAL*8, PARAMETER :: Rsplit=10.d0 !Value to impliment speed up

    !Note that I have not included the speed up alpha and Rsplit
    !The choice of alpha=1.65 seemed to work well for R=100.
    !Rsplit=10 is thoughlessly chosen (only because 100.>10.)
    !Including this seems to make things slower (faster integration but slower IF statements?)

    IF(theta==0.d0 .OR. theta==1.d0) THEN
       dispint_integrand=0.d0
    ELSE
       !IF(r>Rsplit) THEN
       !   k=(-1.d0+1.d0/theta)/r**alpha
       !ELSE
       k=(-1.d0+1.d0/theta)
       !END IF
       dispint_integrand=(p_lin(k,z,cosm)/k**2)*(wk_tophat(k*r)**2)/(theta*(1.d0-theta))
    END IF

  END FUNCTION dispint_integrand

  FUNCTION Si(x)

    IMPLICIT NONE
    REAL*8 :: Si
    REAL*8, INTENT(IN) :: x
    REAL*8 :: x2, y, f, g, si8
    REAL*8, PARAMETER :: pi8=3.1415926535897932384626433d0

    !Expansions for high and low x thieved from Wikipedia, two different expansions for above and below 4.

    IF(ABS(x)<=4.) THEN

       x2=x*x

       si8 = x*(1.d0+x2*(-4.54393409816329991d-2+x2*(1.15457225751016682d-3&
            +x2*(-1.41018536821330254d-5+x2*(9.43280809438713025d-8+x2*(-3.53201978997168357d-10&
            +x2*(7.08240282274875911d-13+x2*(-6.05338212010422477d-16))))))))/ &
            (1.+x2*(1.01162145739225565d-2 +x2*(4.99175116169755106d-5+&
            x2*(1.55654986308745614d-7+x2*(3.28067571055789734d-10+x2*(4.5049097575386581d-13&
            +x2*(3.21107051193712168d-16)))))))

       si=real(si8)

    ELSE IF(ABS(x)>4.) THEN

       y=1.d0/(x*x)

       f = (1.d0 + y*(7.44437068161936700618d2 + y*(1.96396372895146869801d5 +&
            y*(2.37750310125431834034d7 +y*(1.43073403821274636888d9 + y*(4.33736238870432522765d10 &
            + y*(6.40533830574022022911d11 + y*(4.20968180571076940208d12 + &
            y*(1.00795182980368574617d13 + y*(4.94816688199951963482d12 +&
            y*(-4.94701168645415959931d11)))))))))))/ (x*(1. +y*(7.46437068161927678031d2 +&
            y*(1.97865247031583951450d5 +y*(2.41535670165126845144d7 + &
            y*(1.47478952192985464958d9 + y*(4.58595115847765779830d10 +&
            y*(7.08501308149515401563d11 + y*(5.06084464593475076774d12 + &
            y*(1.43468549171581016479d13 + y*(1.11535493509914254097d13)))))))))))


       g = y*(1.d0 + y*(8.1359520115168615d2 + y*(2.35239181626478200d5 + &
            y*(3.12557570795778731d7 + y*(2.06297595146763354d9 + y*(6.83052205423625007d10 +&
            y*(1.09049528450362786d12 + y*(7.57664583257834349d12 +y*(1.81004487464664575d13 +&
            y*(6.43291613143049485d12 +y*(-1.36517137670871689d12)))))))))))/&
            (1. + y*(8.19595201151451564d2 +y*(2.40036752835578777d5 + y*(3.26026661647090822d7 &
            + y*(2.23355543278099360d9 + y*(7.87465017341829930d10 + y*(1.39866710696414565d12 &
            + y*(1.17164723371736605d13 + y*(4.01839087307656620d13 +y*(3.99653257887490811d13))))))))))

       si=real(pi8/2.d0-f*cos(x)-g*sin(x))

    ELSE

       STOP 'ERROR: Si, something went wrong'

    END IF

  END FUNCTION Si

  FUNCTION Ci(x)

    IMPLICIT NONE
    REAL*8 :: Ci
    REAL*8, INTENT(IN) :: x
    REAL*8 :: x2, y, f, g, ci8
    REAL*8, PARAMETER :: em_const=0.577215664901532861d0

    !Expansions for high and low x thieved from Wikipedia, two different expansions for above and below 4.

    IF(ABS(x)<=4.) THEN

       x2=x*x

       ci8=em_const+log(x)+x2*(-0.25d0+x2*(7.51851524438898291d-3+x2*(-1.27528342240267686d-4&
            +x2*(1.05297363846239184d-6+x2*(-4.68889508144848019d-9+x2*(1.06480802891189243d-11&
            +x2*(-9.93728488857585407d-15)))))))/ (1.+x2*(1.1592605689110735d-2+&
            x2*(6.72126800814254432d-5+x2*(2.55533277086129636d-7+x2*(6.97071295760958946d-10+&
            x2*(1.38536352772778619d-12+x2*(1.89106054713059759d-15+x2*(1.39759616731376855d-18))))))))

       ci=real(ci8)

    ELSE IF(ABS(x)>4.) THEN

       y=1./(x*x) 

       f = (1.d0 + y*(7.44437068161936700618d2 + y*(1.96396372895146869801d5 + &
            y*(2.37750310125431834034d7 +y*(1.43073403821274636888d9 + y*(4.33736238870432522765d10&
            + y*(6.40533830574022022911d11 + y*(4.20968180571076940208d12 + y*(1.00795182980368574617d13&
            + y*(4.94816688199951963482d12 +y*(-4.94701168645415959931d11)))))))))))/&
            (x*(1. +y*(7.46437068161927678031d2 +y*(1.97865247031583951450d5 +&
            y*(2.41535670165126845144d7 + y*(1.47478952192985464958d9 + &
            y*(4.58595115847765779830d10 +y*(7.08501308149515401563d11 + y*(5.06084464593475076774d12 &
            + y*(1.43468549171581016479d13 + y*(1.11535493509914254097d13)))))))))))   

       g = y*(1.d0 + y*(8.1359520115168615d2 + y*(2.35239181626478200d5 + y*(3.12557570795778731d7&
            + y*(2.06297595146763354d9 + y*(6.83052205423625007d10 +&
            y*(1.09049528450362786d12 + y*(7.57664583257834349d12 +&
            y*(1.81004487464664575d13 + y*(6.43291613143049485d12 +y*(-1.36517137670871689d12)))))))))))&
            / (1. + y*(8.19595201151451564d2 +y*(2.40036752835578777d5 +&
            y*(3.26026661647090822d7 + y*(2.23355543278099360d9 + y*(7.87465017341829930d10 &
            + y*(1.39866710696414565d12 + y*(1.17164723371736605d13 + y*(4.01839087307656620d13 +y*(3.99653257887490811d13))))))))))

       ci=real(f*sin(x)-g*cos(x))

    ELSE

       STOP 'ERROR: Ci, something went wrong'

    END IF

  END FUNCTION Ci

  FUNCTION derivative_table(x,xin,yin,n,iorder,imeth)

    !Given two arrays x and y such that y=y(x) this uses interpolation to calculate the derivative y'(x_i) at position x_i
    IMPLICIT NONE
    REAL*8 :: derivative_table
    INTEGER, INTENT(IN) :: n
    REAL*8, INTENT(IN) :: x, xin(n), yin(n)
    REAL*8, ALLOCATABLE ::  xtab(:), ytab(:)
    REAL*8 :: a, b, c, d
    REAL*8 :: x1, x2, x3, x4
    REAL*8 :: y1, y2, y3, y4
    INTEGER :: i
    INTEGER, INTENT(IN) :: imeth, iorder

    !This version interpolates if the value is off either end of the array!
    !Care should be chosen to insert x, xtab, ytab as log if this might give better!
    !Results from the interpolation!

    !imeth = 1 => find x in xtab by crudely searching
    !imeth = 2 => find x in xtab quickly assuming the table is linearly spaced
    !imeth = 3 => find x in xtab using midpoint splitting (iterations=CEILING(log2(n)))

    !iorder = 1 => linear interpolation
    !iorder = 2 => quadratic interpolation
    !iorder = 3 => cubic interpolation

    ALLOCATE(xtab(n),ytab(n))

    xtab=xin
    ytab=yin

    IF(xtab(1)>xtab(n)) THEN
       !Reverse the arrays in this case
       CALL reverse(xtab,n)
       CALL reverse(ytab,n)
    END IF

    IF(iorder==1) THEN

       IF(n<2) STOP 'DERIVATIVE_TABLE: Not enough points in your table for linear interpolation'

       IF(x<=xtab(2)) THEN

          x2=xtab(2)
          x1=xtab(1)

          y2=ytab(2)
          y1=ytab(1)

       ELSE IF (x>=xtab(n-1)) THEN

          x2=xtab(n)
          x1=xtab(n-1)

          y2=ytab(n)
          y1=ytab(n-1)

       ELSE

          i=table_integer(x,xtab,n,imeth)

          x2=xtab(i+1)
          x1=xtab(i)

          y2=ytab(i+1)
          y1=ytab(i)

       END IF

       CALL fit_line(a,b,x1,y1,x2,y2)
       derivative_table=a

    ELSE IF(iorder==2) THEN

       IF(n<3) STOP 'DERIVATIVE_TABLE: Not enough points in your table'

       IF(x<=xtab(2) .OR. x>=xtab(n-1)) THEN

          IF(x<=xtab(2)) THEN

             x3=xtab(3)
             x2=xtab(2)
             x1=xtab(1)

             y3=ytab(3)
             y2=ytab(2)
             y1=ytab(1)

          ELSE IF (x>=xtab(n-1)) THEN

             x3=xtab(n)
             x2=xtab(n-1)
             x1=xtab(n-2)

             y3=ytab(n)
             y2=ytab(n-1)
             y1=ytab(n-2)

          END IF

          CALL fit_quadratic(a,b,c,x1,y1,x2,y2,x3,y3)

          derivative_table=2.*a*x+b

       ELSE

          i=table_integer(x,xtab,n,imeth)

          x1=xtab(i-1)
          x2=xtab(i)
          x3=xtab(i+1)
          x4=xtab(i+2)

          y1=ytab(i-1)
          y2=ytab(i)
          y3=ytab(i+1)
          y4=ytab(i+2)

          !In this case take the average of two separate quadratic spline values

          derivative_table=0.

          CALL fit_quadratic(a,b,c,x1,y1,x2,y2,x3,y3)
          derivative_table=derivative_table+(2.*a*x+b)/2.

          CALL fit_quadratic(a,b,c,x2,y2,x3,y3,x4,y4)
          derivative_table=derivative_table+(2.*a*x+b)/2.

       END IF

    ELSE IF(iorder==3) THEN

       IF(n<4) STOP 'DERIVATIVE_TABLE: Not enough points in your table'

       IF(x<=xtab(3)) THEN

          x4=xtab(4)
          x3=xtab(3)
          x2=xtab(2)
          x1=xtab(1)

          y4=ytab(4)
          y3=ytab(3)
          y2=ytab(2)
          y1=ytab(1)

       ELSE IF (x>=xtab(n-2)) THEN

          x4=xtab(n)
          x3=xtab(n-1)
          x2=xtab(n-2)
          x1=xtab(n-3)

          y4=ytab(n)
          y3=ytab(n-1)
          y2=ytab(n-2)
          y1=ytab(n-3)

       ELSE

          i=table_integer(x,xtab,n,imeth)

          x1=xtab(i-1)
          x2=xtab(i)
          x3=xtab(i+1)
          x4=xtab(i+2)

          y1=ytab(i-1)
          y2=ytab(i)
          y3=ytab(i+1)
          y4=ytab(i+2)

       END IF

       CALL fit_cubic(a,b,c,d,x1,y1,x2,y2,x3,y3,x4,y4)
       derivative_table=3.*a*(x**2)+2.*b*x+c

    ELSE

       STOP 'DERIVATIVE_TABLE: Error, iorder not specified correctly'

    END IF

  END FUNCTION derivative_table

  FUNCTION find(x,xin,yin,n,iorder,ifind,imeth)

    !Given two arrays x and y this routine interpolates to find the y_i value at position x_i
    IMPLICIT NONE
    REAL*8 :: find
    INTEGER, INTENT(IN) :: n
    REAL*8, INTENT(IN) :: x, xin(n), yin(n)
    REAL*8, ALLOCATABLE ::  xtab(:), ytab(:)
    REAL*8 :: a, b, c, d
    REAL*8 :: x1, x2, x3, x4
    REAL*8 :: y1, y2, y3, y4
    INTEGER :: i
    INTEGER, INTENT(IN) :: imeth, iorder, ifind

    !This version interpolates if the value is off either end of the array!
    !Care should be chosen to insert x, xtab, ytab as log if this might give better!
    !Results from the interpolation!

    !If the value required is off the table edge the interpolation is always linear

    !iorder = 1 => linear interpolation
    !iorder = 2 => quadratic interpolation
    !iorder = 3 => cubic interpolation

    !ifind = 1 => find x in xtab quickly assuming the table is linearly spaced
    !ifind = 2 => find x in xtab by crudely searching from x(1) to x(n)
    !ifind = 3 => find x in xtab using midpoint splitting (iterations=CEILING(log2(n)))

    !imeth = 1 => Cubic polynomial interpolation
    !imeth = 2 => Lagrange polynomial interpolation

    ALLOCATE(xtab(n),ytab(n))

    xtab=xin
    ytab=yin

    IF(xtab(1)>xtab(n)) THEN
       !Reverse the arrays in this case
       CALL reverse(xtab,n)
       CALL reverse(ytab,n)
    END IF

    IF(x<xtab(1)) THEN

       !Do a linear interpolation beyond the table boundary

       x1=xtab(1)
       x2=xtab(2)

       y1=ytab(1)
       y2=ytab(2)

       IF(imeth==1) THEN
          CALL fit_line(a,b,x1,y1,x2,y2)
          find=a*x+b
       ELSE IF(imeth==2) THEN
          find=Lagrange_polynomial(x,1,(/x1,x2/),(/y1,y2/))
       ELSE
          STOP 'FIND: Error, method not specified correctly'
       END IF

    ELSE IF(x>xtab(n)) THEN

       !Do a linear interpolation beyond the table boundary

       x1=xtab(n-1)
       x2=xtab(n)

       y1=ytab(n-1)
       y2=ytab(n)

       IF(imeth==1) THEN
          CALL fit_line(a,b,x1,y1,x2,y2)
          find=a*x+b
       ELSE IF(imeth==2) THEN
          find=Lagrange_polynomial(x,1,(/x1,x2/),(/y1,y2/))
       ELSE
          STOP 'FIND: Error, method not specified correctly'
       END IF

    ELSE IF(iorder==1) THEN

       IF(n<2) STOP 'FIND: Not enough points in your table for linear interpolation'

       IF(x<=xtab(2)) THEN

          x1=xtab(1)
          x2=xtab(2)

          y1=ytab(1)
          y2=ytab(2)

       ELSE IF (x>=xtab(n-1)) THEN

          x1=xtab(n-1)
          x2=xtab(n)

          y1=ytab(n-1)
          y2=ytab(n)

       ELSE

          i=table_integer(x,xtab,n,ifind)

          x1=xtab(i)
          x2=xtab(i+1)

          y1=ytab(i)
          y2=ytab(i+1)

       END IF

       IF(imeth==1) THEN
          CALL fit_line(a,b,x1,y1,x2,y2)
          find=a*x+b
       ELSE IF(imeth==2) THEN
          find=Lagrange_polynomial(x,1,(/x1,x2/),(/y1,y2/))
       ELSE
          STOP 'FIND: Error, method not specified correctly'
       END IF

    ELSE IF(iorder==2) THEN

       IF(n<3) STOP 'FIND: Not enough points in your table'

       IF(x<=xtab(2) .OR. x>=xtab(n-1)) THEN

          IF(x<=xtab(2)) THEN

             x1=xtab(1)
             x2=xtab(2)
             x3=xtab(3)

             y1=ytab(1)
             y2=ytab(2)
             y3=ytab(3)

          ELSE IF (x>=xtab(n-1)) THEN

             x1=xtab(n-2)
             x2=xtab(n-1)
             x3=xtab(n)

             y1=ytab(n-2)
             y2=ytab(n-1)
             y3=ytab(n)

          END IF

          IF(imeth==1) THEN
             CALL fit_quadratic(a,b,c,x1,y1,x2,y2,x3,y3)
             find=a*(x**2)+b*x+c
          ELSE IF(imeth==2) THEN
             find=Lagrange_polynomial(x,2,(/x1,x2,x3/),(/y1,y2,y3/))
          ELSE
             STOP 'FIND: Error, method not specified correctly'
          END IF

       ELSE

          i=table_integer(x,xtab,n,ifind)

          x1=xtab(i-1)
          x2=xtab(i)
          x3=xtab(i+1)
          x4=xtab(i+2)

          y1=ytab(i-1)
          y2=ytab(i)
          y3=ytab(i+1)
          y4=ytab(i+2)

          IF(imeth==1) THEN
             !In this case take the average of two separate quadratic spline values
             CALL fit_quadratic(a,b,c,x1,y1,x2,y2,x3,y3)
             find=(a*(x**2)+b*x+c)/2.
             CALL fit_quadratic(a,b,c,x2,y2,x3,y3,x4,y4)
             find=find+(a*(x**2)+b*x+c)/2.
          ELSE IF(imeth==2) THEN
             !In this case take the average of two quadratic Lagrange polynomials
             find=(Lagrange_polynomial(x,2,(/x1,x2,x3/),(/y1,y2,y3/))+Lagrange_polynomial(x,2,(/x2,x3,x4/),(/y2,y3,y4/)))/2.
          ELSE
             STOP 'FIND: Error, method not specified correctly'
          END IF

       END IF

    ELSE IF(iorder==3) THEN

       IF(n<4) STOP 'FIND: Not enough points in your table'

       IF(x<=xtab(3)) THEN

          x1=xtab(1)
          x2=xtab(2)
          x3=xtab(3)
          x4=xtab(4)        

          y1=ytab(1)
          y2=ytab(2)
          y3=ytab(3)
          y4=ytab(4)

       ELSE IF (x>=xtab(n-2)) THEN

          x1=xtab(n-3)
          x2=xtab(n-2)
          x3=xtab(n-1)
          x4=xtab(n)

          y1=ytab(n-3)
          y2=ytab(n-2)
          y3=ytab(n-1)
          y4=ytab(n)

       ELSE

          i=table_integer(x,xtab,n,ifind)

          x1=xtab(i-1)
          x2=xtab(i)
          x3=xtab(i+1)
          x4=xtab(i+2)

          y1=ytab(i-1)
          y2=ytab(i)
          y3=ytab(i+1)
          y4=ytab(i+2)

       END IF

       IF(imeth==1) THEN
          CALL fit_cubic(a,b,c,d,x1,y1,x2,y2,x3,y3,x4,y4)
          find=a*x**3+b*x**2+c*x+d
       ELSE IF(imeth==2) THEN
          find=Lagrange_polynomial(x,3,(/x1,x2,x3,x4/),(/y1,y2,y3,y4/))
       ELSE
          STOP 'FIND: Error, method not specified correctly'
       END IF

    ELSE

       STOP 'FIND: Error, interpolation order specified incorrectly'

    END IF

  END FUNCTION find

  FUNCTION find2d(x,xin,y,yin,fin,nx,ny,iorder,ifind,imeth)

    !A 2D interpolation routine to find value f(x,y) at position x, y
    IMPLICIT NONE
    REAL*8 :: find2d
    INTEGER, INTENT(IN) :: nx, ny
    REAL*8, INTENT(IN) :: x, xin(nx), y, yin(ny), fin(nx,ny)
    REAL*8, ALLOCATABLE ::  xtab(:), ytab(:), ftab(:,:)
    REAL*8 :: a, b, c, d
    REAL*8 :: x1, x2, x3, x4
    REAL*8 :: y1, y2, y3, y4
    REAL*8 :: f11, f12, f13, f14
    REAL*8 :: f21, f22, f23, f24
    REAL*8 :: f31, f32, f33, f34
    REAL*8 :: f41, f42, f43, f44
    REAL*8 :: f10, f20, f30, f40
    REAL*8 :: f01, f02, f03, f04
    INTEGER :: i1, i2, i3, i4
    INTEGER :: j1, j2, j3, j4
    REAL*8 :: findx, findy
    INTEGER :: i, j
    INTEGER, INTENT(IN) :: iorder, ifind, imeth

    !This version interpolates if the value is off either end of the array!
    !Care should be chosen to insert x, xtab, ytab as log if this might give better!
    !Results from the interpolation!

    !If the value required is off the table edge the interpolation is always linear

    !iorder = 1 => linear interpolation
    !iorder = 2 => quadratic interpolation
    !iorder = 3 => cubic interpolation

    !ifind = 1 => find x in xtab by crudely searching from x(1) to x(n)
    !ifind = 2 => find x in xtab quickly assuming the table is linearly spaced
    !ifind = 3 => find x in xtab using midpoint splitting (iterations=CEILING(log2(n)))

    !imeth = 1 => Uses cubic polynomials for interpolation
    !imeth = 2 => Uses Lagrange polynomials for interpolation

    IF(imeth==2) STOP 'No Lagrange polynomials for you'

    ALLOCATE(xtab(nx),ytab(ny),ftab(nx,ny))

    xtab=xin
    ytab=yin
    ftab=fin

    IF(xtab(1)>xtab(nx)) STOP 'FIND2D: x table in wrong order'
    IF(ytab(1)>ytab(ny)) STOP 'FIND2D: y table in wrong order'

    IF((x<xtab(1) .OR. x>xtab(nx)) .AND. (y>ytab(ny) .OR. y<ytab(1))) THEN
       WRITE(*,*) 'FIND2D: point', x, y
       STOP 'FIND2D: Desired point is outside x AND y table range'
    END IF

    IF(iorder==1) THEN

       IF(nx<2) STOP 'FIND2D: Not enough x points in your table for linear interpolation'
       IF(ny<2) STOP 'FIND2D: Not enough y points in your table for linear interpolation'

       IF(x<=xtab(2)) THEN

          i=1

       ELSE IF (x>=xtab(nx-1)) THEN

          i=nx-1

       ELSE

          i=table_integer(x,xtab,nx,ifind)

       END IF

       i1=i
       i2=i+1

       x1=xtab(i1)
       x2=xtab(i2)      

       IF(y<=ytab(2)) THEN

          j=1

       ELSE IF (y>=ytab(ny-1)) THEN

          j=ny-1

       ELSE

          j=table_integer(y,ytab,ny,ifind)

       END IF

       j1=j
       j2=j+1

       y1=ytab(j1)
       y2=ytab(j2)

       !

       f11=ftab(i1,j1)
       f12=ftab(i1,j2)

       f21=ftab(i2,j1)
       f22=ftab(i2,j2)

       !y direction interpolation

       CALL fit_line(a,b,x1,f11,x2,f21)
       f01=a*x+b

       CALL fit_line(a,b,x1,f12,x2,f22)
       f02=a*x+b

       CALL fit_line(a,b,y1,f01,y2,f02)
       findy=a*y+b

       !x direction interpolation

       CALL fit_line(a,b,y1,f11,y2,f12)
       f10=a*y+b

       CALL fit_line(a,b,y1,f21,y2,f22)
       f20=a*y+b

       CALL fit_line(a,b,x1,f10,x2,f20)
       findx=a*x+b

       !

       !Final result is an average over each direction
       find2d=(findx+findy)/2.

    ELSE IF(iorder==2) THEN

       STOP 'FIND2D: Quadratic 2D interpolation not implemented - also probably pointless'

    ELSE IF(iorder==3) THEN

       IF(x<xtab(1) .OR. x>xtab(nx)) THEN

          IF(nx<2) STOP 'FIND2D: Not enough x points in your table for linear interpolation'
          IF(ny<4) STOP 'FIND2D: Not enough y points in your table for cubic interpolation'

          !x is off the table edge

          IF(x<xtab(1)) THEN

             i1=1
             i2=2

          ELSE

             i1=nx-1
             i2=nx

          END IF

          x1=xtab(i1)
          x2=xtab(i2)

          IF(y<=ytab(4)) THEN

             j=2

          ELSE IF (y>=ytab(ny-3)) THEN

             j=ny-2

          ELSE

             j=table_integer(y,ytab,ny,ifind)

          END IF

          j1=j-1
          j2=j
          j3=j+1
          j4=j+2

          y1=ytab(j1)
          y2=ytab(j2)
          y3=ytab(j3)
          y4=ytab(j4)

          f11=ftab(i1,j1)
          f12=ftab(i1,j2)
          f13=ftab(i1,j3)
          f14=ftab(i1,j4)

          f21=ftab(i2,j1)
          f22=ftab(i2,j2)
          f23=ftab(i2,j3)
          f24=ftab(i2,j4)

          !y interpolation
          CALL fit_cubic(a,b,c,d,y1,f11,y2,f12,y3,f13,y4,f14)
          f10=a*y**3+b*y**2+c*y+d

          CALL fit_cubic(a,b,c,d,y1,f21,y2,f22,y3,f23,y4,f24)
          f20=a*y**3+b*y**2+c*y+d

          !x interpolation
          CALL fit_line(a,b,x1,f10,x2,f20)
          find2d=a*x+b

       ELSE IF(y<ytab(1) .OR. y>ytab(ny)) THEN

          !y is off the table edge

          IF(nx<4) STOP 'FIND2D: Not enough x points in your table for cubic interpolation'
          IF(ny<2) STOP 'FIND2D: Not enough y points in your table for linear interpolation'

          IF(x<=xtab(4)) THEN

             i=2

          ELSE IF (x>=xtab(nx-3)) THEN

             i=nx-2

          ELSE

             i=table_integer(x,xtab,nx,ifind)

          END IF

          i1=i-1
          i2=i
          i3=i+1
          i4=i+2

          x1=xtab(i1)
          x2=xtab(i2)
          x3=xtab(i3)
          x4=xtab(i4)

          IF(y<ytab(1)) THEN

             j1=1
             j2=2

          ELSE

             j1=ny-1
             j2=ny

          END IF

          y1=ytab(j1)
          y2=ytab(j2)

          f11=ftab(i1,j1)
          f21=ftab(i2,j1)
          f31=ftab(i3,j1)
          f41=ftab(i4,j1)

          f12=ftab(i1,j2)
          f22=ftab(i2,j2)
          f32=ftab(i3,j2)
          f42=ftab(i4,j2)

          !x interpolation

          CALL fit_cubic(a,b,c,d,x1,f11,x2,f21,x3,f31,x4,f41)
          f01=a*x**3+b*x**2+c*x+d

          CALL fit_cubic(a,b,c,d,x1,f12,x2,f22,x3,f32,x4,f42)
          f02=a*x**3+b*x**2+c*x+d

          !y interpolation

          CALL fit_line(a,b,y1,f01,y2,f02)
          find2d=a*y+b

       ELSE

          !Points exists within table boundardies (normal)

          IF(nx<4) STOP 'FIND2D: Not enough x points in your table for cubic interpolation'
          IF(ny<4) STOP 'FIND2D: Not enough y points in your table for cubic interpolation'

          IF(x<=xtab(4)) THEN

             i=2

          ELSE IF (x>=xtab(nx-3)) THEN

             i=nx-2

          ELSE

             i=table_integer(x,xtab,nx,ifind)

          END IF

          i1=i-1
          i2=i
          i3=i+1
          i4=i+2

          x1=xtab(i1)
          x2=xtab(i2)
          x3=xtab(i3)
          x4=xtab(i4)

          IF(y<=ytab(4)) THEN

             j=2

          ELSE IF (y>=ytab(ny-3)) THEN

             j=ny-2

          ELSE

             j=table_integer(y,ytab,ny,ifind)

          END IF

          j1=j-1
          j2=j
          j3=j+1
          j4=j+2

          y1=ytab(j1)
          y2=ytab(j2)
          y3=ytab(j3)
          y4=ytab(j4)

          !

          f11=ftab(i1,j1)
          f12=ftab(i1,j2)
          f13=ftab(i1,j3)
          f14=ftab(i1,j4)

          f21=ftab(i2,j1)
          f22=ftab(i2,j2)
          f23=ftab(i2,j3)
          f24=ftab(i2,j4)

          f31=ftab(i3,j1)
          f32=ftab(i3,j2)
          f33=ftab(i3,j3)
          f34=ftab(i3,j4)

          f41=ftab(i4,j1)
          f42=ftab(i4,j2)
          f43=ftab(i4,j3)
          f44=ftab(i4,j4)

          !x interpolation

          CALL fit_cubic(a,b,c,d,x1,f11,x2,f21,x3,f31,x4,f41)
          f01=a*x**3+b*x**2+c*x+d

          CALL fit_cubic(a,b,c,d,x1,f12,x2,f22,x3,f32,x4,f42)
          f02=a*x**3+b*x**2+c*x+d

          CALL fit_cubic(a,b,c,d,x1,f13,x2,f23,x3,f33,x4,f43)
          f03=a*x**3+b*x**2+c*x+d

          CALL fit_cubic(a,b,c,d,x1,f14,x2,f24,x3,f34,x4,f44)
          f04=a*x**3+b*x**2+c*x+d

          CALL fit_cubic(a,b,c,d,y1,f01,y2,f02,y3,f03,y4,f04)
          findy=a*y**3+b*y**2+c*y+d

          !y interpolation

          CALL fit_cubic(a,b,c,d,y1,f11,y2,f12,y3,f13,y4,f14)
          f10=a*y**3+b*y**2+c*y+d

          CALL fit_cubic(a,b,c,d,y1,f21,y2,f22,y3,f23,y4,f24)
          f20=a*y**3+b*y**2+c*y+d

          CALL fit_cubic(a,b,c,d,y1,f31,y2,f32,y3,f33,y4,f34)
          f30=a*y**3+b*y**2+c*y+d

          CALL fit_cubic(a,b,c,d,y1,f41,y2,f42,y3,f43,y4,f44)
          f40=a*y**3+b*y**2+c*y+d

          CALL fit_cubic(a,b,c,d,x1,f10,x2,f20,x3,f30,x4,f40)
          findx=a*x**3+b*x**2+c*x+d

          !Final result is an average over each direction
          find2d=(findx+findy)/2.

       END IF

    ELSE

       STOP 'FIND2D: order for interpolation not specified correctly'

    END IF

  END FUNCTION find2d

  FUNCTION Lagrange_polynomial(x,n,xv,yv)

    !Computes the result of the nth order Lagrange polynomial at point x, L(x)
    IMPLICIT NONE
    REAL*8 :: Lagrange_polynomial
    REAL*8, INTENT(IN) :: x, xv(n+1), yv(n+1)
    REAL*8 :: l(n+1)
    INTEGER, INTENT(IN) :: n
    INTEGER :: i, j

    !Initialise variables, one for sum and one for multiplication
    Lagrange_polynomial=0.
    l=1.

    !Loops to find the polynomials, one is a sum and one is a multiple
    DO i=0,n
       DO j=0,n
          IF(i .NE. j) l(i+1)=l(i+1)*(x-xv(j+1))/(xv(i+1)-xv(j+1))
       END DO
       Lagrange_polynomial=Lagrange_polynomial+l(i+1)*yv(i+1)
    END DO

  END FUNCTION Lagrange_polynomial

  FUNCTION table_integer(x,xtab,n,imeth)

    !Chooses between ways to find the integer location below some value in an array
    IMPLICIT NONE
    INTEGER :: table_integer
    INTEGER, INTENT(IN) :: n
    REAL*8, INTENT(IN) :: x, xtab(n)
    INTEGER, INTENT(IN) :: imeth

    IF(imeth==1) THEN
       table_integer=linear_table_integer(x,xtab,n)
    ELSE IF(imeth==2) THEN
       table_integer=search_int(x,xtab,n)
    ELSE IF(imeth==3) THEN
       table_integer=int_split(x,xtab,n)
    ELSE
       STOP 'TABLE INTEGER: Method specified incorrectly'
    END IF

  END FUNCTION table_integer

  FUNCTION linear_table_integer(x,xtab,n)

    !Assuming the table is exactly linear this gives you the integer position
    IMPLICIT NONE
    INTEGER :: linear_table_integer
    INTEGER, INTENT(IN) :: n
    REAL*8, INTENT(IN) :: x, xtab(n)
    REAL*8 :: x1, x2, xn
    REAL*8, PARAMETER :: acc=1d-3 !Test for table linearity (wasteful)

    !Returns the integer (table position) below the value of x
    !eg. if x(3)=6. and x(4)=7. and x=6.5 this will return 6
    !Assumes table is organised linearly (care for logs)

    x1=xtab(1)
    x2=xtab(2)
    xn=xtab(n)

    IF(x1>xn) STOP 'LINEAR_TABLE_INTEGER :: table in the wrong order'
    IF(ABS(-1.+float(n-1)*(x2-x1)/(xn-x1))>acc) STOP 'LINEAR_TABLE_INTEGER :: table does not seem to be linear'

    linear_table_integer=1+FLOOR(float(n-1)*(x-x1)/(xn-x1))

  END FUNCTION linear_table_integer

  FUNCTION search_int(x,xtab,n)

    !Does a stupid search through the table from beginning to end to find integer
    IMPLICIT NONE
    INTEGER :: search_int
    INTEGER, INTENT(IN) :: n
    REAL*8, INTENT(IN) :: x, xtab(n)
    INTEGER :: i

    IF(xtab(1)>xtab(n)) STOP 'SEARCH_INT: table in wrong order'

    DO i=1,n
       IF(x>=xtab(i) .AND. x<=xtab(i+1)) EXIT
    END DO

    search_int=i

  END FUNCTION search_int

  FUNCTION int_split(x,xtab,n)

    !Finds the position of the value in the table by continually splitting it in half
    IMPLICIT NONE
    INTEGER :: int_split
    INTEGER, INTENT(IN) :: n
    REAL*8, INTENT(IN) :: x, xtab(n)
    INTEGER :: i1, i2, imid

    IF(xtab(1)>xtab(n)) STOP 'INT_SPLIT: table in wrong order'

    i1=1
    i2=n

    DO

       imid=NINT((i1+i2)/2.)

       IF(x<xtab(imid)) THEN
          i2=imid
       ELSE
          i1=imid
       END IF

       IF(i2==i1+1) EXIT

    END DO

    int_split=i1

  END FUNCTION int_split

  SUBROUTINE fit_line(a1,a0,x1,y1,x2,y2)

    !Given xi, yi i=1,2 fits a line between these points
    IMPLICIT NONE
    REAL*8, INTENT(OUT) :: a0, a1
    REAL*8, INTENT(IN) :: x1, y1, x2, y2   

    a1=(y2-y1)/(x2-x1)
    a0=y1-a1*x1

  END SUBROUTINE fit_line

  SUBROUTINE fit_quadratic(a2,a1,a0,x1,y1,x2,y2,x3,y3)

    !Given xi, yi i=1,2,3 fits a quadratic between these points
    IMPLICIT NONE
    REAL*8, INTENT(OUT) :: a0, a1, a2
    REAL*8, INTENT(IN) :: x1, y1, x2, y2, x3, y3   

    a2=((y2-y1)/(x2-x1)-(y3-y1)/(x3-x1))/(x2-x3)
    a1=(y2-y1)/(x2-x1)-a2*(x2+x1)
    a0=y1-a2*(x1**2)-a1*x1

  END SUBROUTINE fit_quadratic

  SUBROUTINE fit_cubic(a,b,c,d,x1,y1,x2,y2,x3,y3,x4,y4)

    !Given xi, yi i=1,2,3,4 fits a cubic between these points
    IMPLICIT NONE
    REAL*8, INTENT(OUT) :: a, b, c, d
    REAL*8, INTENT(IN) :: x1, y1, x2, y2, x3, y3, x4, y4
    REAL*8 :: f1, f2, f3    

    f1=(y4-y1)/((x4-x2)*(x4-x1)*(x4-x3))
    f2=(y3-y1)/((x3-x2)*(x3-x1)*(x4-x3))
    f3=(y2-y1)/((x2-x1)*(x4-x3))*(1./(x4-x2)-1./(x3-x2))

    a=f1-f2-f3

    f1=(y3-y1)/((x3-x2)*(x3-x1))
    f2=(y2-y1)/((x2-x1)*(x3-x2))
    f3=a*(x3+x2+x1)

    b=f1-f2-f3

    f1=(y4-y1)/(x4-x1)
    f2=a*(x4**2+x4*x1+x1**2)
    f3=b*(x4+x1)

    c=f1-f2-f3

    d=y1-a*x1**3-b*x1**2-c*x1

  END SUBROUTINE fit_cubic

  SUBROUTINE reverse(arry,n)

    !This reverses the contents of arry!
    IMPLICIT NONE
    INTEGER, INTENT(IN) :: n
    REAL*8, INTENT(INOUT) :: arry(n)
    INTEGER :: i
    REAL*8, ALLOCATABLE :: hold(:) 

    ALLOCATE(hold(n))

    hold=arry

    DO i=1,n
       arry(i)=hold(n-i+1)
    END DO

    DEALLOCATE(hold)

  END SUBROUTINE reverse

  FUNCTION file_length(file_name)

    IMPLICIT NONE
    CHARACTER(len=64) :: file_name
    INTEGER ::n, file_length
    REAL*8 :: data

    !Finds the length of a file

    OPEN(7,file=file_name)
    n=0
    DO
       n=n+1
       READ(7,*, end=301) data
    END DO

    !301 is just the label to jump to when the end of the file is reached

301 CLOSE(7)  

    file_length=n-1

  END FUNCTION file_length

  SUBROUTINE fill_growtab(cosm)

    !Fills a table of the growth function vs. a
    !USE cosdef
    IMPLICIT NONE
    TYPE(cosmology) :: cosm
    INTEGER :: i
    REAL*8 :: a, norm
    REAL*8, ALLOCATABLE :: d_tab(:), v_tab(:), a_tab(:)
    REAL*8 :: ainit, amax, dinit, vinit
    !REAL*8, PARAMETER :: acc=1d-4
    INTEGER, PARAMETER :: n=64 !Number of entries for growth tables

    !The calculation should start at a z when Om_m(z)=1., so that the assumption
    !of starting in the g\propto a growing mode is valid (this will not work for early DE)
    ainit=0.001
    !Final should be a=1. unless considering models in the future
    amax=1.

    !These set the initial conditions to be the Om_m=1. growing mode
    dinit=ainit
    vinit=1.

    !Overall accuracy for the ODE solver
    !acc=0.001

    IF(ihm==1) WRITE(*,*) 'GROWTH: Solving growth equation'
    CALL ode_growth(d_tab,v_tab,a_tab,0.d0,ainit,amax,dinit,vinit,acc,3,cosm)
    IF(ihm==1) WRITE(*,*) 'GROWTH: ODE done'

    !Normalise so that g(z=0)=1
    norm=find(1.d0,a_tab,d_tab,SIZE(a_tab),3,3,2)
    IF(ihm==1) WRITE(*,*) 'GROWTH: unnormalised g(a=1):', norm
    d_tab=d_tab/norm
    IF(ihm==1) WRITE(*,*)

    !This downsamples the tables that come out of the ODE solver (which can be a bit long)
    !Could use some table-interpolation routine here to save time
    IF(ALLOCATED(cosm%a_growth)) DEALLOCATE(cosm%a_growth,cosm%growth)
    cosm%ng=n

    ALLOCATE(cosm%a_growth(n),cosm%growth(n))
    DO i=1,n
       a=ainit+(amax-ainit)*float(i-1)/float(n-1)
       cosm%a_growth(i)=a
       cosm%growth(i)=find(a,a_tab,d_tab,SIZE(a_tab),3,3,2)
    END DO

  END SUBROUTINE fill_growtab

 SUBROUTINE ode_growth(x,v,t,kk,ti,tf,xi,vi,acc,imeth,cosm)

    !Solves 2nd order ODE x''(t) from ti to tf and writes out array of x, v, t values 
    IMPLICIT NONE
    REAL*8 :: xi, ti, tf, dt, acc, vi, x4, v4, t4, kk
    REAL*8 :: kx1, kx2, kx3, kx4, kv1, kv2, kv3, kv4
    REAL*8, ALLOCATABLE :: x8(:), t8(:), v8(:), xh(:), th(:), vh(:)
    REAL*8, ALLOCATABLE :: x(:), v(:), t(:)
    INTEGER :: i, j, k, n, np, ifail, kn, imeth
    TYPE(cosmology) :: cosm
    INTEGER, PARAMETER :: jmax=30
    INTEGER, PARAMETER :: ninit=100

    !xi and vi are the initial values of x and v (i.e. x(ti), v(ti))
    !fx is what x' is equal to
    !fv is what v' is equal to
    !acc is the desired accuracy across the entire solution
    !imeth selects method

    IF(ALLOCATED(x)) DEALLOCATE(x)
    IF(ALLOCATED(v)) DEALLOCATE(v)
    IF(ALLOCATED(t)) DEALLOCATE(t)

    DO j=1,jmax

       !Set the number of points for the forward integration
       n=ninit*(2**(j-1))
       n=n+1  

       !Allocate arrays
       ALLOCATE(x8(n),t8(n),v8(n))

       !Set the arrays to initialy be zeroes (is this neceseary?)
       x8=0.d0
       t8=0.d0
       v8=0.d0

       !Set the intial conditions at the intial time
       x8(1)=xi
       v8(1)=vi

       !Fill up a table for the time values
       CALL fill_table(DBLE(ti),DBLE(tf),t8,n)

       !Set the time interval
       dt=(tf-ti)/float(n-1)

       !Intially fix this to zero. It will change to 1 if method is a 'failure'
       ifail=0

       DO i=1,n-1

          x4=real(x8(i))
          v4=real(v8(i))
          t4=real(t8(i))

          IF(imeth==1) THEN

             !Crude method
             kx1=dt*fd(x4,v4,kk,t4,cosm)
             kv1=dt*fv(x4,v4,kk,t4,cosm)

             x8(i+1)=x8(i)+kx1
             v8(i+1)=v8(i)+kv1
                  
          ELSE IF(imeth==2) THEN

             !Mid-point method
             !2017/06/18 - There was a bug in this part before. Luckily it was not used. Thanks Dipak Munshi.
             kx1=dt*fd(x4,v4,kk,t4,cosm)
             kv1=dt*fv(x4,v4,kk,t4,cosm)
             kx2=dt*fd(x4+kx1/2.,v4+kv1/2.,kk,t4+dt/2.,cosm)
             kv2=dt*fv(x4+kx1/2.,v4+kv1/2.,kk,t4+dt/2.,cosm)

             x8(i+1)=x8(i)+kx2
             v8(i+1)=v8(i)+kv2
             
          ELSE IF(imeth==3) THEN

             !4th order Runge-Kutta method (fast!)
             kx1=dt*fd(x4,v4,kk,t4,cosm)
             kv1=dt*fv(x4,v4,kk,t4,cosm)
             kx2=dt*fd(x4+kx1/2.,v4+kv1/2.,kk,t4+dt/2.,cosm)
             kv2=dt*fv(x4+kx1/2.,v4+kv1/2.,kk,t4+dt/2.,cosm)
             kx3=dt*fd(x4+kx2/2.,v4+kv2/2.,kk,t4+dt/2.,cosm)
             kv3=dt*fv(x4+kx2/2.,v4+kv2/2.,kk,t4+dt/2.,cosm)
             kx4=dt*fd(x4+kx3,v4+kv3,kk,t4+dt,cosm)
             kv4=dt*fv(x4+kx3,v4+kv3,kk,t4+dt,cosm)

             x8(i+1)=x8(i)+(kx1+(2.*kx2)+(2.*kx3)+kx4)/6.
             v8(i+1)=v8(i)+(kv1+(2.*kv2)+(2.*kv3)+kv4)/6.

          END IF

          !t8(i+1)=t8(i)+dt

       END DO

       IF(j==1) ifail=1

       IF(j .NE. 1) THEN

          np=1+(n-1)/2

          DO k=1,1+(n-1)/2

             kn=2*k-1

             IF(ifail==0) THEN

                IF(xh(k)>acc .AND. x8(kn)>acc .AND. (ABS(xh(k)/x8(kn))-1.)>acc) ifail=1
                IF(vh(k)>acc .AND. v8(kn)>acc .AND. (ABS(vh(k)/v8(kn))-1.)>acc) ifail=1

                IF(ifail==1) THEN
                   DEALLOCATE(xh,th,vh)
                   EXIT
                END IF

             END IF
          END DO

       END IF

       IF(ifail==0) THEN
          ALLOCATE(x(n),t(n),v(n))
          x=real(x8)
          v=real(v8)
          t=real(t8)
          EXIT
       END IF

       ALLOCATE(xh(n),th(n),vh(n))
       xh=x8
       vh=v8
       th=t8
       DEALLOCATE(x8,t8,v8)

    END DO

  END SUBROUTINE ode_growth

!!$  SUBROUTINE ode_growth(x,v,t,kk,ti,tf,xi,vi,acc,imeth,cosm)
!!$
!!$    !USE cosdef
!!$    IMPLICIT NONE
!!$    REAL*8 :: xi, ti, tf, dt, acc, vi, x4, v4, t4, kk
!!$    REAL*8 :: kx1, kx2, kx3, kx4, kv1, kv2, kv3, kv4
!!$    REAL*8, ALLOCATABLE :: x8(:), t8(:), v8(:), xh(:), th(:), vh(:)
!!$    REAL*8, ALLOCATABLE :: x(:), v(:), t(:)
!!$    INTEGER :: i, j, k, n, np, ifail, kn, imeth
!!$    TYPE(cosmology) :: cosm
!!$
!!$    !Solves 2nd order ODE x''(t) from ti to tf and writes out array of x, v, t values
!!$    !xi and vi are the initial values of x and v (i.e. x(ti), v(ti))
!!$    !fx is what x' is equal to
!!$    !fv is what v' is equal to
!!$    !acc is the desired accuracy across the entire solution
!!$    !imeth selects method
!!$
!!$    IF(ALLOCATED(x)) DEALLOCATE(x)
!!$    IF(ALLOCATED(v)) DEALLOCATE(v)
!!$    IF(ALLOCATED(t)) DEALLOCATE(t)
!!$
!!$    DO j=1,30
!!$
!!$       n=100*(2**(j-1))
!!$       n=n+1  
!!$
!!$       ALLOCATE(x8(n),t8(n),v8(n))
!!$
!!$       x8=0.d0
!!$       t8=0.d0
!!$       v8=0.d0
!!$
!!$       dt=(tf-ti)/float(n-1)
!!$
!!$       x8(1)=xi
!!$       v8(1)=vi
!!$       t8(1)=ti
!!$
!!$       ifail=0
!!$
!!$       DO i=1,n-1
!!$
!!$          x4=real(x8(i))
!!$          v4=real(v8(i))
!!$          t4=real(t8(i))
!!$
!!$          IF(imeth==1) THEN
!!$
!!$             !Crude method!
!!$             v8(i+1)=v8(i)+fv(x4,v4,kk,t4,cosm)*dt
!!$             x8(i+1)=x8(i)+fd(x4,v4,kk,t4,cosm)*dt
!!$             t8(i+1)=t8(i)+dt
!!$
!!$          ELSE IF(imeth==2) THEN
!!$
!!$             STOP 'There is a bug here with dt being multiplied twice - corrected version in HMcode.f90'
!!$
!!$             !Mid-point method!
!!$             kx1=dt*fd(x4,v4,kk,t4,cosm)
!!$             kv1=dt*fv(x4,v4,kk,t4,cosm)
!!$             kx2=dt*fd(x4+kx1/2.,v4+kv1/2.,kk,t4+dt/2.,cosm)
!!$             kv2=dt*fv(x4+kx1/2.,v4+kv1/2.,kk,t4+dt/2.,cosm)
!!$
!!$             v8(i+1)=v8(i)+kv2*dt
!!$             x8(i+1)=x8(i)+kx2*dt
!!$             t8(i+1)=t8(i)+dt
!!$
!!$          ELSE IF(imeth==3) THEN
!!$
!!$             !4th order Runge-Kutta method (fucking fast)!
!!$             kx1=dt*fd(x4,v4,kk,t4,cosm)
!!$             kv1=dt*fv(x4,v4,kk,t4,cosm)
!!$             kx2=dt*fd(x4+kx1/2.,v4+kv1/2.,kk,t4+dt/2.,cosm)
!!$             kv2=dt*fv(x4+kx1/2.,v4+kv1/2.,kk,t4+dt/2.,cosm)
!!$             kx3=dt*fd(x4+kx2/2.,v4+kv2/2.,kk,t4+dt/2.,cosm)
!!$             kv3=dt*fv(x4+kx2/2.,v4+kv2/2.,kk,t4+dt/2.,cosm)
!!$             kx4=dt*fd(x4+kx3,v4+kv3,kk,t4+dt,cosm)
!!$             kv4=dt*fv(x4+kx3,v4+kv3,kk,t4+dt,cosm)
!!$
!!$             x8(i+1)=x8(i)+(kx1+(2.*kx2)+(2.*kx3)+kx4)/6.
!!$             v8(i+1)=v8(i)+(kv1+(2.*kv2)+(2.*kv3)+kv4)/6.
!!$             t8(i+1)=t8(i)+dt
!!$
!!$          END IF
!!$
!!$       END DO
!!$
!!$       IF(j==1) ifail=1
!!$
!!$       IF(j .NE. 1) THEN
!!$
!!$          np=1+(n-1)/2
!!$
!!$          DO k=1,1+(n-1)/2
!!$
!!$             kn=2*k-1
!!$
!!$             IF(ifail==0) THEN
!!$
!!$                IF(xh(k)>acc .AND. x8(kn)>acc .AND. (ABS(xh(k)/x8(kn))-1.)>acc) ifail=1
!!$                IF(vh(k)>acc .AND. v8(kn)>acc .AND. (ABS(vh(k)/v8(kn))-1.)>acc) ifail=1
!!$
!!$                IF(ifail==1) THEN
!!$                   DEALLOCATE(xh,th,vh)
!!$                   EXIT
!!$                END IF
!!$
!!$             END IF
!!$          END DO
!!$
!!$       END IF
!!$
!!$       IF(ifail==0) THEN
!!$          ALLOCATE(x(n),t(n),v(n))
!!$          x=real(x8)
!!$          v=real(v8)
!!$          t=real(t8)
!!$          EXIT
!!$       END IF
!!$
!!$       ALLOCATE(xh(n),th(n),vh(n))
!!$       xh=x8
!!$       vh=v8
!!$       th=t8
!!$       DEALLOCATE(x8,t8,v8)
!!$
!!$    END DO
!!$
!!$  END SUBROUTINE ode_growth

  FUNCTION fv(d,v,k,a,cosm)

    !USE cosdef
    IMPLICIT NONE
    REAL*8 :: fv
    REAL*8, INTENT(IN) :: d, v, k, a
    REAL*8 :: f1, f2, z
    TYPE(cosmology), INTENT(IN) :: cosm

    !Needed for growth function solution
    !This is the fv in \ddot{\delta}=fv

    z=-1.+(1./a)

    f1=3.*omega_m(z,cosm)*d/(2.*(a**2))
    f2=(2.+AH(z,cosm)/hubble2(z,cosm))*(v/a)

    fv=f1-f2

  END FUNCTION fv

  FUNCTION fd(d,v,k,a,cosm)

    !USE cosdef
    IMPLICIT NONE
    REAL*8 :: fd
    REAL*8, INTENT(IN) :: d, v, k, a
    TYPE(cosmology), INTENT(IN) :: cosm

    !Needed for growth function solution
    !This is the fd in \dot{\delta}=fd

    fd=v

  END FUNCTION fd

  FUNCTION AH(z,cosm)

    !USE cosdef
    IMPLICIT NONE
    REAL*8 :: AH
    REAL*8, INTENT(IN) :: z
    REAL*8 :: a
    TYPE(cosmology), INTENT(IN) :: cosm

    !\ddot{a}/a

    a=1./(1.+z)

    AH=cosm%om_m*(a**(-3))+cosm%om_v*(1.+3.*w_de(a,cosm))*X_de(a,cosm)

    AH=-AH/2.

  END FUNCTION AH

  FUNCTION X_de(a,cosm)

    !USE cosdef
    IMPLICIT NONE
    REAL*8 :: X_de
    REAL*8, INTENT(IN) :: a
    TYPE(cosmology), INTENT(IN) :: cosm

    !The time evolution for Om_w for w(a) DE models
    X_de=(a**(-3.*(1.+cosm%w+cosm%wa)))*exp(-3.*cosm%wa*(1.-a))

  END FUNCTION X_de

  FUNCTION w_de(a,cosm)

    !w(a) for DE models
    !USE cosdef
    IMPLICIT NONE
    REAL*8 :: w_de
    REAL*8, INTENT(IN) :: a
    TYPE(cosmology), INTENT(IN) :: cosm

    w_de=cosm%w+(1.-a)*cosm%wa

  END FUNCTION w_de

  PURE FUNCTION sinc(x)

    !Sinc(x)=sin(x)/x
    IMPLICIT NONE
    REAL*8 :: sinc
    REAL*8, INTENT(IN) :: x
    REAL*8, PARAMETER :: dx=1e-3

    !Actually I don't think you need the IF because there is no subtraction cancellationm. Only sinc(0) is a problem
    IF(ABS(x)<ABS(dx)) THEN
       sinc=1.d0-(x**2)/6.d0
    ELSE
       sinc=sin(x)/x
    END IF

  END FUNCTION sinc

  FUNCTION halo_fraction(itype,m,cosm)

    !Mass fraction of a type within a halo
    IMPLICIT NONE
    REAL*8 :: halo_fraction
    INTEGER, INTENT(IN) :: itype
    REAL*8, INTENT(IN) :: m
    TYPE(cosmology) :: cosm

    If(itype==-1 .OR. itype==0) THEN
       halo_fraction=1.
    ELSE IF(itype==1) THEN
       halo_fraction=halo_CDM_fraction(m,cosm)
    ELSE IF(itype==2) THEN
       halo_fraction=halo_gas_fraction(m,cosm)
    ELSE IF(itype==3) THEN
       halo_fraction=halo_star_fraction(m,cosm)
    ELSE IF(itype==4) THEN
       halo_fraction=halo_boundgas_fraction(m,cosm)
    ELSE IF(itype==5) THEN
       halo_fraction=halo_freegas_fraction(m,cosm)
    ELSE
       STOP 'HALO_FRACTION: Error, itype not specified correcntly'
    END IF

  END FUNCTION halo_fraction

  FUNCTION halo_gas_fraction(m,cosm)

    !Mass fraction of a halo in gas
    IMPLICIT NONE
    REAL*8 :: halo_gas_fraction
    REAL*8, INTENT(IN) :: m
    TYPE(cosmology), INTENT(IN) :: cosm

    halo_gas_fraction=halo_boundgas_fraction(m,cosm)+halo_freegas_fraction(m,cosm)

  END FUNCTION halo_gas_fraction

  FUNCTION halo_CDM_fraction(m,cosm)

    !Mass fraction of a halo in CDM
    IMPLICIT NONE
    REAL*8 :: halo_CDM_fraction
    REAL*8, INTENT(IN) :: m
    TYPE(cosmology), INTENT(IN) :: cosm

    !Always the universal value
    halo_CDM_fraction=cosm%om_c/cosm%om_m

  END FUNCTION halo_CDM_fraction

  FUNCTION halo_freegas_fraction(m,cosm)

    !Mass fraction of a halo in free gas
    IMPLICIT NONE
    REAL*8 :: halo_freegas_fraction
    REAL*8, INTENT(IN) :: m
    TYPE(cosmology), INTENT(IN) :: cosm

    !This is always all the gas that is not bound or in stars
    halo_freegas_fraction=cosm%om_b/cosm%om_m-halo_star_fraction(m,cosm)-halo_boundgas_fraction(m,cosm)
    IF(halo_freegas_fraction<0.d0) halo_freegas_fraction=0.d0

  END FUNCTION halo_freegas_fraction

  FUNCTION halo_boundgas_fraction(m,cosm)

    !Fraction of a halo in bound gas
    IMPLICIT NONE
    REAL*8 :: halo_boundgas_fraction
    REAL*8, INTENT(IN) :: m
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8 :: m0, sigma, beta
    INTEGER, PARAMETER :: imod=2 !Set the model

    IF(imod==1) THEN
       !From Fedeli (2014a)
       m0=1.e12
       sigma=3.
       IF(m<m0) THEN
          halo_boundgas_fraction=0.
       ELSE
          halo_boundgas_fraction=erf(log10(m/m0)/sigma)*cosm%om_b/cosm%om_m
       END IF
    ELSE IF(imod==2) THEN
       !From Schneider (2015)
       m0=1.2d14
       beta=0.6
       halo_boundgas_fraction=(cosm%om_b/cosm%om_m)/(1.+(m0/m)**beta)
    ELSE
       STOP 'HALO_BOUNDGAS_FRACTION: Error, imod_boundfrac not specified correctly'
    END IF

  END FUNCTION halo_boundgas_fraction

  FUNCTION halo_star_fraction(m,cosm)

    !Mass fraction of a halo in stars
    IMPLICIT NONE
    REAL*8 :: halo_star_fraction
    REAL*8, INTENT(IN) :: m
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8 :: m0, sigma, A, min
    INTEGER, PARAMETER :: imod=3 !Set the model

    IF(imod==1 .OR. imod==3) THEN
       !Fedeli (2014)
       A=0.024
       m0=5.e12
       sigma=1.2
       halo_star_fraction=A*exp(-((log10(m/m0))**2)/(2.*sigma**2))
       IF(imod==3) THEN
          !Suggested by Ian, the relation I have is for the central stellar mass
          !in reality this saturates for high-mass haloes (due to satellite contribution)
          min=0.01
          IF(halo_star_fraction<min .AND. m>m0) halo_star_fraction=min
       END IF
    ELSE IF(imod==2) THEN
       !Constant star fraction
       A=0.005
       halo_star_fraction=A
    ELSE
       STOP 'HALO_STAR_FRACTION: Error, imod_starfrac specified incorrectly'
    END IF

  END FUNCTION halo_star_fraction

  SUBROUTINE get_nz(inz,lens)

    !The the n(z) function for lensing
    IMPLICIT NONE
    INTEGER, INTENT(INOUT) :: inz
    TYPE(lensing), INTENT(INOUT) :: lens
    CHARACTER(len=256) :: input
    INTEGER :: i
    REAL*8 :: zmin, zmax
    CHARACTER(len=256) :: names(6)

    names(1)='RCSLenS'
    names(2)='2 - KiDS (z = 0.1 -> 0.9)'
    names(3)='2 - KiDS (z = 0.1 -> 0.3)'
    names(4)='2 - KiDS (z = 0.3 -> 0.5)'
    names(5)='2 - KiDS (z = 0.5 -> 0.7)'
    names(6)='2 - KiDS (z = 0.7 -> 0.9)'

    IF(inz==-1) THEN
       WRITE(*,*) 'GET_NZ: Choose n(z)'
       WRITE(*,*) '==================='
       WRITE(*,*) '1 - RCSLenS'
       WRITE(*,*) '2 - KiDS (z = 0.1 -> 0.9)'
       WRITE(*,*) '3 - KiDS (z = 0.1 -> 0.3)'
       WRITE(*,*) '4 - KiDS (z = 0.3 -> 0.5)'
       WRITE(*,*) '5 - KiDS (z = 0.5 -> 0.7)'
       WRITE(*,*) '6 - KiDS (z = 0.7 -> 0.9)'
       READ(*,*) inz
       WRITE(*,*) '==================='
       WRITE(*,*)
    END IF

    IF(inz==1) THEN
       !From analytical function
       lens%nnz=512
       IF(ALLOCATED(lens%z_nz)) DEALLOCATE(lens%z_nz)
       IF(ALLOCATED(lens%nz))   DEALLOCATE(lens%nz)
       ALLOCATE(lens%z_nz(lens%nnz),lens%nz(lens%nnz))
       zmin=0.
       zmax=2.5
       CALL fill_table(zmin,zmax,lens%z_nz,lens%nnz)
       DO i=1,lens%nnz
          lens%nz(i)=nz_lensing(lens%z_nz(i),inz)
       END DO
    ELSE
       !Read in a file
       IF(inz==2) THEN
          input='/Users/Mead/Physics/KiDS/nz/KiDS_z0.1-0.9_MEAD.txt'
       ELSE IF(inz==3) THEN
          input='/Users/Mead/Physics/KiDS/nz/KiDS_z0.1-0.3.txt'
       ELSE IF(inz==4) THEN
          input='/Users/Mead/Physics/KiDS/nz/KiDS_z0.3-0.5.txt'
       ELSE IF(inz==5) THEN
          input='/Users/Mead/Physics/KiDS/nz/KiDS_z0.5-0.7.txt'
       ELSE IF(inz==6) THEN
          input='/Users/Mead/Physics/KiDS/nz/KiDS_z0.7-0.9.txt'
       ELSE
          STOP 'GET_NZ: inz not specified correctly'
       END IF
       WRITE(*,*) 'GET_NZ: Input file:', TRIM(input)
       lens%nnz=file_length(input)
       IF(ALLOCATED(lens%z_nz)) DEALLOCATE(lens%z_nz)
       IF(ALLOCATED(lens%nz))   DEALLOCATE(lens%nz)
       ALLOCATE(lens%z_nz(lens%nnz),lens%nz(lens%nnz))
       OPEN(7,file=input)
       DO i=1,lens%nnz
          READ(7,*) lens%z_nz(i), lens%nz(i)
       END DO
    END IF

    WRITE(*,*) 'GET_NZ: ', TRIM(names(inz))
    WRITE(*,*) 'GET_NZ: zmin:', lens%z_nz(1)
    WRITE(*,*) 'GET_NZ: zmax:', lens%z_nz(lens%nnz)
    WRITE(*,*) 'GET_NZ: nz:', lens%nnz
    WRITE(*,*)

  END SUBROUTINE get_nz

  FUNCTION nz_lensing(z,inz)

    IMPLICIT NONE
    REAL*8 :: nz_lensing
    REAL*8, INTENT(IN) :: z
    INTEGER, INTENT(IN) :: inz
    REAL*8 :: a, b, c, d, e, f, g, h, i
    REAL*8 :: n1, n2, n3

    IF(inz==1) THEN
       !RCSLenS
       a=2.94
       b=-0.44
       c=1.03
       d=1.58
       e=0.40
       f=0.25
       g=0.38
       h=0.81
       i=0.12
       n1=a*z*exp(-(z-b)**2/c**2)
       n2=d*z*exp(-(z-e)**2/f**2)
       n3=g*z*exp(-(z-h)**2/i**2)
       nz_lensing=n1+n2+n3
    ELSE
       STOP 'NZ_LENSING: inz specified incorrectly'
    END IF

  END FUNCTION nz_lensing

  FUNCTION InverseHubble(z,cosm)

    !1/H(z) in units of Mpc/h
    !USE cosdef
    IMPLICIT NONE
    REAL*8 :: InverseHubble
    REAL*8, INTENT(IN) :: z
    TYPE(cosmology) :: cosm

    InverseHubble=conH0/sqrt(hubble2(z,cosm))

  END FUNCTION InverseHubble

  FUNCTION integrate(a,b,f,acc,iorder)

    !Integrates between a and b until desired accuracy is reached
    !Stores information to reduce function calls
    IMPLICIT NONE
    REAL*8 :: integrate
    REAL*8, INTENT(IN) :: a, b, acc
    INTEGER, INTENT(IN) :: iorder
    INTEGER :: i, j
    INTEGER :: n
    REAL*8 :: x, dx
    REAL*8 :: f1, f2, fx
    REAL*8 :: sum_n, sum_2n, sum_new, sum_old
    INTEGER, PARAMETER :: jmin=5
    INTEGER, PARAMETER :: jmax=30

    INTERFACE
       FUNCTION f(x)
         REAL*8 :: f
         REAL*8, INTENT(IN) :: x
       END FUNCTION f
    END INTERFACE

    IF(a==b) THEN

       !Fix the answer to zero if the integration limits are identical
       integrate=0.d0

    ELSE

       !Reset the sum variable for the integration
       sum_2n=0.d0

       DO j=1,jmax
          
          !Note, you need this to be 1+2**n for some integer n
          !j=1 n=2; j=2 n=3; j=3 n=5; j=4 n=9; ...'
          n=1+2**(j-1)

          !Calculate the dx interval for this value of 'n'
          dx=(b-a)/DBLE(n-1)

          IF(j==1) THEN
             
             !The first go is just the trapezium of the end points
             f1=f(a)
             f2=f(b)
             sum_2n=0.5d0*(f1+f2)*dx
             
          ELSE

             !Loop over only new even points to add these to the integral
             DO i=2,n,2
                x=a+(b-a)*DBLE(i-1)/DBLE(n-1)
                fx=f(x)
                sum_2n=sum_2n+fx
             END DO

             !Now create the total using the old and new parts
             sum_2n=sum_n/2.d0+sum_2n*dx

             !Now calculate the new sum depending on the integration order
             IF(iorder==1) THEN  
                sum_new=sum_2n
             ELSE IF(iorder==3) THEN         
                sum_new=(4.d0*sum_2n-sum_n)/3.d0 !This is Simpson's rule and cancels error
             ELSE
                STOP 'INTEGRATE_STORE: Error, iorder specified incorrectly'
             END IF

          END IF

          IF((j>=jmin) .AND. (ABS(-1.d0+sum_new/sum_old)<acc)) THEN
             !jmin avoids spurious early convergence
             integrate=sum_new
             EXIT
          ELSE IF(j==jmax) THEN
             STOP 'INTEGRATE_STORE: Integration timed out'
          ELSE
             !Integral has not converged so store old sums and reset sum variables
             sum_old=sum_new
             sum_n=sum_2n
             sum_2n=0.d0
          END IF

       END DO

    END IF

  END FUNCTION integrate

  FUNCTION integrate_distance(a,b,acc,iorder,cosm)

    !Integrates between a and b until desired accuracy is reached
    !Stores information to reduce function calls
    IMPLICIT NONE
    REAL*8 :: integrate_distance
    REAL*8, INTENT(IN) :: a, b, acc
    INTEGER, INTENT(IN) :: iorder
    TYPE(cosmology), INTENT(IN) :: cosm
    INTEGER :: i, j
    INTEGER :: n
    REAL*8 :: x, dx
    REAL*8 :: f1, f2, fx
    REAL*8 :: sum_n, sum_2n, sum_new, sum_old
    INTEGER, PARAMETER :: jmin=5
    INTEGER, PARAMETER :: jmax=30  

    IF(a==b) THEN

       !Fix the answer to zero if the integration limits are identical
       integrate_distance=0.d0

    ELSE

       !Reset the sum variable for the integration
       sum_2n=0.d0

       DO j=1,jmax
          
          !Note, you need this to be 1+2**n for some integer n
          !j=1 n=2; j=2 n=3; j=3 n=5; j=4 n=9; ...'
          n=1+2**(j-1)

          !Calculate the dx interval for this value of 'n'
          dx=(b-a)/DBLE(n-1)

          IF(j==1) THEN
             
             !The first go is just the trapezium of the end points
             f1=InverseHubble(a,cosm)
             f2=InverseHubble(b,cosm)
             sum_2n=0.5d0*(f1+f2)*dx
             
          ELSE

             !Loop over only new even points to add these to the integral
             DO i=2,n,2
                x=a+(b-a)*DBLE(i-1)/DBLE(n-1)
                fx=InverseHubble(x,cosm)
                sum_2n=sum_2n+fx
             END DO

             !Now create the total using the old and new parts
             sum_2n=sum_n/2.d0+sum_2n*dx

             !Now calculate the new sum depending on the integration order
             IF(iorder==1) THEN  
                sum_new=sum_2n
             ELSE IF(iorder==3) THEN         
                sum_new=(4.d0*sum_2n-sum_n)/3.d0 !This is Simpson's rule and cancels error
             ELSE
                STOP 'INTEGRATE_STORE: Error, iorder specified incorrectly'
             END IF

          END IF

          IF((j>=jmin) .AND. (ABS(-1.d0+sum_new/sum_old)<acc)) THEN
             !jmin avoids spurious early convergence
             integrate_distance=sum_new
             EXIT
          ELSE IF(j==jmax) THEN
             STOP 'INTEGRATE_STORE: Integration timed out'
          ELSE
             !Integral has not converged so store old sums and reset sum variables
             sum_old=sum_new
             sum_n=sum_2n
             sum_2n=0.d0
          END IF

       END DO

    END IF

  END FUNCTION integrate_distance

  FUNCTION integrate_q(r,a,b,acc,iorder,lens,cosm)

    !Integrates between a and b until desired accuracy is reached
    !Stores information to reduce function calls
    IMPLICIT NONE
    REAL*8 :: integrate_q
    REAL*8, INTENT(IN) :: a, b, r, acc
    INTEGER, INTENT(IN) :: iorder
    TYPE(cosmology), INTENT(IN) :: cosm
    TYPE(lensing), INTENT(IN) :: lens
    INTEGER :: i, j
    INTEGER :: n
    REAL*8 :: x, dx
    REAL*8 :: f1, f2, fx
    REAL*8 :: sum_n, sum_2n, sum_new, sum_old
    INTEGER, PARAMETER :: jmin=5
    INTEGER, PARAMETER :: jmax=30

    IF(a==b) THEN

       !Fix the answer to zero if the integration limits are identical
       integrate_q=0.d0

    ELSE

       !Reset the sum variable for the integration
       sum_2n=0.d0

       DO j=1,jmax
          
          !Note, you need this to be 1+2**n for some integer n
          !j=1 n=2; j=2 n=3; j=3 n=5; j=4 n=9; ...'
          n=1+2**(j-1)

          !Calculate the dx interval for this value of 'n'
          dx=(b-a)/DBLE(n-1)

          IF(j==1) THEN
             
             !The first go is just the trapezium of the end points
             f1=q_integrand(a,r,lens,cosm)
             f2=q_integrand(b,r,lens,cosm)
             sum_2n=0.5d0*(f1+f2)*dx
             
          ELSE

             !Loop over only new even points to add these to the integral
             DO i=2,n,2
                x=a+(b-a)*DBLE(i-1)/DBLE(n-1)
                fx=q_integrand(x,r,lens,cosm)
                sum_2n=sum_2n+fx
             END DO

             !Now create the total using the old and new parts
             sum_2n=sum_n/2.d0+sum_2n*dx

             !Now calculate the new sum depending on the integration order
             IF(iorder==1) THEN  
                sum_new=sum_2n
             ELSE IF(iorder==3) THEN         
                sum_new=(4.d0*sum_2n-sum_n)/3.d0 !This is Simpson's rule and cancels error
             ELSE
                STOP 'INTEGRATE_STORE: Error, iorder specified incorrectly'
             END IF

          END IF

          IF((j>=jmin) .AND. (ABS(-1.d0+sum_new/sum_old)<acc)) THEN
             !jmin avoids spurious early convergence
             integrate_q=sum_new
             EXIT
          ELSE IF(j==jmax) THEN
             STOP 'INTEGRATE_STORE: Integration timed out'
          ELSE
             !Integral has not converged so store old sums and reset sum variables
             sum_old=sum_new
             sum_n=sum_2n
             sum_2n=0.d0
          END IF

       END DO

    END IF

  END FUNCTION integrate_q

  FUNCTION q_integrand(z,r,lens,cosm)

    !The lensing efficiency integrand, which is a function of z
    !z is integrated over while r is just a parameter
    !This is only called for n(z)
    IMPLICIT NONE
    REAL*8 :: q_integrand
    REAL*8, INTENT(IN) :: r, z
    TYPE(cosmology), INTENT(IN) :: cosm
    TYPE(lensing), INTENT(IN) :: lens
    REAL*8 :: rdash, nz

    IF(z==0.) THEN

       q_integrand=0.

    ELSE

       !Find the r'(z) variable that is integrated over
       rdash=find(z,cosm%z_r,cosm%r,cosm%nr,3,3,2)

       !Find the n(z)
       nz=find(z,lens%z_nz,lens%nz,lens%nnz,3,3,2)

       !This is then the integrand
       q_integrand=nz*f_k(rdash-r,cosm)/f_k(rdash,cosm)

    END IF

  END FUNCTION q_integrand

  FUNCTION integrate_Limber(l,a,b,ktab,ztab,ptab,nk,nz,acc,iorder,proj,cosm)

    !Integrates between a and b until desired accuracy is reached
    !Stores information to reduce function calls
    IMPLICIT NONE
    REAL*8 :: integrate_Limber
    REAL*8, INTENT(IN) :: a, b, acc
    INTEGER, INTENT(IN) :: iorder
    REAL*8, INTENT(IN) :: l
    REAL*8, INTENT(IN) :: ktab(nk), ztab(nz), ptab(nk,nz)
    INTEGER, INTENT(IN) :: nk, nz
    TYPE(projection), INTENT(IN) :: proj
    TYPE(cosmology), INTENT(IN) :: cosm
    REAL*8 :: r, z, k, x1, x2
    INTEGER :: i, j
    INTEGER :: n
    REAL*8 :: x, dx
    REAL*8 :: f1, f2, fx
    REAL*8 :: sum_n, sum_2n, sum_new, sum_old
    INTEGER, PARAMETER :: jmin=5
    INTEGER, PARAMETER :: jmax=30

    IF(a==b) THEN

       !Fix the answer to zero if the integration limits are identical
       integrate_Limber=0.d0

    ELSE

       !Reset the sum variable for the integration
       sum_2n=0.d0

       DO j=1,jmax
          
          !Note, you need this to be 1+2**n for some integer n
          !j=1 n=2; j=2 n=3; j=3 n=5; j=4 n=9; ...'
          n=1+2**(j-1)

          !Calculate the dx interval for this value of 'n'
          dx=(b-a)/DBLE(n-1)

          IF(j==1) THEN
             
             !The first go is just the trapezium of the end points
             f1=Limber_integrand(a,l,ktab,ztab,ptab,nk,nz,proj,cosm)
             f2=Limber_integrand(b,l,ktab,ztab,ptab,nk,nz,proj,cosm)
             sum_2n=0.5d0*(f1+f2)*dx
             
          ELSE

             !Loop over only new even points to add these to the integral
             DO i=2,n,2
                x=a+(b-a)*DBLE(i-1)/DBLE(n-1)
                fx=Limber_integrand(x,l,ktab,ztab,ptab,nk,nz,proj,cosm)
                sum_2n=sum_2n+fx
             END DO

             !Now create the total using the old and new parts
             sum_2n=sum_n/2.d0+sum_2n*dx

             !Now calculate the new sum depending on the integration order
             IF(iorder==1) THEN  
                sum_new=sum_2n
             ELSE IF(iorder==3) THEN         
                sum_new=(4.d0*sum_2n-sum_n)/3.d0 !This is Simpson's rule and cancels error
             ELSE
                STOP 'INTEGRATE_STORE: Error, iorder specified incorrectly'
             END IF

          END IF

          IF((j>=jmin) .AND. (ABS(-1.d0+sum_new/sum_old)<acc)) THEN
             !jmin avoids spurious early convergence
             integrate_Limber=sum_new
             EXIT
          ELSE IF(j==jmax) THEN
             STOP 'INTEGRATE_STORE: Integration timed out'
          ELSE
             !Integral has not converged so store old sums and reset sum variables
             sum_old=sum_new
             sum_n=sum_2n
             sum_2n=0.d0
          END IF

       END DO

    END IF

  END FUNCTION integrate_Limber

  FUNCTION Limber_integrand(r,l,ktab,ztab,ptab,nk,nz,proj,cosm)

    IMPLICIT NONE
    REAL*8 :: Limber_integrand
    REAL*8, INTENT(IN) :: r, l
    REAL*8, INTENT(IN) :: ktab(nk), ztab(nz), ptab(nk,nz)
    INTEGER, INTENT(IN) :: nk, nz
    TYPE(cosmology), INTENT(IN) :: cosm
    TYPE(projection), INTENT(IN) :: proj
    REAL*8 :: z, k, x1, x2

    IF(r==0.d0) THEN

       Limber_integrand=0.d0

    ELSE

       !Get variables r, z(r) and k(r)
       z=find(r,cosm%r,cosm%z_r,cosm%nr,3,3,2)
       k=(l+0.5)/f_k(r,cosm) !LoVerde et al. (2008) Limber correction
       
       !Get the two kernels
       x1=find(r,proj%r_x1,proj%x1,proj%nx1,3,3,2)
       x2=find(r,proj%r_x1,proj%x2,proj%nx2,3,3,2)
       
       !Construct the integrand (should use log finding?)
       Limber_integrand=x1*x2*find_pkz(k,z,ktab,ztab,ptab,nk,nz)/(f_k(r,cosm)**2)

    END IF
    
  END FUNCTION Limber_integrand

  FUNCTION find_pkz(k,z,ktab,ztab,pnltab,nk,nz)

    IMPLICIT NONE
    REAL*8 :: find_pkz
    INTEGER, INTENT(IN) :: nk, nz
    REAL*8, INTENT(IN) :: k, z
    REAL*8, INTENT(IN) :: ktab(nk), ztab(nz), pnltab(nk,nz)
    !k cut for kappa integral for some reason (?)
    REAL*8, PARAMETER :: kcut=1.e8

    !Looks up the non-linear power as a function of k and z

    IF(k==0.) THEN
       find_pkz=0.
    ELSE IF(k>kcut) THEN
       find_pkz=0.
    ELSE
       find_pkz=exp(find2d(log(k),log(ktab),z,ztab,log(pnltab),nk,nz,3,3,1))
    END IF

    !Convert from Delta^2 -> P(k) - with dimensions of (Mpc/h)^3
    find_pkz=(2.*pi**2)*find_pkz/k**3

  END FUNCTION find_pkz

!!$  FUNCTION find2d(x,xin,y,yin,fin,nx,ny,iorder,imeth)
!!$
!!$    !A 2D interpolation routine to find value f(x,y) at position x, y
!!$    IMPLICIT NONE
!!$    REAL*8 :: find2d
!!$    INTEGER, INTENT(IN) :: nx, ny
!!$    REAL*8, INTENT(IN) :: x, xin(nx), y, yin(ny), fin(nx,ny)
!!$    REAL*8, ALLOCATABLE ::  xtab(:), ytab(:), ftab(:,:)
!!$    REAL*8 :: a, b, c, d
!!$    REAL*8 :: x1, x2, x3, x4
!!$    REAL*8 :: y1, y2, y3, y4
!!$    REAL*8 :: f11, f12, f13, f14
!!$    REAL*8 :: f21, f22, f23, f24
!!$    REAL*8 :: f31, f32, f33, f34
!!$    REAL*8 :: f41, f42, f43, f44
!!$    REAL*8 :: f10, f20, f30, f40
!!$    REAL*8 :: f01, f02, f03, f04
!!$    INTEGER :: i1, i2, i3, i4
!!$    INTEGER :: j1, j2, j3, j4
!!$    REAL*8 :: findx, findy
!!$    INTEGER :: i, j
!!$    INTEGER, INTENT(IN) :: imeth, iorder
!!$
!!$    !This version interpolates if the value is off either end of the array!
!!$    !Care should be chosen to insert x, xtab, ytab as log if this might give better!
!!$    !Results from the interpolation!
!!$
!!$    !If the value required is off the table edge the interpolation is always linear
!!$
!!$    !imeth = 1 => find x in xtab by crudely searching from x(1) to x(n)
!!$    !imeth = 2 => find x in xtab quickly assuming the table is linearly spaced
!!$    !imeth = 3 => find x in xtab using midpoint splitting (iterations=CEILING(log2(n)))
!!$
!!$    !iorder = 1 => linear interpolation
!!$    !iorder = 2 => quadratic interpolation
!!$    !iorder = 3 => cubic interpolation
!!$
!!$    ALLOCATE(xtab(nx),ytab(ny),ftab(nx,ny))
!!$
!!$    xtab=xin
!!$    ytab=yin
!!$    ftab=fin
!!$
!!$    IF(xtab(1)>xtab(nx)) STOP 'FIND2D: x table in wrong order'
!!$    IF(ytab(1)>ytab(ny)) STOP 'FIND2D: y table in wrong order'
!!$
!!$    IF((x<xtab(1) .OR. x>xtab(nx)) .AND. (y>ytab(ny) .OR. y<ytab(1))) THEN
!!$       WRITE(*,*) 'FIND2D: point', x, y
!!$       STOP 'FIND2D: Desired point is outside x AND y table range'
!!$    END IF
!!$
!!$    IF(iorder==1) THEN
!!$
!!$       IF(nx<2) STOP 'FIND2D: Not enough x points in your table for linear interpolation'
!!$       IF(ny<2) STOP 'FIND2D: Not enough y points in your table for linear interpolation'
!!$
!!$       IF(x<=xtab(2)) THEN
!!$
!!$          i=1
!!$
!!$       ELSE IF (x>=xtab(nx-1)) THEN
!!$
!!$          i=nx-1
!!$
!!$       ELSE
!!$
!!$          i=table_integer(x,xtab,nx,imeth)
!!$
!!$       END IF
!!$
!!$       i1=i
!!$       i2=i+1
!!$
!!$       x1=xtab(i1)
!!$       x2=xtab(i2)      
!!$
!!$       IF(y<=ytab(2)) THEN
!!$
!!$          j=1
!!$
!!$       ELSE IF (y>=ytab(ny-1)) THEN
!!$
!!$          j=ny-1
!!$
!!$       ELSE
!!$
!!$          j=table_integer(y,ytab,ny,imeth)
!!$
!!$       END IF
!!$
!!$       j1=j
!!$       j2=j+1
!!$
!!$       y1=ytab(j1)
!!$       y2=ytab(j2)
!!$
!!$!!!
!!$
!!$       f11=ftab(i1,j1)
!!$       f12=ftab(i1,j2)
!!$
!!$       f21=ftab(i2,j1)
!!$       f22=ftab(i2,j2)
!!$
!!$!!! y direction interpolation
!!$
!!$       CALL fit_line(a,b,x1,f11,x2,f21)
!!$       f01=a*x+b
!!$
!!$       CALL fit_line(a,b,x1,f12,x2,f22)
!!$       f02=a*x+b
!!$
!!$       CALL fit_line(a,b,y1,f01,y2,f02)
!!$       findy=a*y+b
!!$
!!$!!! x direction interpolation
!!$
!!$       CALL fit_line(a,b,y1,f11,y2,f12)
!!$       f10=a*y+b
!!$
!!$       CALL fit_line(a,b,y1,f21,y2,f22)
!!$       f20=a*y+b
!!$
!!$       CALL fit_line(a,b,x1,f10,x2,f20)
!!$       findx=a*x+b
!!$
!!$!!!
!!$
!!$       !Final result is an average over each direction
!!$       find2d=(findx+findy)/2.
!!$
!!$    ELSE IF(iorder==2) THEN
!!$
!!$       STOP 'FIND2D: Quadratic 2D interpolation not implemented - also probably pointless'
!!$
!!$    ELSE IF(iorder==3) THEN
!!$
!!$       IF(x<xtab(1) .OR. x>xtab(nx)) THEN
!!$
!!$          IF(nx<2) STOP 'FIND2D: Not enough x points in your table for linear interpolation'
!!$          IF(ny<4) STOP 'FIND2D: Not enough y points in your table for cubic interpolation'
!!$
!!$          !x is off the table edge
!!$
!!$          IF(x<xtab(1)) THEN
!!$
!!$             i1=1
!!$             i2=2
!!$
!!$          ELSE
!!$
!!$             i1=nx-1
!!$             i2=nx
!!$
!!$          END IF
!!$
!!$          x1=xtab(i1)
!!$          x2=xtab(i2)
!!$
!!$          IF(y<=ytab(4)) THEN
!!$
!!$             j=2
!!$
!!$          ELSE IF (y>=ytab(ny-3)) THEN
!!$
!!$             j=ny-2
!!$
!!$          ELSE
!!$
!!$             j=table_integer(y,ytab,ny,imeth)
!!$
!!$          END IF
!!$
!!$          j1=j-1
!!$          j2=j
!!$          j3=j+1
!!$          j4=j+2
!!$
!!$          y1=ytab(j1)
!!$          y2=ytab(j2)
!!$          y3=ytab(j3)
!!$          y4=ytab(j4)
!!$
!!$          f11=ftab(i1,j1)
!!$          f12=ftab(i1,j2)
!!$          f13=ftab(i1,j3)
!!$          f14=ftab(i1,j4)
!!$
!!$          f21=ftab(i2,j1)
!!$          f22=ftab(i2,j2)
!!$          f23=ftab(i2,j3)
!!$          f24=ftab(i2,j4)
!!$
!!$!!! y interpolation
!!$
!!$          CALL fit_cubic(a,b,c,d,y1,f11,y2,f12,y3,f13,y4,f14)
!!$          f10=a*y**3+b*y**2+c*y+d
!!$
!!$          CALL fit_cubic(a,b,c,d,y1,f21,y2,f22,y3,f23,y4,f24)
!!$          f20=a*y**3+b*y**2+c*y+d
!!$
!!$!!! x interpolation
!!$
!!$          CALL fit_line(a,b,x1,f10,x2,f20)
!!$          find2d=a*x+b
!!$
!!$       ELSE IF(y<ytab(1) .OR. y>ytab(ny)) THEN
!!$
!!$          !y is off the table edge
!!$
!!$          IF(nx<4) STOP 'FIND2D: Not enough x points in your table for cubic interpolation'
!!$          IF(ny<2) STOP 'FIND2D: Not enough y points in your table for linear interpolation'
!!$
!!$          IF(x<=xtab(4)) THEN
!!$
!!$             i=2
!!$
!!$          ELSE IF (x>=xtab(nx-3)) THEN
!!$
!!$             i=nx-2
!!$
!!$          ELSE
!!$
!!$             i=table_integer(x,xtab,nx,imeth)
!!$
!!$          END IF
!!$
!!$          i1=i-1
!!$          i2=i
!!$          i3=i+1
!!$          i4=i+2
!!$
!!$          x1=xtab(i1)
!!$          x2=xtab(i2)
!!$          x3=xtab(i3)
!!$          x4=xtab(i4)
!!$
!!$          IF(y<ytab(1)) THEN
!!$
!!$             j1=1
!!$             j2=2
!!$
!!$          ELSE
!!$
!!$             j1=ny-1
!!$             j2=ny
!!$
!!$          END IF
!!$
!!$          y1=ytab(j1)
!!$          y2=ytab(j2)
!!$
!!$          f11=ftab(i1,j1)
!!$          f21=ftab(i2,j1)
!!$          f31=ftab(i3,j1)
!!$          f41=ftab(i4,j1)
!!$
!!$          f12=ftab(i1,j2)
!!$          f22=ftab(i2,j2)
!!$          f32=ftab(i3,j2)
!!$          f42=ftab(i4,j2)
!!$
!!$!!! x interpolation
!!$
!!$          CALL fit_cubic(a,b,c,d,x1,f11,x2,f21,x3,f31,x4,f41)
!!$          f01=a*x**3+b*x**2+c*x+d
!!$
!!$          CALL fit_cubic(a,b,c,d,x1,f12,x2,f22,x3,f32,x4,f42)
!!$          f02=a*x**3+b*x**2+c*x+d
!!$
!!$!!!y interpolation
!!$
!!$          CALL fit_line(a,b,y1,f01,y2,f02)
!!$          find2d=a*y+b
!!$
!!$       ELSE
!!$
!!$          !Points exists within table boundardies (normal)
!!$
!!$          IF(nx<4) STOP 'FIND2D: Not enough x points in your table for cubic interpolation'
!!$          IF(ny<4) STOP 'FIND2D: Not enough y points in your table for cubic interpolation'
!!$
!!$          IF(x<=xtab(4)) THEN
!!$
!!$             i=2
!!$
!!$          ELSE IF (x>=xtab(nx-3)) THEN
!!$
!!$             i=nx-2
!!$
!!$          ELSE
!!$
!!$             i=table_integer(x,xtab,nx,imeth)
!!$
!!$          END IF
!!$
!!$          i1=i-1
!!$          i2=i
!!$          i3=i+1
!!$          i4=i+2
!!$
!!$          x1=xtab(i1)
!!$          x2=xtab(i2)
!!$          x3=xtab(i3)
!!$          x4=xtab(i4)
!!$
!!$          IF(y<=ytab(4)) THEN
!!$
!!$             j=2
!!$
!!$          ELSE IF (y>=ytab(ny-3)) THEN
!!$
!!$             j=ny-2
!!$
!!$          ELSE
!!$
!!$             j=table_integer(y,ytab,ny,imeth)
!!$
!!$          END IF
!!$
!!$          j1=j-1
!!$          j2=j
!!$          j3=j+1
!!$          j4=j+2
!!$
!!$          y1=ytab(j1)
!!$          y2=ytab(j2)
!!$          y3=ytab(j3)
!!$          y4=ytab(j4)
!!$
!!$!!!
!!$
!!$          f11=ftab(i1,j1)
!!$          f12=ftab(i1,j2)
!!$          f13=ftab(i1,j3)
!!$          f14=ftab(i1,j4)
!!$
!!$          f21=ftab(i2,j1)
!!$          f22=ftab(i2,j2)
!!$          f23=ftab(i2,j3)
!!$          f24=ftab(i2,j4)
!!$
!!$          f31=ftab(i3,j1)
!!$          f32=ftab(i3,j2)
!!$          f33=ftab(i3,j3)
!!$          f34=ftab(i3,j4)
!!$
!!$          f41=ftab(i4,j1)
!!$          f42=ftab(i4,j2)
!!$          f43=ftab(i4,j3)
!!$          f44=ftab(i4,j4)
!!$
!!$!!! x interpolation
!!$
!!$          CALL fit_cubic(a,b,c,d,x1,f11,x2,f21,x3,f31,x4,f41)
!!$          f01=a*x**3+b*x**2+c*x+d
!!$
!!$          CALL fit_cubic(a,b,c,d,x1,f12,x2,f22,x3,f32,x4,f42)
!!$          f02=a*x**3+b*x**2+c*x+d
!!$
!!$          CALL fit_cubic(a,b,c,d,x1,f13,x2,f23,x3,f33,x4,f43)
!!$          f03=a*x**3+b*x**2+c*x+d
!!$
!!$          CALL fit_cubic(a,b,c,d,x1,f14,x2,f24,x3,f34,x4,f44)
!!$          f04=a*x**3+b*x**2+c*x+d
!!$
!!$          CALL fit_cubic(a,b,c,d,y1,f01,y2,f02,y3,f03,y4,f04)
!!$          findy=a*y**3+b*y**2+c*y+d
!!$
!!$!!! y interpolation
!!$
!!$          CALL fit_cubic(a,b,c,d,y1,f11,y2,f12,y3,f13,y4,f14)
!!$          f10=a*y**3+b*y**2+c*y+d
!!$
!!$          CALL fit_cubic(a,b,c,d,y1,f21,y2,f22,y3,f23,y4,f24)
!!$          f20=a*y**3+b*y**2+c*y+d
!!$
!!$          CALL fit_cubic(a,b,c,d,y1,f31,y2,f32,y3,f33,y4,f34)
!!$          f30=a*y**3+b*y**2+c*y+d
!!$
!!$          CALL fit_cubic(a,b,c,d,y1,f41,y2,f42,y3,f43,y4,f44)
!!$          f40=a*y**3+b*y**2+c*y+d
!!$
!!$          CALL fit_cubic(a,b,c,d,x1,f10,x2,f20,x3,f30,x4,f40)
!!$          findx=a*x**3+b*x**2+c*x+d
!!$
!!$          !Final result is an average over each direction
!!$          find2d=(findx+findy)/2.
!!$
!!$       END IF
!!$
!!$    ELSE
!!$
!!$       STOP 'FIND2D: order for interpolation not specified correctly'
!!$
!!$    END IF
!!$
!!$  END FUNCTION find2d

END PROGRAM HMX


