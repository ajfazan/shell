#!/bin/sh

if [ ${#} -ne 2 ]; then

  printf "Usage:\n\t%s <DEM_FILE> <OUT_DIR>\n\n" $(basename ${0})
  exit 4

fi

if [ ! -f ${1} ]; then

  echo "First input argument must be a file"
  exit 1

fi

if [ ! -d ${2} ]; then

  echo "Second input argument must be a directory"
  exit 2

fi

TARGET="${2}/$(basename ${1} | sed -r 's/^(.+)\.(.+)$/\1/').tif"

gdal_calc.py -A ${1} --NoDataValue=-32767 --type=Float32 --format=GTiff --quiet --overwrite \
  --calc="A * numpy.logical_and( A > 5e-4, A <= 3200.0 ) - 32767.0 * ( A <= 0.0 )" \
  --outfile=${TARGET} --co=COMPRESS=LZW --co=BIGTIFF=YES --co=TILED=YES

gdal_edit.py -stats ${TARGET}

generate_raster_footprint --overwrite ${TARGET} ${2}
