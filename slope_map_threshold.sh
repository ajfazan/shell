#!/bin/sh

TMP=$(mktemp -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)

gdaldem slope -q -of GTiff -co COMPRESS=LZW ${1} ${TMP}

gdal_calc.py -A ${TMP} --calc="127 * ( A >= ${3} )" --type=Byte --format=GTiff --co=COMPRESS=LZW \
  --NoDataValue=0 --outfile=${2} --quiet --overwrite

gdal_edit.py -ro -stats ${2}

rm -f ${TMP}
