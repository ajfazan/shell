#!/bin/sh

fix_rgb_background() {

  DIR=$(realpath ${2})

  cp ${1} ${DIR}

  generate_raster_footprint --remove-holes --overwrite ${1} ${DIR}

  LAYER=$(basename ${1} | sed -r 's/^(.+)\.(.+)$/\1/')

  FOOTPRINT="${DIR}/${LAYER}.gpkg"

  TARGET="${DIR}/${LAYER}.tif"

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

  R_BAND=$(mktemp -u -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)
  G_BAND=$(mktemp -u -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)
  B_BAND=$(mktemp -u -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)
  A_BAND=$(mktemp -u -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)

  gdal_rasterize -q -of GTiff -ot Byte -burn 255 -l footprint -ts ${COLS} ${ROWS} \
    -te ${XMIN} ${YMIN} ${XMAX} ${YMAX} ${FOOTPRINT} ${A_BAND}

  gdal_edit.py -unsetnodata ${TARGET}

  gdal_calc.py -A ${TARGET} --A_band=1 -B ${A_BAND} --B_band=1 --type=Byte --format=GTiff --quiet \
    --NoDataValue=0 --outfile=${R_BAND} --calc="( A * ( B != 0 ) ) + ( A == 0 ) * ( B != 0 )" &

  gdal_calc.py -A ${TARGET} --A_band=2 -B ${A_BAND} --B_band=1 --type=Byte --format=GTiff --quiet \
    --NoDataValue=0 --outfile=${G_BAND} --calc="( A * ( B != 0 ) ) + ( A == 0 ) * ( B != 0 )" &

  gdal_calc.py -A ${TARGET} --A_band=3 -B ${A_BAND} --B_band=1 --type=Byte --format=GTiff --quiet \
    --NoDataValue=0 --outfile=${B_BAND} --calc="( A * ( B != 0 ) ) + ( A == 0 ) * ( B != 0 )" &

  wait

  gdal_merge.py -q -o ${TARGET} -ot Byte -of GTiff -n 0 -a_nodata 0 -separate \
    ${R_BAND} ${G_BAND} ${B_BAND}

  gdal_edit.py -stats -colorinterp_1 red -colorinterp_2 green -colorinterp_3 blue ${TARGET}

  rm -f ${R_BAND} ${G_BAND} ${B_BAND} ${A_BAND} ${BBOX} ${CSV1} ${CSV2}

  return 0
}
