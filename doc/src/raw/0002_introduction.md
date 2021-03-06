# Introduction {#introduction}

Accurate estimates of the spatial and temporal distribution of recharge are important for many types of hydrologic assessments, including those that concern water-quality protection, streamflow and riparian ecosystem management, aquifer replenishment, groundwater-flow modeling, and contaminant transport; these recharge estimates are often key to understanding the effects of development in urban, industrial, and agricultural regions. With increasing demand for hydrologic assessments in support of management decisions comes an increased need for practical methods to quantify recharge rates and delineate zones of similar recharge [@scanlon_choosing_2002].

The code calculates components of the water balance at a daily timestep by means of a modified version of the Thornthwaite-Mather soil-moisture-balance approach [@thornthwaite_approach_1948; @thornthwaite_instructions_1957]. Data requirements include several commonly available tabular and gridded data types: (1) precipitation and temperature, (2) land-use classification, (3) hydrologic soil group, (4) flow direction and (5) soil-water capacity. The data and formats required are designed to take advantage of widely available GIS datasets and file structures.

There is often a tradeoff between a modeling package's ease of use and its ability to simulate detail in a problem. SWB is no exception. The Soil-Water-Balance code can be easily used to estimate potential recharge in a wide variety of environmental settings. The inputs to the model are flexible; the user may define as many classes of soils as needed in order to capture important features.

Two versions of the Soil-Water-Balance code now exist (versions 1.0 and 2.0). Version 2.0 simulates all of the processes that Version 1.0 does. 

