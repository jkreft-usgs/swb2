!> @file
!>  Main program which references all other modules; execution begins here.


!>  Main program which references all other modules; execution begins here.
!>
!> Accepts command-line arguments and makes a single call
!> to the control_setModelOptions routine in module \ref control.
program main

  use iso_c_binding, only    : c_short, c_int, c_float, c_double, c_bool
  use logfiles, only         : LOGS, LOG_DEBUG
  use model_initialize, only : initialize_all, read_control_file
  use model_domain, only     : MODEL
  use model_iterate, only    : iterate_over_simulation_days
  use version_control, only  : SWB_VERSION, GIT_COMMIT_HASH_STRING, &
                               GIT_BRANCH_STRING, COMPILE_DATE, COMPILE_TIME
  use string_list, only      : STRING_LIST_T
  use iso_fortran_env

  implicit none

  type (STRING_LIST_T)           :: slControlFiles

  character (len=256)            :: sBuf
  character (len=:), allocatable :: sOutputPrefixName
  character (len=:), allocatable :: sOutputDirectoryName
  character (len=:), allocatable :: sDataDirectoryName
  integer (kind=c_int)           :: iNumArgs
  character (len=1024)           :: sCompilerFlags
  character (len=256)            :: sCompilerVersion
  character (len=256)            :: sVersionString
  character (len=256)            :: sGitHashString
  integer (kind=c_int)           :: iCount
  integer (kind=c_int)           :: iIndex
  integer (kind=c_int)           :: iLen

  sOutputPrefixName    = ""
  sOutputDirectoryName = ""
  sDataDirectoryName   = ""

  iNumArgs = COMMAND_ARGUMENT_COUNT()

  sVersionString = "  Soil Water Balance Code version "//trim( SWB_VERSION )    &
      //" -- compiled on: "//trim(COMPILE_DATE)//" "//trim(COMPILE_TIME)

  sGitHashString = "    [ Git branch and commit hash: "//trim( GIT_BRANCH_STRING )    &
     //", "//trim( GIT_COMMIT_HASH_STRING )//" ]"

  iCount = max( len_trim( sVersionString ), len_trim( sGitHashString ) )

  write(unit=*, fmt="(/,a)") repeat("-",iCount + 2)  
  write(UNIT=*,FMT="(a)") trim( sVersionString )
  write(UNIT=*,FMT="(a)") trim( sGitHashString )  
  write(unit=*, fmt="(a,/)") repeat("-",iCount + 2)  

  if(iNumArgs == 0 ) then

#ifdef __GFORTRAN__
    sCompilerFlags = COMPILER_OPTIONS()
    sCompilerVersion = COMPILER_VERSION()
    write(UNIT=*,FMT="(a,/)") "Compiled with: gfortran ("//TRIM(sCompilerVersion)//")"
    write(UNIT=*,FMT="(a)") "Compiler flags:"
    write(UNIT=*,FMT="(a)") "-------------------------------"
    write(UNIT=*,FMT="(a,/)") TRIM(sCompilerFlags)
#endif

#ifdef __INTEL_COMPILER
    write(UNIT=*,FMT="(a)") "Compiled with: Intel Fortran version " &
      //TRIM(int2char(__INTEL_COMPILER))
      write(UNIT=*,FMT="(a,/)") "Compiler build date:"//TRIM(int2char(__INTEL_COMPILER_BUILD_DATE))
#endif

#ifdef __G95__
    write(UNIT=*,FMT="(a,/)") "Compiled with: G95 minor version " &
      //TRIM(int2char(__G95_MINOR__))
#endif

    write(UNIT=*,FMT="(/,/,a,/,a,/,a,/)")  "Usage: swb2 [control file name] [--output_prefix=][--output_dir=][--data_dir=]", &
                                           "                                ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~", &
                                           "                                                   (optional)"
    stop

  end if

  do iIndex=1, iNumArgs

    call GET_COMMAND_ARGUMENT( iIndex, sBuf )

    if ( sBuf(1:13) .eq. "--output_dir=" ) then

      sOutputDirectoryName = trim( sBuf(14:) )
      iLen = len_trim( sOutputDirectoryName )

      ! if there is no trailing "/", append one so we can form (more) fully 
      ! qualified filenames later
      if ( .not. sOutputDirectoryName(iLen:iLen) .eq. "/" )  &
        sOutputDirectoryName = trim(sOutputDirectoryName)//"/"

      call LOGS%set_output_directory( sOutputDirectoryName )

    elseif ( sBuf(1:16) .eq. "--output_prefix=" ) then

      sOutputPrefixName = trim( sBuf(17:) )
      iLen = len_trim( sOutputPrefixName )

    elseif ( sBuf(1:11) .eq. "--data_dir=" ) then

      sDataDirectoryName = sBuf(12:)
      iLen = len_trim( sDataDirectoryName )

      ! if there is no trailing "/", append one so we can form (more) fully 
      ! qualified filenames later
      if ( .not. sDataDirectoryName(iLen:iLen) .eq. "/" )  &
        sDataDirectoryName = trim(sDataDirectoryName)//"/"

    else

      ! no match on the command-line argument flags; this must be a control file
      call slControlFiles%append( trim( sBuf ) )

    endif

  enddo 
 
  ! open and initialize logfiles
  call LOGS%initialize( iLogLevel = LOG_DEBUG )
  call LOGS%write( sMessage='Base data directory name set to: "'//trim( sDataDirectoryName )//'"', &
                   lEcho=.TRUE._c_bool )
  call LOGS%write( sMessage='Output file prefix set to: "'//trim( sOutputPrefixName )//'"', &
                   lEcho=.TRUE._c_bool )

  do iIndex=1, slControlFiles%count

    ! read control file
    call read_control_file( slControlFiles%get( iIndex ) )

  enddo  

  call slControlFiles%clear()

  call initialize_all( sOutputPrefixName, sOutputDirectoryName, sDataDirectoryName )

  call iterate_over_simulation_days( MODEL )
   
  call LOGS%close()

end program main
