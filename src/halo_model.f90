PROGRAM halo_model

  IMPLICIT NONE

  ! Assigns the cosmological model
  CALL assign_cosmology(icosmo,cosm,verbose)
  CALL init_cosmology(cosm)
  CALL print_cosmology(cosm)

  ! Assign the halo model
  CALL assign_halomod(ihm,hmod,verbose)

  ! Set number of k points and k range (log spaced)
  nk=128
  kmin=1e-3
  kmax=1e2
  CALL fill_array(log(kmin),log(kmax),k,nk)
  k=exp(k)

  ! Set the scale factor and range (linearly spaced)
  !na=16
  !amin=0.2
  !amax=1.0
  !CALL fill_array(amin,amax,a,na)

  ! Set the number of redshifts and range (linearly spaced) and convert z -> a
  zmin=0.
  zmax=4.
  na=16
  CALL fill_array(zmin,zmax,a,na)
  DO i=1,na
     a(i)=scale_factor_z(a(i)) ! Note that this is correct because 'a' here is actually 'z'
  END DO

  field=field_dmonly
  CALL calculate_HMx(field,1,mmin,mmax,k,nk,a,na,pows_li,pows_2h,pows_1h,pows_hm,hmod,cosm,verbose,response=.FALSE.)

  base='data/power'
  CALL write_power_a_multiple(k,a,pows_li,pows_2h(1,1,:,:),pows_1h(1,1,:,:),pows_hm(1,1,:,:),nk,na,base,verbose)

END PROGRAM halo_model
