#!/bin/sh

fix_rgb_background() {

  DIR=$(mktemp --directory --tmpdir=${2} XXXXXXXXXXXXXXXX)

  generate_raster_footprint --overwrite --remove-holes --nodata 0 --sieve 16 \
    --format GTiff ${1} ${2}

  BASE=$(basename ${1} | sed -r 's/^(.+)\.(.+)$/\1/')

  ALPHA="${DIR}/${BASE}.tif"

  raster_tools --overwrite --compress --stats --nodata 0 --alphafix ${ALPHA} ${1} ${2}

  TARGET="${2}/${BASE}.tif"

  rm -rf ${DIR}

  generate_raster_footprint --overwrite ${TARGET} ${2}

  return 0
}

fix_rgb_jpeg_collar() {

  DIR=$(mktemp --directory --tmpdir=${2} XXXXXXXXXXXXXXXX)

  generate_raster_footprint --overwrite --remove-holes --nodata 0 --sieve 16 \
    --format GTiff ${1} ${2}

  BASE=$(basename ${1} | sed -r 's/^(.+)\.(.+)$/\1/')

  ALPHA="${DIR}/${BASE}.tif"

  R_BAND=$(mktemp --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)
  G_BAND=$(mktemp --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)
  B_BAND=$(mktemp --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)

  gdal_calc.py -A ${1} --A_band=1 -B ${ALPHA} --B_band=1 --format=GTiff --co=BIGTIFF=YES \
    --type=Byte --quiet --overwrite --outfile=${R_BAND} --calc="( B != 0 ) * ( A + ( A == 0 ) )" &

  gdal_calc.py -A ${1} --A_band=2 -B ${ALPHA} --B_band=1 --format=GTiff --co=BIGTIFF=YES \
    --type=Byte --quiet --overwrite --outfile=${G_BAND} --calc="( B != 0 ) * ( A + ( A == 0 ) )" &

  gdal_calc.py -A ${1} --A_band=3 -B ${ALPHA} --B_band=1 --format=GTiff --co=BIGTIFF=YES \
    --type=Byte --quiet --overwrite --outfile=${B_BAND} --calc="( B != 0 ) * ( A + ( A == 0 ) )" &

  wait

  STACK=$(mktemp --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)

  gdal_merge.py -q -o ${STACK} -ot Byte -of GTiff -co BIGTIFF=YES -separate \
    ${R_BAND} ${G_BAND} ${B_BAND} ${ALPHA}

  TARGET="${2}/${BASE}.tif"

  gdal_translate -q -b 1 -b 2 -b 3 -mask 4 -ot Byte --config GDAL_TIFF_INTERNAL_MASK YES -of GTiff \
    -co COMPRESS=JPEG -co JPEG_QUALITY=80 -co PHOTOMETRIC=YCBCR ${STACK} ${TARGET}

  rm -f ${R_BAND} ${G_BAND} ${B_BAND} ${STACK}

  rm -rf ${DIR}

  generate_raster_footprint --overwrite --alpha ${TARGET} ${2}

  return 0
}
