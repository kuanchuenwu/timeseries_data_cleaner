# timeseries_data_cleaner

Time-series data can come from multiple sources or conform to different conventions (e.g. date/time formats), thus requiring several ETL data "cleaning" processes (e.g. de-duplication, missing data imputation, format conversion) to produce consistent data that can then be analyzed and fed to machine learning A.I. models.  Furthermore, specifically for time-series, the data should undergo timescale standardization; for instance, if series A is monthly, series B is weekly, and series C is daily, then series A and series B are often transformed to become daily, i.e. the finest timescale resolution in the dataset.

The previously described time-series ETL operations are performed by the all-original, custom-coded function written in Matlab.
