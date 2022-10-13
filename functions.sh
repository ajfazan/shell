#!/bin/sh

create_alpha_band() {

  generate_raster_footprint \
    --skip-validation --remove-holes --overwrite --nodata 0 --sieve 16 ${1} ${2}

  LAYER=$(basename ${1} | sed -r 's/^(.+)\.(.+)$/\1/')

  FOOTPRINT="${2}/${LAYER}.gpkg"

  ogrinfo -q -sql "ALTER TABLE '${LAYER}' RENAME TO footprint" ${FOOTPRINT}

  ogrinfo -q -sql "DELETE FROM footprint WHERE ( area < 1.0 )" ${FOOTPRINT}

  BBOX="${2}/${LAYER}.bbox.gpkg"

  gdaltindex -f GPKG -lyr_name bbox ${BBOX} ${1} 1>/dev/null

  SQL="MBRMinX( geom ) AS x1, MBRMinY( geom ) AS y1, MBRMaxX( geom ) AS x2, MBRMaxY( geom ) AS y2"
  SQL="SELECT ${SQL} FROM bbox"

  CSV1=$(mktemp --tmpdir=${TMPDIR} --suffix=".csv" XXXXXXXXXXXXXXXX)
  CSV2=$(mktemp --tmpdir=${TMPDIR} --suffix=".csv" XXXXXXXXXXXXXXXX)

  ogr2ogr -f CSV -sql "${SQL}" ${CSV1} ${BBOX}
  sed -i '1d ; s/,/ /g' ${CSV1}
  read XMIN YMIN XMAX YMAX < ${CSV1}

  gdalinfo ${1} | egrep '^Size' | cut -d' ' -f3- | sed -r 's/,//g' > ${CSV2}
  read COLS ROWS < ${CSV2}

  ALPHA="${2}/${LAYER}.alpha.tif"

  gdal_rasterize -q -of GTiff -co COMPRESS=LZW -ot Byte -burn ${3} -l footprint \
    -ts ${COLS} ${ROWS} -te ${XMIN} ${YMIN} ${XMAX} ${YMAX} ${FOOTPRINT} ${ALPHA}

  rm -f ${FOOTPRINT} ${BBOX} ${CSV1} ${CSV2}

  return 0
}

fix_rgb_background() {

  create_alpha_band ${1} ${2} 255

  BASE=$(basename ${1} | sed -r 's/^(.+)\.(.+)$/\1/')

  ALPHA="${2}/${BASE}.alpha.tif"

  raster_calc --overwrite --compress --stats --nodata 0 --mask ${ALPHA} ${1} ${2}

  TARGET="${2}/${BASE}.tif"

  rm -f ${ALPHA}

  generate_raster_footprint --overwrite ${TARGET} ${2}

  return 0
}

fix_rgb_jpeg_collar() {

  create_alpha_band ${1} ${2} 1

  BASE=$(basename ${1} | sed -r 's/^(.+)\.(.+)$/\1/')

  ALPHA="${2}/${BASE}.alpha.tif"

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

  rm -f ${R_BAND} ${G_BAND} ${B_BAND} ${ALPHA} ${STACK}

  generate_raster_footprint --overwrite --alpha ${TARGET} ${2}

  return 0
}
