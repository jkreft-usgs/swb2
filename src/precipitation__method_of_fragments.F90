!> @file
!! Contains the module @ref precipitation__method_of_fragments.

!>
!!  Module @ref precipitation__method_of_fragments
!!  provides support for creating synthetic daily precipitation
!!  given grids of monthly sum precipitation and a "fragments" file.
!!  The fragments file is generated from observations at discrete locations, 
!!  the values of which range from 0 to 1, and the sum of which is 1.
!!  The fragment value is simply the daily observed precipitation value divided
!!  by the monthly sum of all observed precipitation values for that station.
!!
!!  In addition, this routine accepts another set of rainfall adjustment grids, 
!!  needed in order to ensure the resulting precipitation totals fall in line with 
!!  other published values, in the development case, the Rainfall Atlas of Hawaii. 

module precipitation__method_of_fragments

  use iso_c_binding
  use constants_and_conversions, only  : asInt, asFloat, lTRUE, lFALSE
  use data_catalog
  use data_catalog_entry
  use dictionary
  use exceptions
  use file_operations
  use logfiles, only            : LOGS, LOG_ALL, LOG_DEBUG
  use parameters
  use strings
  use string_list
  use simulation_datetime
  use grid
  implicit none

  private

  public :: precipitation_method_of_fragments_initialize
  public :: read_daily_fragments
  public :: precipitation_method_of_fragments_calculate

  !> Module variable that holds the rainfall gage (zone) number
  integer (kind=c_int), allocatable, public :: RAIN_GAGE_ID(:)

  !> Module variable that holds the current day's rainfall fragment value
  real (kind=c_float), allocatable, public  :: FRAGMENT_VALUE(:)

  !> Module variable indicating which "simulation number" is active
  !! Only has meaning if the rainfall fragments are being applied via a predetermined
  !! sequence file
  integer (kind=c_int), public :: SIMULATION_NUMBER = 1

  !> Module variable that holds the rainfall adjustment factor
  real (kind=c_float), allocatable, public  :: RAINFALL_ADJUST_FACTOR(:)

  !> Module variable that holds a sequence of random numbers associated with the selection
  !! of the fragment set to use
  real (kind=c_float), allocatable :: RANDOM_VALUES(:)

  !> Module level variable used to create subsets of the FRAGMENT_SEQUENCES file
  logical (kind=c_bool), allocatable :: SEQUENCE_SELECTION(:)

  !> Module variable detemining whether fragment sequences are chosen at random or
  !! selected from an external file
  logical (kind=c_bool) :: RANDOM_FRAGMENT_SEQUENCES = .true._c_bool

  !> Data structure that holds a single line of data from the input rainfall fragments file.
  type, public :: FRAGMENTS_T
    integer (kind=c_int) :: iMonth
    integer (kind=c_int) :: iRainGageZone
    integer (kind=c_int) :: iFragmentSet
    real (kind=c_float)  :: fFragmentValue(31)
  end type FRAGMENTS_T

  !> Pointer to a rainfall fragments data structure.
  type, public :: PTR_FRAGMENTS_T
    type (FRAGMENTS_T), pointer  :: pFragment => null()
  end type PTR_FRAGMENTS_T

  !> Data structure to hold the current active rainfall fragments for
  !! a particular rain gage zone.
  type, public :: FRAGMENTS_SET_T
    integer (kind=c_int) :: iRainGageZone
    integer (kind=c_int) :: iNumberOfFragments(12)
    integer (kind=c_int) :: iStartRecord(12)
  end type FRAGMENTS_SET_T

  !> Array of all fragments read in from the rainfall fragments file.
  type (FRAGMENTS_T), allocatable, target, public       :: FRAGMENTS(:)

  !> Subset of rainfall fragments file pointing to the currently active fragments.
  type (PTR_FRAGMENTS_T), allocatable                   :: CURRENT_FRAGMENTS(:)
  
  !> Array of fragments sets; fragments sets include indices to the start record
  !! associated with the fragment for each month
  type (FRAGMENTS_SET_T), allocatable, public           :: FRAGMENTS_SETS(:)

  !> Data structure to hold static (pre-calculated) fragment selection numbers
  type, public :: FRAGMENTS_SEQUENCE_T
    integer (kind=c_int) :: sim_number
    integer (kind=c_int) :: sim_month
    integer (kind=c_int) :: sim_rainfall_zone    
    integer (kind=c_int) :: sim_year
    real (kind=c_float)  :: sim_random_number
    integer (kind=c_int) :: sim_selected_set
  end type FRAGMENTS_SEQUENCE_T

  !> Pointer to all or some of the FRAGMENTS_SEQUENCE array
  type ( FRAGMENTS_SEQUENCE_T ), pointer :: pFRAGMENTS_SEQUENCE

  !> Array of fragment sequence sets
  type (FRAGMENTS_SEQUENCE_T), allocatable, public  :: FRAGMENTS_SEQUENCE(:)

  type (DATA_CATALOG_ENTRY_T), pointer :: pRAINFALL_ADJUST_FACTOR      

  integer (kind=c_int) :: LU_FRAGMENTS_ECHO

contains

  !> Initialize method of fragments.
  !!
  !! This routine accesses the "RAINFALL_ZONE" gridded data object and 
  !! calls the routine to read in the rainfall fragments file. Values of RAINFALL_ZONE are stored
  !! in a module variable @ref RAIN_GAGE_ID for future reference.
  !!
  !! @params[in]   lActive   2-D boolean array defining active and inactive cells

  subroutine precipitation_method_of_fragments_initialize( lActive )

    logical (kind=c_bool), intent(in)     :: lActive(:,:)

    ! [ LOCALS ]
    integer (kind=c_int)                 :: iStat
    type (DATA_CATALOG_ENTRY_T), pointer :: pRAINFALL_ZONE
    type (STRING_LIST_T)                 :: slString
    integer (kind=c_int)                 :: iMaxRainZones
    integer (kind=c_int), allocatable    :: iSimulationNumbers(:)

    ! look up the simulation number associated with the desired fragment sequence set
    call CF_DICT%get_values( sKey="FRAGMENTS_SEQUENCE_SIMULATION_NUMBER", iValues=iSimulationNumbers )
    if ( iSimulationNumbers(1) > 0 )  SIMULATION_NUMBER = iSimulationNumbers(1)

    ! locate the data structure associated with the gridded rainfall zone entries
    pRAINFALL_ZONE => DAT%find("RAINFALL_ZONE")
    if ( .not. associated(pRAINFALL_ZONE) ) &
        call die("A RAINFALL_ZONE grid must be supplied in order to make use of this option.",    &
          __SRCNAME__, __LINE__)

    allocate( RAIN_GAGE_ID( count(lActive) ), stat=iStat )
    call assert( iStat == 0, "Problem allocating memory", __SRCNAME__, __LINE__ )
 
    call pRAINFALL_ZONE%getvalues()
 
    ! map the 2D array of RAINFALL_ZONE values to the vector of active cells
    RAIN_GAGE_ID = pack( pRAINFALL_ZONE%pGrdBase%iData, lActive )

    allocate( RAINFALL_ADJUST_FACTOR( count(lActive) ), stat=iStat )
    call assert( iStat == 0, "Problem allocating memory", __SRCNAME__, __LINE__ )

    allocate( FRAGMENT_VALUE( count(lActive) ), stat=iStat )
    call assert( iStat == 0, "Problem allocating memory", __SRCNAME__, __LINE__ )


    ! look up the name of the fragments file in the control file dictionary
    call CF_DICT%get_values( sKey="FRAGMENTS_DAILY_FILE", slString=slString )

    ! use the first entry in the string list slString as the filename to open for
    ! use with the daily fragments routine
    call read_daily_fragments( slString%get(1) )
    call slString%clear()

    ! look up the name of the fragments SEQUENCE file in the control file dictionary
    call CF_DICT%get_values( sKey="FRAGMENTS_SEQUENCE_FILE", slString=slString )
   
    if ( .not. ( slString%get(1) .strequal. "<NA>" ) )  then
      call read_fragments_sequence( slString%get(1) )
      RANDOM_FRAGMENT_SEQUENCES = .false._c_bool
      allocate ( SEQUENCE_SELECTION( count(FRAGMENTS_SEQUENCE%sim_month > 0) ), stat=iStat )
      call assert( iStat == 0, "Problem allocating memory", __SRCNAME__, __LINE__ )      
    endif  

    !> Now the fragments file is in memory. Create an ancillary data structure
    !> to keep track of which records correspond to various rain zones

    iMaxRainZones = maxval(FRAGMENTS%iRainGageZone)

    allocate ( FRAGMENTS_SETS( iMaxRainZones ), stat=iStat )
    call assert( iStat == 0, "Problem allocating memory", __SRCNAME__, __LINE__ )

    allocate (CURRENT_FRAGMENTS( iMaxRainZones ), stat=iStat )
    call assert( iStat == 0, "Problem allocating memory", __SRCNAME__, __LINE__ )

    allocate (RANDOM_VALUES( iMaxRainZones ), stat=iStat )
    call assert( iStat == 0, "Problem allocating memory", __SRCNAME__, __LINE__ )

    call process_fragment_sets()

    open( newunit=LU_FRAGMENTS_ECHO, file="Fragments_as_implemented_by_SWB.csv")
    write( LU_FRAGMENTS_ECHO, fmt="(a, 30('fragment, '),'fragment')")                 &
        "Index, Month, Rain_Zone, Year, Random Number, Fragment_Set,"

  end subroutine precipitation_method_of_fragments_initialize

!--------------------------------------------------------------------------------------------------

  subroutine process_fragment_sets()

    integer (kind=c_int)   :: iCount
    integer (kind=c_int)   :: iIndex
    integer (kind=c_int)   :: iRainGageZone 
    integer (kind=c_int)   :: iPreviousRainGageZone   
    integer (kind=c_int)   :: iFragmentChunk
    integer (kind=c_int)   :: iMonth
    integer (kind=c_int)   :: iPreviousMonth
    character (len=10)     :: sBuf0
    character (len=10)     :: sBuf1
    character (len=12)     :: sBuf2
    character (len=10)     :: sBuf3
    character (len=52)     :: sBuf4

    ! this counter is used to accumulate the number of fragments associated with the 
    ! current raingage zone/month combination
    iCount = 0 

    iRainGageZone = FRAGMENTS( lbound( FRAGMENTS, 1) )%iRainGageZone
    iPreviousRainGageZone = iRainGageZone
    iPreviousMonth = FRAGMENTS( lbound( FRAGMENTS, 1) )%iMonth

    ! populate the first record of FRAGMENT_SETS
    FRAGMENTS_SETS( iRainGageZone )%iRainGageZone = iRainGageZone
    FRAGMENTS_SETS( iRainGageZone )%iStartRecord(iPreviousMonth) = lbound( FRAGMENTS, 1)

    
    ! now iterate through *all* fragments, keeping track of the starting record for each new rainfall gage 
    ! zone number
    do iIndex = lbound( FRAGMENTS, 1) + 1, ubound( FRAGMENTS, 1 )
 
      iRainGageZone = FRAGMENTS(iIndex)%iRainGageZone
      iMonth = FRAGMENTS(iIndex)%iMonth

      iCount = iCount + 1

      if ( iRainGageZone /= iPreviousRainGageZone ) then
        
        FRAGMENTS_SETS( iPreviousRainGageZone )%iNumberOfFragments(iPreviousMonth) = iCount
        FRAGMENTS_SETS( iRainGageZone )%iRainGageZone = iRainGageZone
        FRAGMENTS_SETS( iRainGageZone )%iStartRecord(iMonth) = iIndex   
        ! need to handle the last fragment set as a special case
        FRAGMENTS_SETS( iRainGageZone )%iNumberOfFragments(iMonth) = iCount
        iCount = 0

      endif
      
      iPreviousMonth = iMonth
      iPreviousRainGageZone = iRainGageZone  

    enddo  

    call LOGS%write("### Summary of fragment sets in memory ###", &
       iLogLevel=LOG_ALL, iLinesBefore=1, iLinesAfter=1, lEcho=lFALSE )
    call LOGS%write("gage number | month      | start index  | num records ")
    call LOGS%write("----------- | ---------- | ------------ | ------------")
    do iIndex=1, ubound( FRAGMENTS_SETS, 1)
      do iMonth=1,12
        write (sBuf0, fmt="(i10)") iIndex
        write (sBuf1, fmt="(i10)") iMonth
        write (sBuf2, fmt="(i12)") FRAGMENTS_SETS(iIndex)%iStartRecord(iMonth)
        write (sBuf3, fmt="(i10)") FRAGMENTS_SETS(iIndex)%iNumberOfFragments(iMonth)
        write (sBuf4, fmt="(a10,'  | ', a10,' | ', a12,' | ',a10)") adjustl(sBuf0),     &
               adjustl(sBuf1), adjustl(sBuf2), adjustl(sBuf3)
        call LOGS%write( sBuf4 )
      enddo  
    end do

  end subroutine process_fragment_sets

!--------------------------------------------------------------------------------------------------

  subroutine read_daily_fragments( sFilename )

    character (len=*), intent(in)    :: sFilename

    ! [ LOCALS ]
    character (len=512)   :: sRecord, sSubstring
    integer (kind=c_int)  :: iStat
    integer (kind=c_int)  :: iCount
    integer (kind=c_int)  :: iIndex
    integer (kind=c_int)  :: iNumLines  
    real (kind=c_float)   :: fTempValue
    type (ASCII_FILE_T)   :: FRAGMENTS_FILE


    call FRAGMENTS_FILE%open( sFilename = sFilename,         &
                              sCommentChars = "#%!",         &
                              sDelimiters = "WHITESPACE",    &
                              lHasHeader = .false._c_bool )

    iNumLines = FRAGMENTS_FILE%numLines()

    allocate(  FRAGMENTS( iNumLines ), stat=iStat )
    call assert( iStat == 0, "Problem allocating memory for fragments table", __SRCNAME__, __LINE__ )

    iCount = 0

    do 

      ! read in next line of file
      sRecord = FRAGMENTS_FILE%readLine()

      if ( FRAGMENTS_FILE%isEOF() ) exit 

      iCount = iCount + 1

      ! read in month number
      call chomp(sRecord, sSubstring, FRAGMENTS_FILE%sDelimiters )

      if ( len_trim(sSubstring) == 0 )                                    &
        call die( "Missing month number in the daily fragments file",     &
          __SRCNAME__, __LINE__, "Problem occured on line number "        &
          //asCharacter(FRAGMENTS_FILE%currentLineNum() )                 &
          //" of file "//dquote(sFilename) )

      FRAGMENTS(iCount)%iMonth = asInt(sSubString)

      ! read in rain gage zone
      call chomp(sRecord, sSubstring, FRAGMENTS_FILE%sDelimiters )

      if ( len_trim(sSubstring) == 0 )                                         &
        call die( "Missing rain gage zone number in the daily fragments file", &
          __SRCNAME__, __LINE__, "Problem occured on line number "             &
          //asCharacter(FRAGMENTS_FILE%currentLineNum() )                      &
          //" of file "//dquote(sFilename) )

      FRAGMENTS(iCount)%iRainGageZone = asInt(sSubString)

      ! read in fragment set number for this zone
      call chomp(sRecord, sSubstring, FRAGMENTS_FILE%sDelimiters )

      if ( len_trim(sSubstring) == 0 )                                         &
        call die( "Missing fragment set number in the daily fragments file",   &
          __SRCNAME__, __LINE__, "Problem occured on line number "             &
          //asCharacter(FRAGMENTS_FILE%currentLineNum() )                      &
          //" of file "//dquote(sFilename) )

      FRAGMENTS(iCount)%iFragmentSet = asInt(sSubString)
      
      do iIndex = 1, 31

        ! read in fragment for given day of month
        call chomp(sRecord, sSubstring, FRAGMENTS_FILE%sDelimiters )

        if ( len_trim(sSubstring) == 0 )                                       &
          call die( "Missing fragment value in the daily fragments file",      &
            __SRCNAME__, __LINE__, "Problem occured on line number "           &
            //asCharacter(FRAGMENTS_FILE%currentLineNum() )                    &
            //" of file "//dquote(sFilename) )

        fTempValue = asFloat( sSubstring )

        ! This substitution is needed to prevent "-9999" or "9999" values embedded in the fragments file
        ! from creeping into calculations. In the event of a "9999", the appropriate substitution is
        ! zero, since the previous fragments for the month to this point should already sum to 1.0
        if ( ( fTempValue < 0.0_c_float ) .or. ( fTempValue > 1.0_c_float ) ) then
          FRAGMENTS(iCount)%fFragmentValue(iIndex) = 0.0_c_float
        else
          FRAGMENTS(iCount)%fFragmentValue(iIndex) = fTempValue          
        endif          

      enddo
      
    enddo    

    call LOGS%write("Maximum rain gage zone number: "//asCharacter(maxval(FRAGMENTS%iRainGageZone)), &
      iTab=31, iLinesAfter=1, iLogLevel=LOG_ALL)

  end subroutine read_daily_fragments

!--------------------------------------------------------------------------------------------------

  subroutine read_fragments_sequence( sFilename )

    character (len=*), intent(in)    :: sFilename

    ! [ LOCALS ]
    character (len=512)   :: sRecord, sSubstring
    integer (kind=c_int)  :: iStat
    integer (kind=c_int)  :: iCount
    integer (kind=c_int)  :: iIndex
    integer (kind=c_int)  :: iNumLines  
    type (ASCII_FILE_T)   :: SEQUENCE_FILE
    character (len=10)     :: sBuf0
    character (len=10)     :: sBuf1
    character (len=12)     :: sBuf2
    character (len=10)     :: sBuf3
    character (len=10)     :: sBuf4
    character (len=256)     :: sBuf5    
    type (STRING_LIST_T)   :: slHeader


    call SEQUENCE_FILE%open( sFilename = sFilename,         &
                             sCommentChars = "#%!",         &
                             sDelimiters = "WHITESPACE",    &
                             lHasHeader = .true._c_bool )

    slHeader = SEQUENCE_FILE%readHeader()

    iNumLines = SEQUENCE_FILE%numLines()

    allocate(  FRAGMENTS_SEQUENCE( iNumLines ), stat=iStat )
    call assert( iStat == 0, "Problem allocating memory for fragments sequence table",    &
      __SRCNAME__, __LINE__ )

    iCount = 0

    do 

      ! read in next line of file
      sRecord = SEQUENCE_FILE%readLine()

      if ( SEQUENCE_FILE%isEOF() ) exit 

      iCount = iCount + 1

      ! read in simulation number
      call chomp(sRecord, sSubstring, SEQUENCE_FILE%sDelimiters )

      if ( len_trim(sSubstring) == 0 )                                              &
          call die( "Missing simulation number in the fragments sequence file",     &
            __SRCNAME__, __LINE__, "Problem occured on line number "                &
            //asCharacter(SEQUENCE_FILE%currentLineNum() )                          &
            //" of file "//dquote(sFilename) )

      FRAGMENTS_SEQUENCE(iCount)%sim_number = asInt(sSubString)

      ! read in month
      call chomp(sRecord, sSubstring, SEQUENCE_FILE%sDelimiters )

      if ( len_trim(sSubstring) == 0 )                                              &
        call die( "Missing month number in the fragments sequence file",            &
          __SRCNAME__, __LINE__, "Problem occured on line number "                  &
          //asCharacter(SEQUENCE_FILE%currentLineNum() )                            &
          //" of file "//dquote(sFilename) )

      FRAGMENTS_SEQUENCE(iCount)%sim_month = asInt(sSubString)

      ! read in rainfall zone
      call chomp(sRecord, sSubstring, SEQUENCE_FILE%sDelimiters )

      if ( len_trim(sSubstring) == 0 )                                              &
        call die( "Missing rainfall zone number in the fragments sequence file",    &
          __SRCNAME__, __LINE__, "Problem occured on line number "                  &
          //asCharacter(SEQUENCE_FILE%currentLineNum() )                            &
          //" of file "//dquote(sFilename) )

      FRAGMENTS_SEQUENCE(iCount)%sim_rainfall_zone = asInt(sSubString)
      

      ! read in sim_year
      call chomp(sRecord, sSubstring, SEQUENCE_FILE%sDelimiters )

      if ( len_trim(sSubstring) == 0 )                                              &
        call die( "Missing year number in the fragments sequence file",             &
          __SRCNAME__, __LINE__, "Problem occured on line number "                  &
          //asCharacter(SEQUENCE_FILE%currentLineNum() )                            &
          //" of file "//dquote(sFilename) )

      FRAGMENTS_SEQUENCE(iCount)%sim_year = asInt(sSubString)

      ! read in sim_random_number
      call chomp(sRecord, sSubstring, SEQUENCE_FILE%sDelimiters )

      if ( len_trim(sSubstring) == 0 )                                                   &
        call die( "Missing simulation random number in the fragments sequence file",     &
          __SRCNAME__, __LINE__, "Problem occured on line number "                       &
          //asCharacter(SEQUENCE_FILE%currentLineNum() )                                 &
          //" of file "//dquote(sFilename) )

      FRAGMENTS_SEQUENCE(iCount)%sim_random_number = asFloat(sSubString)

      ! read in simulation selected set
      call chomp(sRecord, sSubstring, SEQUENCE_FILE%sDelimiters )

      if ( len_trim(sSubstring) == 0 )                                                   &
        call die( "Missing selected fragment set number in the fragments sequence file", &
          __SRCNAME__, __LINE__, "Problem occured on line number "                       &
          //asCharacter(SEQUENCE_FILE%currentLineNum() )                                 &
          //" of file "//dquote(sFilename) )

      FRAGMENTS_SEQUENCE(iCount)%sim_selected_set = asInt(sSubString)

    enddo

    call LOGS%write("### Summary of fragment sequence sets in memory ###", &
       iLogLevel=LOG_ALL, iLinesBefore=1, iLinesAfter=1, lEcho=lFALSE )
    call LOGS%write("sim number | rainfall zone   | month  | year   | selected set ")
    call LOGS%write("----------- | ---------- | ------------ | ------------|------------")
    do iIndex=1, ubound( FRAGMENTS_SEQUENCE, 1)
      write (sBuf0, fmt="(i10)") FRAGMENTS_SEQUENCE( iIndex )%sim_number
      write (sBuf1, fmt="(i10)") FRAGMENTS_SEQUENCE( iIndex )%sim_rainfall_zone
      write (sBuf2, fmt="(i12)") FRAGMENTS_SEQUENCE( iIndex )%sim_month
      write (sBuf3, fmt="(i10)") FRAGMENTS_SEQUENCE( iIndex )%sim_year
      write (sBuf4, fmt="(i10)") FRAGMENTS_SEQUENCE( iIndex )%sim_selected_set

      write (sBuf5, fmt="(a,'  | ', a,'  |  ', a,'  |  ',a,'  |  ',a)")                        &
        adjustl(sBuf0), adjustl(sBuf1), adjustl(sBuf2), adjustl(sBuf3), adjustl(sBuf4)
      call LOGS%write( trim( sBuf5 ) )
    end do

  end subroutine read_fragments_sequence

!--------------------------------------------------------------------------------------------------
  
  !> Update rainfall fragments on daily basis.
  !!
  !! If called when lShuffle is TRUE:
  !! 1) update random values
  !! 2) random values are used to select the next active fragment set
  !!    for the current RainGageZone
  !!
  !! *Each* time the routine is called, the appropriate fragment is 
  !! selected from the current active fragement set and is assigned
  !! to all cells that share a common RainGageZone

  subroutine update_fragments( lShuffle )

    logical (kind=c_bool), intent(in) :: lShuffle

    ! [ LOCALS ]
    integer (kind=c_int) :: iIndex
    integer (kind=c_int) :: iMaxRainZones
    integer (kind=c_int) :: iMonth
    integer (kind=c_int) :: iDay
    integer (kind=c_int) :: iYearOfSimulation

    integer (kind=c_int) :: iNumberOfFragments
    integer (kind=c_int)  :: iStartRecord
    integer (kind=c_int) :: iEndRecord
    integer (kind=c_int) :: iTargetRecord
    integer (kind=c_int) :: iStat
    integer (kind=c_int) :: iUBOUND_FRAGMENTS
    integer (kind=c_int) :: iUBOUND_CURRENT_FRAGMENTS
    character (len=512)  :: sBuf


    iMaxRainZones = maxval(FRAGMENTS%iRainGageZone)
    iMonth = SIM_DT%curr%iMonth
    iDay = SIM_DT%curr%iDay
    iYearOfSimulation=SIM_DT%iYearOfSimulation

    iUBOUND_FRAGMENTS = ubound( FRAGMENTS, 1)
    iUBOUND_CURRENT_FRAGMENTS = ubound( CURRENT_FRAGMENTS, 1)

    ! if by chance a mismatch in shape-to-grid results in an active cell with *NO* valid
    ! rain gage ID, we need to set the entire array to zero to quash any spurious values getting in 
    FRAGMENT_VALUE = 0.0_c_float

    do iIndex = 1, iMaxRainZones
 
      if ( lShuffle ) then

        call update_random_values()

        iStartRecord = FRAGMENTS_SETS( iIndex )%iStartRecord(iMonth)   
        iNumberOfFragments = FRAGMENTS_SETS(iIndex)%iNumberOfFragments(iMonth)
        iEndRecord = iStartRecord + iNumberOfFragments - 1
        iTargetRecord = iStartRecord + int(RANDOM_VALUES(iIndex) * real( iNumberOfFragments ))

        if ( ( iIndex > iUBOUND_CURRENT_FRAGMENTS ) .or. ( iTargetRecord > iUBOUND_FRAGMENTS )   &
            .or. ( iIndex < 1 ) .or. ( iTargetRecord < 1) ) then
          call LOGS%write("Error detected in method of fragments routine; dump of current"       &
                          //" variables follows:", iLinesBefore=1)
          call LOGS%write("iIndex: "//asCharacter(iIndex), iTab=3 )
          call LOGS%write("iStartRecord: "//asCharacter(iStartRecord), iTab=3 )
          call LOGS%write("iNumberOfFragments: "//asCharacter(iNumberOfFragments), iTab=3 )
          call LOGS%write("iEndRecord: "//asCharacter(iEndRecord), iTab=3 )
          call LOGS%write("iTargetRecord: "//asCharacter(iTargetRecord), iTab=3 )
          call LOGS%write("ubound(CURRENT_FRAGMENTS, 1): "//asCharacter(iUBOUND_CURRENT_FRAGMENTS), &
                          iTab=3 )
          call LOGS%write("ubound(FRAGMENTS, 1): "//asCharacter(iUBOUND_FRAGMENTS), iTab=3 )                    
          call LOGS%write("RANDOM_VALUES(iIndex): "//asCharacter(RANDOM_VALUES(iIndex)), iTab=3 )
          call die( "Miscalculation in target record: calculated record index is out of bounds", &
            __SRCNAME__, __LINE__ )
        endif
          
        CURRENT_FRAGMENTS(iIndex)%pFragment => FRAGMENTS( iTargetRecord )

         write(LU_FRAGMENTS_ECHO,fmt="(4(i5,','),f10.6,',',i5,',',30(f8.3,','),f8.3)")   &
                     iIndex,                                                             &
                     FRAGMENTS( iTargetRecord)%iMonth,                                   &
                     FRAGMENTS( iTargetRecord)%iRainGageZone,                            &                     
                     iYearOfSimulation,                                                  &
                     RANDOM_VALUES(iIndex),                                              &
                     FRAGMENTS( iTargetRecord)%iFragmentSet,                             &
                     FRAGMENTS( iTargetRecord)%fFragmentValue

        ! call LOGS%write( trim(sBuf), iLogLevel=LOG_DEBUG, lEcho=lFALSE )

      endif

      if ( ( CURRENT_FRAGMENTS( iIndex )%pFragment%fFragmentValue( iDay ) < 0.0 ) &
         .or. ( CURRENT_FRAGMENTS( iIndex )%pFragment%fFragmentValue( iDay ) > 1.0 ) ) then

        call LOGS%write("Error detected in method of fragments routine; dump of current variables"  & 
                        //" follows:", iLinesBefore=1, iLogLevel=LOG_ALL )
        call LOGS%write("iIndex:"//asCharacter(iIndex), iTab=3 )
        call LOGS%write("iDay: "//asCharacter(iDay), iTab=3 )
        call LOGS%write("iRainGageZone: "//asCharacter(FRAGMENTS( iTargetRecord)%iRainGageZone), iTab=3 )      
        call LOGS%write("iFragmentSet: "//asCharacter(FRAGMENTS( iTargetRecord)%iFragmentSet), iTab=3 )
        call LOGS%write("fFragmentValue: "//asCharacter(FRAGMENTS( iTargetRecord)%fFragmentValue(iDay) ), iTab=3 )

      endif

      call LOGS%write("frag: "//asCharacter(iIndex)//"  day: "//asCharacter(iDay) &
         //"  value: "//asCharacter( CURRENT_FRAGMENTS( iIndex )%pFragment%fFragmentValue( iDay ) ), &
         lEcho=lFALSE )

      where ( RAIN_GAGE_ID == iIndex )

        FRAGMENT_VALUE = CURRENT_FRAGMENTS( iIndex )%pFragment%fFragmentValue( iDay )

      endwhere  

    enddo  

  end subroutine update_fragments

!--------------------------------------------------------------------------------------------------

  subroutine update_random_values()

    ! [ LOCALS ]
    integer (kind=c_int) :: iIndex, iIndex2
    logical (kind=c_bool) :: lSequenceSelection

    if ( RANDOM_FRAGMENT_SEQUENCES ) then

      call random_number( RANDOM_VALUES )

    else

      RANDOM_VALUES = -9999999.9

      do iIndex=1, size(FRAGMENTS_SEQUENCE%sim_month, 1) 

        lSequenceSelection =       ( FRAGMENTS_SEQUENCE(iIndex)%sim_month == SIM_DT%curr%iMonth )            &
                             .and. ( FRAGMENTS_SEQUENCE(iIndex)%sim_year == SIM_DT%iYearOfSimulation )       &
                             .and. ( FRAGMENTS_SEQUENCE(iIndex)%sim_number == SIMULATION_NUMBER )

        if ( .not. lSequenceSelection ) cycle

        do iIndex2=1,size(RANDOM_VALUES,1)

          if ( FRAGMENTS_SEQUENCE( iIndex )%sim_rainfall_zone == iIndex2 ) then

            RANDOM_VALUES( iIndex2 ) = FRAGMENTS_SEQUENCE( iIndex )%sim_random_number
            exit

          endif

        enddo  

      enddo  

    endif

  end subroutine update_random_values

!--------------------------------------------------------------------------------------------------

  subroutine precipitation_method_of_fragments_calculate( lActive )

    logical (kind=c_bool), intent(in)     :: lActive(:,:)

    ! [ LOCALS ]
    integer (kind=c_int)              :: iIndex
    integer (kind=c_int)              :: iMaxRainZones
    real (kind=c_float), allocatable  :: RANDOM_VALUES(:)
    integer (kind=c_int)              :: iStat
    logical (kind=c_bool), save       :: lFirstCall = lTRUE

    integer (kind=c_int) :: iMonth
    integer (kind=c_int) :: iDay
    integer (kind=c_int) :: iYear
    type (DATA_CATALOG_ENTRY_T), pointer :: pRAINFALL_ADJUST_FACTOR      


    iMonth = SIM_DT%curr%iMonth
    iDay = SIM_DT%curr%iDay
    iYear = SIM_DT%curr%iYear

    ! locate the data structure associated with the gridded rainfall adjustment factor
    pRAINFALL_ADJUST_FACTOR => DAT%find("RAINFALL_ADJUST_FACTOR")

    if ( .not. associated(pRAINFALL_ADJUST_FACTOR) ) &
        call die("A RAINFALL_ADJUST_FACTOR grid must be supplied in order to make use"     &
                 //" of this option.", __SRCNAME__, __LINE__)

    call pRAINFALL_ADJUST_FACTOR%getvalues(iMonth=iMonth, iDay=iDay, iYear=iYear  )

    ! map the 2D array of RAINFALL_ADJUST_FACTOR values to the vector of active cells
    RAINFALL_ADJUST_FACTOR = pack( pRAINFALL_ADJUST_FACTOR%pGrdBase%rData, lActive )
    iMaxRainZones = maxval(FRAGMENTS%iRainGageZone)
    if ( iDay == 1 .or. lFirstCall ) then

      call update_fragments( lShuffle = lTRUE)
      lFirstCall = lFALSE

    else 

      call update_fragments( lShuffle = lFALSE )

    endif  

  end subroutine precipitation_method_of_fragments_calculate

!--------------------------------------------------------------------------------------------------

end module precipitation__method_of_fragments
