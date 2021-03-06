program test_file_utils

  use constants_and_conversions
  use file_utilities
  use strings
  implicit none

  character (len=:), allocatable :: mydir

  call mkdir( "testdir")

  call get_cwd( mydir )
  print *, "Current directory is: "//dquote( mydir )

  call chdir( trim(mydir)//"/testdir" )

  call get_cwd( mydir )

  print *, "Changed directories. Current directory is: "//dquote( mydir )

end program test_file_utils