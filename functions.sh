#!/bin/sh

create_alpha_band() {

  RASTER=$(realpath ${1})

  DIR=$(realpath ${2})

  generate_raster_footprint \
    --skip-validation --remove-holes --overwrite --nodata 0 --sieve 16 ${RASTER} ${DIR}

  LAYER=$(basename ${1} | sed -r 's/^(.+)\.(.+)$/\1/')

  FOOTPRINT="${DIR}/${LAYER}.gpkg"

  ogrinfo -q -sql "ALTER TABLE '${LAYER}' RENAME TO footprint" ${FOOTPRINT}

  BBOX=$(mktemp -u -q --tmpdir=${TMPDIR} --suffix=".gpkg" XXXXXXXXXXXXXXXX)

  gdaltindex -f GPKG -lyr_name bbox ${BBOX} ${1} 1>/dev/null

  SQL="MBRMinX( geom ) AS x1, MBRMinY( geom ) AS y1, MBRMaxX( geom ) AS x2, MBRMaxY( geom ) AS y2"
  SQL="SELECT ${SQL} FROM bbox"

  CSV1=$(mktemp -u -q --tmpdir=${TMPDIR} --suffix=".csv" XXXXXXXXXXXXXXXX)
  CSV2=$(mktemp -u -q --tmpdir=${TMPDIR} --suffix=".csv" XXXXXXXXXXXXXXXX)

  ogr2ogr -f CSV -sql "${SQL}" ${CSV1} ${BBOX}
  sed -i '1d ; s/,/ /g' ${CSV1}
  read XMIN YMIN XMAX YMAX < ${CSV1}

  gdalinfo ${1} | egrep '^Size' | cut -d' ' -f3- | sed -r 's/,//g' > ${CSV2}
  read COLS ROWS < ${CSV2}

  ALPHA="${DIR}/${LAYER}.alpha.tif"

  gdal_rasterize -q -of GTiff -co COMPRESS=LZW -ot Byte -burn ${3} -l footprint \
    -ts ${COLS} ${ROWS} -te ${XMIN} ${YMIN} ${XMAX} ${YMAX} ${FOOTPRINT} ${ALPHA}

  rm -f ${FOOTPRINT} ${BBOX} ${CSV1} ${CSV2}

  echo ${ALPHA}
}

fix_rgb_background() {

  ALPHA=$(create_alpha_band ${1} ${2} 255)

  DIR=$(dirname ${ALPHA})

  TARGET="${DIR}/$(basename ${ALPHA} | sed -r 's/\.alpha\.tif$/.tif/')"

  R_BAND=$(mktemp -u -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)
  G_BAND=$(mktemp -u -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)
  B_BAND=$(mktemp -u -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)

  gdal_calc.py -A ${1} --A_band=1 -B ${ALPHA} --B_band=1 --type=Byte --format=GTiff --quiet --co=BIGTIFF=YES \
    --NoDataValue=0 --outfile=${R_BAND} --calc="( B != 0 ) * ( A + ( A == 0 ) )" &

  gdal_calc.py -A ${1} --A_band=2 -B ${ALPHA} --B_band=1 --type=Byte --format=GTiff --quiet --co=BIGTIFF=YES \
    --NoDataValue=0 --outfile=${G_BAND} --calc="( B != 0 ) * ( A + ( A == 0 ) )" &

  gdal_calc.py -A ${1} --A_band=3 -B ${ALPHA} --B_band=1 --type=Byte --format=GTiff --quiet --co=BIGTIFF=YES \
    --NoDataValue=0 --outfile=${B_BAND} --calc="( B != 0 ) * ( A + ( A == 0 ) )" &

  wait

  gdal_merge.py -q -o ${TARGET} -ot Byte -of GTiff -co COMPRESS=LZW -co TILED=YES -co BIGTIFF=YES \
    -n 0 -a_nodata 0 -separate ${R_BAND} ${G_BAND} ${B_BAND}

  gdal_edit.py -stats -colorinterp_1 red -colorinterp_2 green -colorinterp_3 blue ${TARGET}

  rm -f ${R_BAND} ${G_BAND} ${B_BAND} ${ALPHA}

  generate_raster_footprint --overwrite ${TARGET} ${DIR}

  return 0
}

fix_rgb_jpeg_collar() {

  ALPHA=$(create_alpha_band ${1} ${2} 1)

  DIR=$(dirname ${ALPHA})

  TARGET="${DIR}/$(basename ${ALPHA} | sed -r 's/\.alpha\.tif$/.tif/')"

  R_BAND=$(mktemp -u -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)
  G_BAND=$(mktemp -u -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)
  B_BAND=$(mktemp -u -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)

  gdal_calc.py -A ${1} --A_band=1 -B ${ALPHA} --B_band=1 --type=Byte --format=GTiff --quiet --co=BIGTIFF=YES \
    --outfile=${R_BAND} --calc="( B != 0 ) * ( A + ( A == 0 ) )" &

  gdal_calc.py -A ${1} --A_band=2 -B ${ALPHA} --B_band=1 --type=Byte --format=GTiff --quiet --co=BIGTIFF=YES \
    --outfile=${G_BAND} --calc="( B != 0 ) * ( A + ( A == 0 ) )" &

  gdal_calc.py -A ${1} --A_band=3 -B ${ALPHA} --B_band=1 --type=Byte --format=GTiff --quiet --co=BIGTIFF=YES \
    --outfile=${B_BAND} --calc="( B != 0 ) * ( A + ( A == 0 ) )" &

  wait

  STACK=$(mktemp -u -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)

  gdal_merge.py -q -o ${STACK} -ot Byte -of GTiff -co BIGTIFF=YES -separate \
    ${R_BAND} ${G_BAND} ${B_BAND} ${ALPHA}

  gdal_translate -q -b 1 -b 2 -b 3 -mask 4 -ot Byte --config GDAL_TIFF_INTERNAL_MASK YES -of GTiff \
    -co COMPRESS=JPEG -co JPEG_QUALITY=80 -co PHOTOMETRIC=YCBCR ${STACK} ${TARGET}

  rm -f ${R_BAND} ${G_BAND} ${B_BAND} ${ALPHA} ${STACK}

  generate_raster_footprint --overwrite --alpha ${TARGET} ${DIR}

  return 0
}
