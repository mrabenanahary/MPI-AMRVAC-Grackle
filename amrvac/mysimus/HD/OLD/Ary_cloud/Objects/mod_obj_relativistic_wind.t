module mod_obj_relativistic_wind
use mod_constants
use mod_global_parameters
use mod_obj_global_parameters
use mod_obj_mat
use mod_physics
use mod_srmhd_parameters

implicit none

  ! the relativistic wind type

  type rel_wind_parameters
        character(len=20)    :: unit               !> physical unit at parameter file
        real(dp)             :: center(1:3)        !> wind -star center
        real(dp)             :: r_in               !> inner boundary wind position
        real(dp)             :: r_out_init         !> initial wind region
        real(dp)             :: r_out_impos        !> wind impose radion
        real(dp)             :: lfac               !> wind Lorentz factor
        real(dp)             :: velocity(1:3)      !> wind speed
        real(dp)             :: magnetic(1:3)      !> wind magnetic field
        real(dp)             :: power              !> wind power flux
        real(dp)             :: mass_flux          !> wind mass flux
        real(dp)             :: temperature_init   !> wind initial temperature
        real(dp)             :: pressure_init      !> wind initial pressure
        real(dp)             :: density_init       !> wind initial density
        real(dp)             :: number_density_init!> wind initial density
        real(dp)             :: time_start         !> wind starting time
        real(dp)             :: time_end           !> wind end time
        real(dp)             :: sigma0             !> wind assymetri
        real(dp)             :: xisigma0           !> wind magnetisation sigma
        real(dp)             :: beta               !> wind plasma Beta
        logical              :: tracer_on          !> tracer for the wind
  end type


  type rel_wind
    !Ref : Komissarov et Lyubarsky 2004,  Mon. Not. R. Astron. Soc. 349, 779–792 (2004)
    logical, allocatable      :: patch(:^D&)         !> wind is on cell
    logical, allocatable      :: patch_escape(:^D&)  !> wind is on cell
    type(rel_wind_parameters) :: myconfig            !> wind paramter to read
    character(len=78)         :: subname             !> subroutine name that call it
    contains
     PROCEDURE, PASS(self)    :: set_default     => usr_wind_set_default
     PROCEDURE, PASS(self)    :: set_complet     => usr_wind_set_complet
     PROCEDURE, PASS(self)    :: normalize       => usr_wind_normalize
     PROCEDURE, PASS(self)    :: set_w           => usr_wind_set_w
     PROCEDURE, PASS(thewind) :: read_parameters => usr_wind_read_p
     PROCEDURE, PASS(self)    :: write_setting   => usr_wind_write_setting
     PROCEDURE, PASS(self)    :: clean_memory    => usr_wind_clean_memory
     PROCEDURE, PASS(self)    :: spd_rad_to_cart => usr_wind_spd_rad_to_cart
  end type rel_wind
contains


!-------------------------------------------------------------------------
 !> Read the ism parameters  from a parfile
  subroutine usr_wind_read_p(thewind,wind_config,files)
    class(rel_wind)                    :: thewind
    character(len=*), intent(in)       :: files(:)
    type(rel_wind_parameters)          :: wind_config
    integer                            :: i_file
    namelist /usr_pulsar_wind_list/ wind_config

    if(mype==0)write(*,*)'Reading usr_wind_list'
    do i_file = 1, size(files)
       open(unitpar, file=trim(files(i_file)), status="old")
       read(unitpar, usr_pulsar_wind_list, end=112)
112    close(unitpar)
    end do


  end subroutine usr_wind_read_p

!------------------------------------------------------------------------
!> write the cloud setting
subroutine usr_wind_write_setting(self,unit_config)
  implicit none
  class(rel_wind)                     :: self
  integer,intent(in)                  :: unit_config
  ! .. local ..

  !-----------------------------------

  write(unit_config,*)'************************************'
  write(unit_config,*)'************WIND setting ************'
  write(unit_config,*)'************************************'
  write(unit_config,*) 'Density     = ', self%myconfig%density_init
  write(unit_config,*) 'Pressure    = ', self%myconfig%pressure_init
  write(unit_config,*) 'Temperature = ', self%myconfig%temperature_init
  write(unit_config,*) 'Speed       = ', self%myconfig%velocity
  write(unit_config,*)'************************************'
  write(unit_config,*)'******** END WIND setting **********'
  write(unit_config,*)'************************************'
end    subroutine usr_wind_write_setting
!--------------------------------------------------------------------

!> subroutine default setting for cloud
 subroutine usr_wind_set_default(self)
  implicit none
  class(rel_wind)          :: self
  !----------------------------------
  self%myconfig%unit                   = 'code'
  self%myconfig%density_init           = 0.0_dp
  self%myconfig%number_density_init    = 0.0_dp
  self%myconfig%mass_flux              = 0.0_dp
  self%myconfig%temperature_init       = 0.0_dp
  self%myconfig%pressure_init          = 0.0_dp
  self%myconfig%center(:)              = 0.0_dp!(box_limit(2,:)-box_limit(1,:))/2.0_dp
  self%myconfig%r_in                   = 0.0_dp!(box_limit(2,:)+box_limit(1,:))/2.0_dp
  self%myconfig%r_out_init             = 0.0_dp
  self%myconfig%r_out_impos            = 0.0_dp
  self%myconfig%velocity(:)            = 0.0_dp
  self%myconfig%magnetic(:)            = 0.0_dp
  self%myconfig%power                  = 0.0_dp
  self%myconfig%sigma0                 = 0.0_dp

  self%myconfig%tracer_on              = .false.

 end subroutine usr_wind_set_default
 !--------------------------------------------------------------------
 !> subroutine check the parfile setting for cloud
 subroutine usr_wind_set_complet(self,star_speed)
   implicit none
   class(rel_wind)          :: self
   real(dp), intent(in)     :: star_speed(1:3)
   ! .. local ..
   logical                  :: dust_is_frac
   real(dp)                 :: mp,kb,cloud_volume
   !-----------------------------------
   if(SI_unit) then
     mp=mp_SI
     kB=kB_SI
   else
     mp=mp_cgs
     kB=kB_cgs
   end if

   if (self%myconfig%lfac>0.0) then
     self%myconfig%velocity(r_)     = dsqrt(1.0_dp-1.0_dp&
                                            /self%myconfig%lfac**2.0_dp)
     self%myconfig%velocity(theta_) = 0.0_dp
     self%myconfig%velocity(phi_)   = 0.0_dp
     self%myconfig%velocity         = unit_velocity*self%myconfig%velocity
   else
    self%myconfig%lfac=1.0_dp / &
             dsqrt(1.0_dp-(sum(self%myconfig%velocity)/unit_velocity)**2.0_dp)
   end if



   if (dabs(self%myconfig%mass_flux)>smalldouble)then
    self%myconfig%density_init        = self%myconfig%mass_flux/(4.0_dp*dpi*     &
                               self%myconfig%r_in**2.0_dp *  &
                               dabs(self%myconfig%velocity(r_))*self%myconfig%lfac)
    self%myconfig%number_density_init = self%myconfig%density_init/mp
   else if(dabs(self%myconfig%power)>smalldouble) then

    self%myconfig%density_init        = self%myconfig%power/(4.0_dp*dpi*     &
                               self%myconfig%r_in**2.0_dp *  &
                               dabs(self%myconfig%velocity(r_))*self%myconfig%lfac)
    self%myconfig%number_density_init = self%myconfig%density_init/mp

  else if (dabs(self%myconfig%density_init)<smalldouble*mp)then
    self%myconfig%density_init        = self%myconfig%number_density_init*mp
    self%myconfig%mass_flux           = self%myconfig%density_init*4.0_dp*dpi*     &
                               self%myconfig%r_in**2.0_dp *  &
                               dabs(self%myconfig%velocity(r_))*self%myconfig%lfac
    self%myconfig%power           = self%myconfig%mass_flux
   else

    if (dabs(self%myconfig%number_density_init)<smalldouble*mp)then
      self%myconfig%number_density_init        = self%myconfig%density_init/mp
    end if

   end if

   if(dabs(self%myconfig%pressure_init)<smalldouble) then
    self%myconfig%pressure_init =self%myconfig%number_density_init*&
                                 kB*self%myconfig%temperature_init
   end if


 end subroutine usr_wind_set_complet
!--------------------------------------------------------------------
 subroutine usr_wind_normalize(self)
  implicit none
  class(rel_wind)          :: self
  !----------------------------------
  if(trim(self%myconfig%unit)=='code')return

  self%myconfig%density_init     = self%myconfig%density_init     /unit_density
  self%myconfig%temperature_init = self%myconfig%temperature_init /unit_temperature
  self%myconfig%pressure_init    = self%myconfig%pressure_init    /unit_pressure
  self%myconfig%velocity         = self%myconfig%velocity         /unit_velocity
  self%myconfig%magnetic         = self%myconfig%magnetic         /unit_magneticfield
  self%myconfig%center           = self%myconfig%center           /unit_length
  self%myconfig%r_in             = self%myconfig%r_in             /unit_length
  self%myconfig%r_out_impos      = self%myconfig%r_out_impos      /unit_length
  self%myconfig%r_out_init       = self%myconfig%r_out_init       /unit_length
  self%myconfig%power            = self%myconfig%power            /unit_user%luminosity
  self%myconfig%mass_flux        = self%myconfig%mass_flux        /unit_user%mass_flux
  self%myconfig%time_start       = self%myconfig%time_start       /unit_time
  self%myconfig%time_end         = self%myconfig%time_end         /unit_time

 end subroutine usr_wind_normalize
!--------------------------------------------------------------------
!--------------------------------------------------------------------
 !> subroutine patch for the cloud
 subroutine usr_wind_patch(ixI^L,ixO^L,qt,x,self)
  implicit none
  integer, intent(in)        :: ixI^L,ixO^L
  real(kind=dp), intent(in)  :: qt
  real(kind=dp), intent(in)  :: x(ixI^S,1:ndir)
  class(rel_wind)            :: self
  real(dp), dimension(ixI^S) :: dist
  !----------------------------------

  allocate(self%patch(ixG^T))

  call usr_distance(ixI^L,ixO^L,typeaxial,self%myconfig%center,x,dist)
  if(qt<=self%myconfig%time_start)then
   self%patch(ixO^S) = Dist(ixO^S) <self%myconfig%r_out_init &
                      .and. Dist(ixO^S) >self%myconfig%r_in
  else
   self%patch(ixO^S) = Dist(ixO^S) <self%myconfig%r_out_impos &
                       .and. Dist(ixO^S) >self%myconfig%r_in
  end if
  if(allocated(self%patch_escape))then
    self%patch(ixO^S) = self%patch(ixO^S).and.(.not.self%patch_escape(ixO^S))
  end if
 end subroutine usr_wind_patch
!--------------------------------------------------------------------
 !> subroutine setting for cloud
 subroutine usr_wind_set_w(ixI^L,ixO^L,qt,x,w,self)
  implicit none
  integer, intent(in)          :: ixI^L,ixO^L
  real(kind=dp), intent(in)    :: qt
  real(kind=dp)                :: x(ixI^S,1:ndir)
  real(kind=dp)                :: w(ixI^S,1:nw)
  class(rel_wind)              :: self
  ! .. local..
  integer                                :: idir
  real(kind=dp), dimension(ixI^S)        :: energy_flux,sqrB,kinetic_flux
  real(kind=dp), dimension(ixI^S,1:ndim) :: x_sphere
  !----------------------------------

  call usr_get_spherical(ixI^L,ixO^L,typeaxial,self%myconfig%center,x,x_sphere)
  call usr_wind_patch(ixI^L,ixO^L,qt,x,self)

  where(self%patch(ixO^S))
   energy_flux(ixO^S)      = self%myconfig%power/x_sphere(ixO^S,r_)**2.0_dp *&
                          (dsin(x_sphere(ixO^S,theta_))**2.0d0+one/self%myconfig%sigma0)

   w(ixO^S,mom(r_))        = self%myconfig%velocity(r_)
   w(ixO^S,mom(theta_))    = self%myconfig%velocity(theta_)
   w(ixO^S,mom(phi_))      = self%myconfig%velocity(phi_)
   w(ixO^S,lfac_)          = self%myconfig%lfac

   w(ixO^S,mag(r_))        = self%myconfig%magnetic(1)
   w(ixO^S,mag(theta_))    = self%myconfig%magnetic(2)
   w(ixO^S,mag(phi_))      = dsqrt(4.0_dp*dpi*self%myconfig%power)* &
                              self%myconfig%xisigma0/x_sphere(ixO^S,r_)  * &
                              dsin(x_sphere(ixO^S,theta_))*(1.0_dp-2.0_dp*x_sphere(ixO^S,theta_))



   sqrB(ixO^S)             = SUM(w(ixO^S,mag(1):mag(ndir))**2.0_dp,dim=ndim+1)
   kinetic_flux(ixO^S)     = energy_flux(ixO^S)-  sqrB(ixO^S)/(4.0_dp*dpi)

   w(ixO^S,rho_)           = kinetic_flux(ixO^S)/(w(ixO^S,lfac_)*w(ixO^S,mom(r_)))

   w(ixO^S,p_)             = max(self%myconfig%beta*half*sqrB(ixO^S),&
                             1.0d-2*w(ixO^S,rho_),1.0d4*small_pressure)

 end where

  if(trim(typeaxial)/='spherical')call self%spd_rad_to_cart(ixI^L,ixO^L,x,w)


  cond_tracer_on :if(self%myconfig%tracer_on.and.phys_n_tracer>0&
                    .and.itr<=phys_n_tracer)then
   where(self%patch(ixO^S))
    w(ixO^S,tracer(itr)) = w(ixO^S,rho_)
   elsewhere
    w(ixO^S,tracer(itr)) = 0.0_dp
   end where
   itr=itr+1
  end if cond_tracer_on



 end subroutine usr_wind_set_w


!===========================================================
!> Subroutine to convert radial wind from spherical to cartesian coordinates
subroutine usr_wind_spd_rad_to_cart(ixI^L,ixO^L,x,w,self)
  use mod_global_parameters
  implicit none
  integer, intent(in)             :: ixI^L,ixO^L
  real(kind=dp), intent(in)       :: x(ixI^S,1:ndir)
  real(kind=dp), intent(inout)    :: w(ixI^S,1:nw)
  class(rel_wind)                 :: self
  ! .. local ..
  real(kind=dp), dimension(ixI^S,1:ndir) :: v_spherical
  real(kind=dp), dimension(ixI^S)        :: sin_theta,cos_theta
  real(kind=dp), dimension(ixI^S)        :: sin_phi,cos_phi
  real(kind=dp), dimension(ixI^S)        :: Dist
  !--------------------------------------------------

  call usr_distance(ixI^L,ixO^L,typeaxial,self%myconfig%center,x,dist)

 select case(typeaxial)
  case('slab')
    v_spherical(ixO^S,1:ndir) = w(ixO^S,mom(1):mom(ndir))
   if(z_in) then
     sin_theta(ixO^S)=dsqrt(x(ixO^S,x_)**2.0_dp+x(ixO^S,y_)**2.0_dp)/Dist(ixO^S)
     cos_theta(ixO^S)=x(ixO^S,z_)/Dist(ixO^S)
   else
    sin_theta(ixO^S)=1.0_DP
    cos_theta(ixO^S)=0.0_dp
   end if
   if(y_in) then
     sin_phi(ixO^S)=dsin(x(ixO^S,phi_))
     cos_phi(ixO^S)=dcos(x(ixO^S,phi_))
   else
    sin_phi(ixO^S)=0.0_DP
    cos_phi(ixO^S)=1.0_dp
   end if
   where(self%patch(ixO^S))
    w(ixO^S,mom(x_)) = v_spherical(ixO^S,r_)*cos_phi(ixO^S)*sin_theta(ixO^S)

    where(sin_phi(ixO^S)>0.0_dp)
     w(ixO^S,mom(y_)) = v_spherical(ixO^S,r_)*sin_phi(ixO^S)*sin_theta(ixO^S)
    else where
     w(ixO^S,mom(y_)) = zero
    end where
    where(cos_phi(ixO^S)>0.0_dp)
     w(ixO^S,mom(z_)) = v_spherical(ixO^S,r_)*cos_theta(ixO^S)
    else where
     w(ixO^S,mom(z_)) = zero
    end where

   end where
  case('cylindrical')
    v_spherical(ixO^S,1:ndir) = w(ixO^S,mom(1):mom(ndir))
   if(z_in) then
     where(Dist(ixO^S)>0)
      sin_theta(ixO^S)=x(ixO^S,r_)/Dist(ixO^S)
      cos_theta(ixO^S)=x(ixO^S,z_)/Dist(ixO^S)
     elsewhere
      sin_theta(ixO^S)=1.0_DP
      cos_theta(ixO^S)=0.0_dp
     endwhere
   else
    sin_theta(ixO^S)=1.0_DP
    cos_theta(ixO^S)=0.0_dp
   end if

   if(phi_in) then
     sin_phi(ixO^S)=dsin(x(ixO^S,phi_))
     cos_phi(ixO^S)=dcos(x(ixO^S,phi_))
   else
    sin_phi(ixO^S)=0.0_DP
    cos_phi(ixO^S)=1.0_dp
   end if

   where(self%patch(ixO^S))
    w(ixO^S,mom(r_)) = v_spherical(ixO^S,r_)*cos_phi(ixO^S)*sin_theta(ixO^S)

    ! where(sin_phi(ixO^S)>0.0_dp)
    !  w(ixO^S,mom(y_)) = w(ixO^S,mom(r_))*sin_phi(ixO^S)*sin_theta(ixO^S)
    ! else where
    !  w(ixO^S,mom(y_)) = zero
    ! end where
    where(cos_phi(ixO^S)>0.0_dp)
     w(ixO^S,mom(z_)) = v_spherical(ixO^S,r_)*cos_theta(ixO^S)*cos_phi(ixO^S)
    else where
     w(ixO^S,mom(z_)) = zero
    end where

   end where

  case('spherical')
  ! Dummy
  case default
  write(*,*) ' is not implimented '
  call mpistop(' stop at amrvacusr.t  et user_getcartesianV')
 end select
end subroutine usr_wind_spd_rad_to_cart

!--------------------------------------------------------------------
!> Subroutine to clean array memory of associated with cloud object
subroutine usr_wind_clean_memory(self)
  class(rel_wind)    :: self
  if(allocated(self%patch_escape))deallocate(self%patch_escape)
  if(allocated(self%patch))deallocate(self%patch)
end subroutine usr_wind_clean_memory
!--------------------------------------------------------------------

end module mod_obj_relativistic_wind