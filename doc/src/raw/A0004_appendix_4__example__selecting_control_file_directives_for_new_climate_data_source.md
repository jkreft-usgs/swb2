# Appendix 4. Example of control file setting selection for a new climate data source.

New sources of gridded climate data are continuing to come online. Inevitably, these new climate data sources will require that the SWB control file directives be modified in order to work properly. This example shows the process used to configure SWB control file parameters for a set of downscaled climate model results produced by a consortium of agencies including USGS, BLM, NCAR, U.S. Army Corps. of Engineers, and others (Brekke and others, 2013), available here:

 http://gdo-dcp.ucllnl.org/downscaled_cmip_projections/dcpInterface.html.

For this example, we downloaded model results for a single climate scenario, for a subset of the national grid. As will be shown later, sometimes the tools employed in creating the data subset end up changing the output NetCDF file in a way that prevents it from being used with SWB.
Once the necessary NetCDF files have been downloaded to a local hard drive, the metadata they contain should be examined. A simple command-line tool that can accomplish this is called “ncdump”, distributed by Unidata. As of February, 2016, it is available as part of the NetCDF C library for Windows, which may be obtained here: http://www.unidata.ucar.edu/software/netcdf/docs/winbin.html. Once the library is installed, ncdump may be run at the command line to extract the metadata.

```
>C:\”Program Files\netCDF 4.4.0”\bin\ncdump –h Extraction_pr.nc
```

The output from running this command is shown below.

```
netcdf Extraction_pr {
dimensions:
        longitude = 129 ;
        latitude = 64 ;
        time = 2557 ;
        projection = UNLIMITED ; // (1 currently)
variables:
        float longitude(longitude) ;
                longitude:standard_name = "longitude" ;
                longitude:long_name = "Longitude" ;
                longitude:units = "degrees_east" ;
                longitude:axis = "X" ;
        float latitude(latitude) ;
                latitude:standard_name = "latitude" ;
                latitude:long_name = "Latitude" ;
                latitude:units = "degrees_north" ;
                latitude:axis = "Y" ;
        double time(time) ;
                time:standard_name = "time" ;
                time:long_name = "time" ;
                time:units = "days since 1950-01-01 00:00:00" ;
                time:calendar = "standard" ;
        float pr(projection, time, latitude, longitude) ;
                pr:standard_name = "precipitation_flux" ;
                pr:long_name = "Precipitation" ;
                pr:units = "mm/d" ;
                pr:_FillValue = 1.e+020f ;
                pr:missing_value = 1.e+020f ;
                pr:typeConversion_op_ncl = "double converted to float" ;
                pr:cell_methods = "time: mean" ;
                pr:interp_method = "conserve_order1" ;
                pr:original_units = "kg/m2/s" ;
                pr:original_name = "precip" ;
                pr:associated_files = "baseURL: http://cmip-pcmdi.llnl.gov/CMIP5/dataLocation areacella: areacella_fx_GFDL-CM3_rcp26_r0i0p0.nc" ;
                pr:time = 38716.5 ;

// global attributes:
                :CDI = "Climate Data Interface version 1.6.2 (http://code.zmaw.de/projects/cdi)" ;
                :Conventions = "CF-1.4" ;
                :history = "12/2014 corrected the historical bias in the mean" ;
                :institution = "NOAA GFDL(201 Forrestal Rd, Princeton, NJ, 08540)" ;
                :institute_id = "NOAA GFDL" ;
                :model_id = "GFDL-CM3" ;
                :frequency = "day" ;
                :experiment = "RCP2.6" ;
                :experiment_id = "rcp26" ;
                :parent_experiment_id = "historical" ;
                :parent_experiment_rip = "r1i1p1" ;
                :creation_date = "Mon Sep 10 22:41:18 PDT 2012" ;
                :references = "Daily BC method: modified version of Maurer EP, Hidalgo HG, Das T, Dettinger MD, Cayan DR, 2010, Hydrol Earth Syst Sci 14:1125-1138\n",
                        "CA method: Hidalgo HG, Dettinger MD, Cayan DR, 2008, California Energy Commission technical report CEC-500-2007-123\n",
                        "Reference period obs: updated version of Maurer EP, Wood AW, Adam JC, Lettenmaier DP, Nijssen B, 2002, J Climate 15(22):3237ΓÇô3251, \n",
                        "provided via http://www.engr.scu.edu/~emaurer/gridded_obs/index_gridded_obs.html" ;
                :contacts = "Bridget Thrasher: bridget@climateanalyticsgroup.org or Ed Maurer: emaurer@scu.edu" ;
                :documentation = "http://gdo-dcp.ucllnl.org" ;
                :NCO = "4.0.8" ;
                :CDO = "Climate Data Operators version 1.6.2 (http://code.zmaw.de/projects/cdo)" ;
                :Projections = "gfdl-cm3.1.rcp26, " ;
}
```

There is a lot of useful information in this particular set of metadata. NetCDF files of this sort typically have a number of dimensions and variables defined in the first part of the file description. In this example, four dimensions are defined: longitude, latitude, time, and projection. In addition, the file contains four variables: longitude, latitude, time, and pr (precipitation). Three of the variable names are also names of dimensions. The dimension “longitude” in this case refers to a set of index values ranging from 0 to 128. The variable “longitude” contains the actual longitudinal value associated with each of the indices contained in the longitude dimension.
```
C:\"Program Files\netCDF 4.4.0"\bin\ncdump -v longitude Extraction_pr.nc
```

Running ncdump with the “-v” option and a variable name returns a list of all variable values:

```
longitude = 251.9375, 252.0625, 252.1875, 252.3125, 252.4375, 252.5625,
   252.6875, 252.8125, 252.9375, 253.0625, 253.1875, 253.3125, 253.4375,
   253.5625, 253.6875, 253.8125, 253.9375, 254.0625, 254.1875, 254.3125,
   254.4375, 254.5625, 254.6875, 254.8125, 254.9375, 255.0625, 255.1875,
   255.3125, 255.4375, 255.5625, 255.6875, 255.8125, 255.9375, 256.0625,
   256.1875, 256.3125, 256.4375, 256.5625, 256.6875, 256.8125, 256.9375,
   257.0625, 257.1875, 257.3125, 257.4375, 257.5625, 257.6875, 257.8125,
   257.9375, 258.0625, 258.1875, 258.3125, 258.4375, 258.5625, 258.6875,
   258.8125, 258.9375, 259.0625, 259.1875, 259.3125, 259.4375, 259.5625,
   259.6875, 259.8125, 259.9375, 260.0625, 260.1875, 260.3125, 260.4375,
   260.5625, 260.6875, 260.8125, 260.9375, 261.0625, 261.1875, 261.3125,
   261.4375, 261.5625, 261.6875, 261.8125, 261.9375, 262.0625, 262.1875,
   262.3125, 262.4375, 262.5625, 262.6875, 262.8125, 262.9375, 263.0625,
   263.1875, 263.3125, 263.4375, 263.5625, 263.6875, 263.8125, 263.9375,
   264.0625, 264.1875, 264.3125, 264.4375, 264.5625, 264.6875, 264.8125,
   264.9375, 265.0625, 265.1875, 265.3125, 265.4375, 265.5625, 265.6875,
   265.8125, 265.9375, 266.0625, 266.1875, 266.3125, 266.4375, 266.5625,
   266.6875, 266.8125, 266.9375, 267.0625, 267.1875, 267.3125, 267.4375,
   267.5625, 267.6875, 267.8125, 267.9375 ;
```

An interesting this to note about the values of longitude is that they seem unusual relative to the longitudes we are used to working with in North America. Indeed, this example dataset is centered on the state of Nebraska, USA; we commonly would see the longitude values range from about 108° to 93° West longitude, perhaps expressed as -108° to -93°. Many of the downscaled climate model datasets refer to longitude as ranging from 0° to 360°, with the longitude of 0°/360° centered on the parallel running through Greenwich, England. If we subtract 360° from the longitude values above, the range looks more familiar: 251°-360°=-108°; 267°-360°=-93°. Presumably the reason for defining longitudes this way is because it is easier to have model grid for which all longitude values are greater than zero!

One item we need to look at first is the organization of the data of interest on the disk file. SWB expects climate data files to be arranged in such a way that the data may be accessed by referencing a specific datetime, y-coordinate, and x-coordinate value. The precipitation variable we are interested in is dimensioned as follows:

```
float pr(projection, time, latitude, longitude) ;
```

SWB is written under the assumption that the variable of interest will be referenced by just three dimensions: time, x, and y. The fourth dimension listed above, projection, was added apparently to allow results for more than one climate emissions scenario to be stored in a single NetCDF file. In order to use this file with SWB we must get rid of this fourth dimension.
To remove the fourth dimension, we can use a third-party tool called NCO, NetCDF Climate Operators, to calculate an “average” over the fourth dimension. Because there is only a single projection contained in the file, the resulting file will be the same as the input file *without* the projection dimension. NCO as available at: http://nco.sourceforge.net/. As of February, 2016, a Windows executable for NCO may be found here: http://nco.sourceforge.net/src/nco-4.5.4.windows.mvs.exe.

The NCO package is not overly user friendly. Luckily, it has a helpful discussion page, which suggests that to eliminate a “degenerate” dimension (a dimension with only a single value), the “averaging” tool may be used:

```
ncwa -a projection Extraction_pr.nc Extraction_pr_3d.nc
```

ncwa stands for “NetCDF Weighted Averager”. The “-a” flag allows one to specify a dimension over which to average (“projection”). The last two entries are the input and output filenames, respectively. Once this command-line utility is run, the NetCDF files are rendered usable by SWB.
With all of the metadata available we can finally generate the SWB control file statements to make this file work with SWB:

```
# 001: specify the filename containing precipitation data
PRECIPITATION NETCDF Extraction_pr_3D.nc

# 002: define PRECIPITATION projection and NetCDF variable names
PRECIPITATION_GRID_PROJECTION_DEFINITION +proj=lonlat +ellps=GRS80 +datum=NAD83 +lon_wrap=180 +no_defs
NETCDF_PRECIP_X_VAR longitude
NETCDF_PRECIP_Y_VAR latitude
NETCDF_PRECIP_Z_VAR pr

# 003: define PRECIPITATION missing values action
PRECIPITATION_MISSING_VALUES_CODE 1.0E+20
PRECIPITATION_MISSING_VALUES_OPERATOR >=
PRECIPITATION_MISSING_VALUES_ACTION ZERO

# 004: PRECIPITATION is given in mm/day; need to convert to inches/day
PRECIPITATION_SCALE_FACTOR 0.03937008
```

The first line of the control file snippet above specifies the name of the NetCDF file that contains the precipitation data we wish to use.

The commands under group 002 define the geographic projection and specify the variable names. In this case, the exact projection of the data is unknown; in any event climate models rarely seem to reflect anything other than a global (unprojected) coordinate system. It is not clear from the metadata what datum was used in defining the latitude and longitude. We’ll guess NAD83 with an ellipsoid specified by GRS80. Downscaled climate model cells are generally far larger than the error we would incur by selecting the wrong datum and ellipsoid. Note that this dataset requires the “+lon_wrap=180” addition to the projection definition. This is required in order to convert the longitude values to +/- 180°. The variable names are found in the metadata and must be supplied in the control file in order for SWB to find them: x=> “longitude”, y=>”latitude”, z=”pr”.

The commands under group 003 specify what actions SWB should take in the event it encounters missing values within the file. The first line defines the numeric value associated with a missing value. The second line defines the operator, which can be one of  “<”, “<=”, “>”, “>=”. The third line specifies what should be done with the missing value. In this case, we’ve specified that any values >= 1.0E+20 will be treated as 0.0.

The command under group 004 informs SWB how the values in the file are to be converted to inches per day. The PRECIPITATION_SCALE_FACTOR of 0.03937 = 1.0 / 25.4, or one over the number of millimeters per inch.
