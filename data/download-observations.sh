#!/bin/bash

## downloaded from "https://www1.ncdc.noaa.gov/pub/data/noaa/{year}/{usaf}-{wban}-{year}.gz"

## Barcelona el prat airport usaf-wban code is 081810-99999
mkdir -p observations
cd observations

for year in `seq 2007 2016`; do
    wget https://www1.ncdc.noaa.gov/pub/data/noaa/$year/081810-99999-$year.gz
done
